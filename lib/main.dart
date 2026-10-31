import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// FB Live Tool — V2 (Android APK, Flutter)
// Facebook Live ONLY.
//
// V2, jo V1 mein NAHI tha, ab hai:
//  1) Page Selection — Pages save karein (naam + Stream Key), dropdown se chunein.
//  2) Account Linking — Facebook login (OAuth) ke liye Meta App Review chahiye,
//     is liye V2 mein linking = Page ka Stream Key Live Producer se copy kar ke
//     yahan save karna hai. Yehi tareeqa foran kaam karta hai, bina review ke.
//     Stream Key kabhi chat mein mat bhejna, sirf app ke andar daalein.
//  3) Video Link paste — Source: File / YouTube Link / Facebook Link / Direct Link.
//     YouTube: youtube_explode se direct stream URL nikaal kar FFmpeg ko diya jata hai.
//     Facebook: public video page se direct video URL dhoondne ki koshish ki jati hai;
//     agar na mile to app saaf error dega — phir file download kar ke File mode use karein.
//     Direct: .mp4 / .m3u8 link seedha FFmpeg input ban jata hai.
//  4) Copyright Text — footer mein sliding text (left to right), user rule ke mutabiq.
//  5) Logo Watermark Upload — apna PNG logo gallery se chunein, top-right par lagega
//     (image watermark = top-right, user rule 2026-10-30). Na chunein to default AlifYa icon lagega.
// Test Mode: 10-second local MP4, bina Stream Key ke, watermark + text check karne ke liye.
// Sirf apni ya ijazat wali video use karein — doosre ki video se copyright strike
// ya Page restriction lag sakta hai.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FFmpegKitExtended.initialize();
  runApp(const FBLiveApp());
}

class FBLiveApp extends StatelessWidget {
  const FBLiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FB Live Tool',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class _Page {
  final String name;
  final String rtmp;
  final String key;
  _Page({required this.name, required this.rtmp, required this.key});
  Map<String, dynamic> toJson() => {'name': name, 'rtmp': rtmp, 'key': key};
  static _Page fromJson(Map<String, dynamic> j) => _Page(
        name: (j['name'] ?? '') as String,
        rtmp: (j['rtmp'] ?? 'rtmps://live-api-s.facebook.com:443/rtmp/') as String,
        key: (j['key'] ?? '') as String,
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _rtmpController =
      TextEditingController(text: 'rtmps://live-api-s.facebook.com:443/rtmp/');
  final _keyController = TextEditingController();
  final _pageNameController = TextEditingController();
  final _linkController = TextEditingController();
  final _copyrightController = TextEditingController();

  String _videoPath = '';
  String _customLogoPath = '';
  String _status = 'Ready. Pehle Test Mode se check karein.';
  String _log = '';
  String _testOutputPath = '';
  String _position = 'top-right';
  bool _loop = true;
  bool _testMode = true;
  bool _running = false;

  // V2 state
  String _source = 'file'; // file | link
  String _linkType = 'youtube'; // youtube | facebook | direct
  List<_Page> _pages = [];
  String? _selectedPageName;

  static const _positions = {
    'bottom-right': 'W-w-20:H-h-20',
    'bottom-left': '20:H-h-20',
    'top-right': 'W-w-20:20',
    'top-left': '20:20',
  };

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<File> _pagesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pages.json');
  }

