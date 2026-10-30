import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// FB Live Tool — V1 (Android APK, Flutter)
// Facebook Live ONLY. Source in V1: a video file picked on the phone.
// Watermark: assets/watermark.png (AlifYa icon, PNG image) overlaid top-right by default
// (user rule 2026-10-30: image watermark = top-right; text watermark, if added, = footer sliding left to right).
// Test Mode: writes a 10-second local MP4 instead of streaming to Facebook,
// so you can check the watermark without a Stream Key.
//
// IMPORTANT, read before a real live:
// - The Stream Key is entered in the app ONLY. Never post it in chat.
// - Only stream your own videos or videos you have permission to use.
// - Keep this app in the foreground / split-screen while you switch to
//   Facebook to press Go Live. Android may kill a background stream;
//   a foreground-service version is planned for V2 if this is a problem
//   on your phone.
// - Facebook links / YouTube links are NOT in V1. Android has no yt-dlp,
//   so link resolving needs a separate extractor (planned for V2).

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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _rtmpController =
      TextEditingController(text: 'rtmps://live-api-s.facebook.com:443/rtmp/');
  final _keyController = TextEditingController();
  String _videoPath = '';
  String _status = 'Ready. Pehle Test Mode se check karein.';
  String _log = '';
  String _testOutputPath = '';
  String _position = 'top-right';
  bool _loop = true;
  bool _testMode = true;
  bool _running = false;

  static const _positions = {
    'bottom-right': 'W-w-20:H-h-20',
    'bottom-left': '20:H-h-20',
    'top-right': 'W-w-20:20',
    'top-left': '20:20',
  };

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

  Future<String> _watermarkPath() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/watermark.png');
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/watermark.png');
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }

  Future<void> _start() async {
    if (_videoPath.isEmpty) {
      setState(() => _status = 'Pehle video chunein.');
      return;
    }
    if (!_testMode && _keyController.text.trim().isEmpty) {
      setState(() => _status = 'Facebook Stream Key dein, ya Test Mode on karein.');
      return;
    }

    final wmPath = await _watermarkPath();
    final pos = _positions[_position]!;
    final filter =
        '[0:v]scale=1280:720:force_original_aspect_ratio=decrease,'
        'pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v0];'
        '[1:v]scale=230:-1[wm];'
        '[v0][wm]overlay=$pos[vtmp];[vtmp]format=yuv420p[vout]';

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
        '${loopPart}-re -i "$_videoPath" -i "$wmPath" '
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
        // Keep only the latest log line to avoid rebuilding on every line.
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
    await FFmpegKitExtended.cancelAllSessions();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FB Live Tool')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Facebook Live ONLY — video file + watermark',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _running ? null : _pickVideo,
              child: const Text('Video Chunein (Gallery)'),
            ),
            if (_videoPath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_videoPath, style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _rtmpController,
              decoration: const InputDecoration(
                labelText: 'Facebook RTMP URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Facebook Stream Key (chat mein kabhi mat bhejna)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _position,
              decoration: const InputDecoration(
                labelText: 'Watermark position',
                border: OutlineInputBorder(),
              ),
              items: _positions.keys
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) => setState(() => _position = v ?? 'top-right'),
            ),
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
              'Real live steps: 1) Test Mode OFF karein. 2) facebook.com/live/producer mein Page chunein, Stream Key copy karke yahan daalein. '
              '3) Start dabayein, Facebook mein PREVIEW aane par wahan Go Live dabayein. '
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