  Future<void> _loadPages() async {
    try {
      final f = await _pagesFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as List;
      final pages = raw
          .map((e) => _Page.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _pages = pages;
        if (pages.isNotEmpty) {
          _selectedPageName = pages.first.name;
          _applyPage(pages.first);
        }
      });
    } catch (_) {
      // Pages file kharab ho to ignore karein, app nahi rukegi.
    }
  }

  Future<void> _savePages() async {
    try {
      final f = await _pagesFile();
      await f.writeAsString(
          jsonEncode(_pages.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  void _applyPage(_Page p) {
    _rtmpController.text = p.rtmp;
    _keyController.text = p.key;
  }

  Future<void> _saveCurrentPage() async {
    final name = _pageNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _status = 'Page save karne ke liye pehle Page ka naam likhein.');
      return;
    }
    final p = _Page(
      name: name,
      rtmp: _rtmpController.text.trim(),
      key: _keyController.text.trim(),
    );
    setState(() {
      _pages.removeWhere((e) => e.name == name);
      _pages.add(p);
      _selectedPageName = name;
      _status = 'Page "$name" save ho gaya. Ab dropdown se isko select kar sakte hain.';
    });
    await _savePages();
  }

  Future<void> _deleteSelectedPage() async {
    final name = _selectedPageName;
    if (name == null) return;
    setState(() {
      _pages.removeWhere((e) => e.name == name);
      _selectedPageName = _pages.isEmpty ? null : _pages.first.name;
      if (_selectedPageName != null) {
        _applyPage(_pages.firstWhere((e) => e.name == _selectedPageName));
      }
      _status = 'Page "$name" delete ho gaya.';
    });
    await _savePages();
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _videoPath = file.path;
        _status = 'Video chuna gaya.';
      });
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _customLogoPath = file.path;
        _status = 'Logo chuna gaya — ye top-right par watermark banega.';
      });
    }
  }

  Future<String> _watermarkPath() async {
    if (_customLogoPath.isNotEmpty) return _customLogoPath;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/watermark.png');
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/watermark.png');
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }

  String? _fontPath() {
    for (final p in [
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      '/system/fonts/DroidSans.ttf',
    ]) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  String _escapeDrawtext(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll(':', '\\:')
        .replaceAll('%', '\\%');
  }

  Future<String> _resolveLinkInput() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) throw 'Link khaali hai. Pehle link paste karein.';
    if (_linkType == 'direct') return link;
    if (_linkType == 'youtube') {
      final yt = YoutubeExplode();
      try {
        final video = await yt.videos.get(link);
        final manifest = await yt.videos.streamsClient.getManifest(video.id);
        final muxed = manifest.muxed.toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
        if (muxed.isEmpty) {
          throw 'Is YouTube video ka direct (muxed) stream nahi mila. Video download kar ke File mode use karein.';
        }
        return muxed.first.url.toString();
      } finally {
        yt.close();
      }
    }
    // facebook
    if (link.toLowerCase().contains('.mp4')) return link;
    final res = await http.get(
      Uri.parse(link),
      headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36'},
    );
    final body = res.body;
    final patterns = [
      RegExp(r'"playable_url"\s*:\s*"([^"]+)"'),
      RegExp(r'"playable_url_quality_hd"\s*:\s*"([^"]+)"'),
      RegExp(r'<meta property="og:video" content="([^"]+)"'),
      RegExp(r'"hd_src"\s*:\s*"([^"]+)"'),
      RegExp(r'"sd_src"\s*:\s*"([^"]+)"'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(body);
      if (m != null) {
        final u = m.group(1)!.replaceAll(r'\u0026', '&').replaceAll(r'\/', '/');
        if (u.startsWith('http')) return u;
      }
    }
    throw 'Facebook video ka direct link nahi mila (sirf public video kaam karta hai). Video download kar ke File mode use karein.';
  }

  Future<void> _start() async {
    String inputPath;
    if (_source == 'file') {
      if (_videoPath.isEmpty) {
        setState(() => _status = 'Pehle video chunein, ya Source = Link chunein.');
        return;
      }
      inputPath = _videoPath;
    } else {
      setState(() => _status = 'Link resolve ho raha hai...');
      try {
        inputPath = await _resolveLinkInput();
      } catch (e) {
        setState(() {
          _status = 'Link resolve FAILED: $e';
          _running = false;
        });
        return;
      }
    }
    if (!_testMode && _keyController.text.trim().isEmpty) {
      setState(() => _status = 'Facebook Stream Key dein, ya Test Mode on karein.');
      return;
    }

    final wmPath = await _watermarkPath();
    final pos = _positions[_position]!;
    final copyright = _copyrightController.text.trim();
    final font = copyright.isNotEmpty ? _fontPath() : null;
    String filter;
    if (font != null) {
      // Watermark (image, top-right rule) + copyright text (footer, sliding left to right).
      filter =
          '[0:v]scale=1280:720:force_original_aspect_ratio=decrease,'
          'pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v0];'
          '[1:v]scale=230:-1[wm];'
          '[v0][wm]overlay=$pos[vtmp];'
          "[vtmp]drawtext=fontfile=$font:text='${_escapeDrawtext(copyright)}':"
          "fontsize=36:fontcolor=white:box=1:boxcolor=black@0.5:"
          "x='mod(t*120\\,w+tw)-tw':y='h-th-20'[vout]";
    } else {
      if (copyright.isNotEmpty) {
        setState(() => _status = 'Copyright text ke liye phone mein font nahi mila, text ke baghair chal raha hai.');
      }
      filter =
          '[0:v]scale=1280:720:force_original_aspect_ratio=decrease,'
          'pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v0];'
          '[1:v]scale=230:-1[wm];'
          '[v0][wm]overlay=$pos[vtmp];[vtmp]format=yuv420p[vout]';
    }

    String output;
    String outFormat;
    String extra = '';
    if (_testMode) {
      final dir = await getApplicationDocumentsDirectory();
      _testOutputPath = '${dir.path}/test-output.mp4';
      output = _testOutputPath;
      outFormat = 'mp4';
      extra = '-t 10';
    } else {
      final rtmp = _rtmpController.text.trim().replaceAll(RegExp(r'/+$'), '');
      output = '$rtmp/${_keyController.text.trim()}';
      outFormat = 'flv';
    }

    final loopPart = _loop ? '-stream_loop -1 ' : '';
    final command =
        '${loopPart}-re -i "$inputPath" -i "$wmPath" '
        '-filter_complex "$filter" '
        '-map "[vout]" -map "0:a?" '
        '-c:v libx264 -preset veryfast -maxrate 2500k -bufsize 5000k '
        '-pix_fmt yuv420p -g 60 -c:a aac -b:a 128k '
        '$extra -f $outFormat "$output"';

    setState(() {
      _running = true;
      _status = _testMode
          ? 'Test chal raha hai (10 sec)...'
          : 'Streaming shuru ho raha hai. Facebook Live Producer mein PREVIEW check karein, phir wahan Go Live dabayein.';
      _log = '';
    });

    FFmpegKit.executeAsync(
      command,
      onComplete: (session) async {
        if (!mounted) return;
        final returnCode = session.getReturnCode();
        setState(() {
          _running = false;
          if (ReturnCode.isSuccess(returnCode)) {
            _status = _testMode
                ? 'Test complete. File: $_testOutputPath'
                : 'Stream khatam ho gaya.';
          } else if (ReturnCode.isCancel(returnCode)) {
            _status = 'Stream rok diya gaya.';
          } else {
            _status = 'Stream FAILED. Neeche log check karein.';
            _log = session.getFailStackTrace() ?? '';
          }
        });
      },
      onLog: (log) {
        _log = log.message;
      },
      onStatistics: (statistics) {
        if (!mounted || !_running) return;
        setState(() {
          _status = _testMode
              ? 'Test chal raha hai...'
              : 'LIVE chal raha hai... (${(statistics.time / 1000).toStringAsFixed(0)} sec)';
        });
      },
    );
  }

  Future<void> _stop() async {
    // cancelAllSessions() returns void in ffmpeg_kit_extended 1.0.0 - must NOT be awaited.
    FFmpegKitExtended.cancelAllSessions();
    if (mounted) {
      setState(() {
        _running = false;
        _status = 'Stop dabaya gaya. Facebook mein bhi End Live Video dabayein.';
      });
    }
  }

  @override
  void dispose() {
    _rtmpController.dispose();
    _keyController.dispose();
    _pageNameController.dispose();
    _linkController.dispose();
    _copyrightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FB Live Tool — V2')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Facebook Live ONLY — Page + Link + Watermark + Copyright',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // ---- 1) PAGE SELECTION + ACCOUNT LINKING ----
            const Text('1) Page Selection + Account Linking',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
              'Account Linking ka matlab is app mein: Facebook login (OAuth) ke liye Meta App Review chahiye, '
              'is liye yahan Page ka Stream Key Live Producer se copy kar ke save karein. '
              'facebook.com/live/producer kholein, Page chunein, Stream Key copy karein, yahan paste karein, Save Page dabayein. '
              'Stream Key kabhi chat mein mat bhejna.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_pages.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedPageName,
                decoration: const InputDecoration(
                  labelText: 'Page chunein (saved pages)',
                  border: OutlineInputBorder(),
                ),
                items: _pages
                    .map((p) => DropdownMenuItem(value: p.name, child: Text(p.name)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final p = _pages.firstWhere((e) => e.name == v);
                  setState(() {
                    _selectedPageName = v;
                    _applyPage(p);
                  });
                },
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _pageNameController,
              decoration: const InputDecoration(
                labelText: 'Naye Page ka naam (masalan: AlifYa AI Page)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rtmpController,
              decoration: const InputDecoration(
                labelText: 'Facebook RTMP URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Facebook Stream Key (chat mein kabhi mat bhejna)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _running ? null : _saveCurrentPage,
                    child: const Text('Save Page'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_running || _selectedPageName == null)
                        ? null
                        : _deleteSelectedPage,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Delete Page'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ---- 2) VIDEO SOURCE: FILE / LINK ----
            const Text('2) Video Source — File ya Link',
                style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(
              value: _source,
              decoration: const InputDecoration(
                labelText: 'Source chunein',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'file', child: Text('Video File (Gallery)')),
                DropdownMenuItem(value: 'link', child: Text('Video Link paste karein')),
              ],
              onChanged: (v) => setState(() => _source = v ?? 'file'),
            ),
            const SizedBox(height: 8),
            if (_source == 'file')
              ElevatedButton(
                onPressed: _running ? null : _pickVideo,
                child: const Text('Video Chunein (Gallery)'),
              )
            else ...[
              DropdownButtonFormField<String>(
                value: _linkType,
                decoration: const InputDecoration(
                  labelText: 'Link kis cheez ki hai?',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'youtube', child: Text('YouTube Link')),
                  DropdownMenuItem(value: 'facebook', child: Text('Facebook Video Link (public)')),
                  DropdownMenuItem(value: 'direct', child: Text('Direct Video Link (.mp4 / .m3u8)')),
                ],
                onChanged: (v) => setState(() => _linkType = v ?? 'youtube'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _linkController,
                decoration: const InputDecoration(
                  labelText: 'Yahan link paste karein',
                  border: OutlineInputBorder(),
                ),
              ),
              const Text(
                'YouTube: link se direct stream nikaala jayega. Facebook: sirf public video ka direct link mil sakta hai, '
                'na mile to video download kar ke File mode use karein.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (_videoPath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_videoPath, style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 16),
            // ---- 3) LOGO WATERMARK UPLOAD ----
            const Text('3) Logo Watermark Upload (top-right)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ElevatedButton(
              onPressed: _running ? null : _pickLogo,
              child: const Text('Apna Logo Chunein (PNG)'),
            ),
            if (_customLogoPath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Logo: $_customLogoPath',
                    style: const TextStyle(fontSize: 12)),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Koi logo nahi chuna — default AlifYa icon top-right par lagega.',
                    style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _position,
              decoration: const InputDecoration(
                labelText: 'Watermark position (image = top-right rule)',
                border: OutlineInputBorder(),
              ),
              items: _positions.keys
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) => setState(() => _position = v ?? 'top-right'),
            ),
            const SizedBox(height: 16),
            // ---- 4) COPYRIGHT TEXT ----
            const Text('4) Copyright Text (footer, sliding left to right)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _copyrightController,
              decoration: const InputDecoration(
                labelText: 'Copyright text yahan paste / likhein (masalan: © Naseem Digital)',
                border: OutlineInputBorder(),
              ),
            ),
            const Text(
              'Ye text video ke neeche (footer) mein left se right slide hoga. Khaali chhoda to koi text nahi lagega.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Loop on rakhein'),
              value: _loop,
              onChanged: (v) => setState(() => _loop = v),
            ),
            SwitchListTile(
              title: const Text('Test Mode (Facebook par NAHI jayega, 10 sec local file)'),
              value: _testMode,
              onChanged: (v) => setState(() => _testMode = v),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _running ? null : _start,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('▶ Start / Go Live'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _running ? _stop : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('■ Stop'),
            ),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_log, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            const Text(
              'Real live steps: 1) Page select karein ya Save karein. 2) Test Mode OFF karein. '
              '3) Start dabayein, Facebook Live Producer mein PREVIEW aane par wahan Go Live dabayein. '
              '4) Khatam par Facebook mein End Live Video, phir yahan Stop.\n\n'
              'Sirf apni ya ijazat wali video use karein. Doosre ki video se copyright strike ya Page restriction lag sakta hai.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
