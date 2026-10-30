# FB Live Tool — APK Setup (Phone Only, No PC)

**Scope V1:** Facebook Live ONLY. Source: video file picked on the phone.
Watermark: AlifYa icon, bottom-right by default.
YouTube/Facebook LINK source is NOT in V1 (Android has no yt-dlp) — planned for V2.

## Aapko kya chahiye (sirf phone se)
- GitHub account (free) + GitHub app ya Chrome browser on phone
- Facebook Page + Live Producer se Stream Key (app mein hi daalna hai)
- Internet ON rakhna hai stream ke doran
- Play Store ki zaroorat NAHI hai (sirf khud use karne ke liye)

## Step 1 — GitHub repo banayein (phone se)
1. GitHub app ya github.com kholein, sign in karein.
2. New repository banayein, naam: `fb-live-tool`, Public ya Private (dono chalenge).
3. Is ZIP ki files repo mein upload karein, folder structure EXACT ye honi chahiye:
   - `lib/main.dart`
   - `pubspec.yaml`
   - `assets/watermark.png`
   - `tools/patch_manifest.py`
   - `.github/workflows/build-apk.yml`
   - `README-phone-steps.md` (ye file, optional)
   - Upload karne ke liye GitHub web mein "Add file > Upload files" use karein.
     `.github` folder chhup sakta hai — agar web upload mein dot-folder mushkil ho,
     to workflow file ko baad mein GitHub web editor se banayein:
     repo mein "Add file > Create new file", naam likhein
     `.github/workflows/build-apk.yml`, aur is ZIP ki workflow file ka
     poora text paste karke Commit karein.

## Step 2 — Build chalayein
1. Repo mein **Actions** tab kholein.
2. Workflow **Build FB Live APK** chunein, **Run workflow** dabayein.
3. Wait karein — andazan 10-20 minute (har build ka time alag ho sakta hai).
4. Agar build FAIL ho, to Actions ke log mein aakhri error ki line dekhein
   aur mujhe wo line bhejein — main fix karke nayi file dunga.
   Aam fail reasons: Flutter version, ya ffmpeg_kit bundle download ka network issue
   (dobara Run karne se aksar theek ho jata hai).

## Step 3 — APK download + install (phone par)
1. Build complete hone par, us run ke neeche **Artifacts** mein
   `fb-live-tool-apk` milega — download karein.
2. Download ki hui APK kholein. Phone poochhega "Install unknown apps" —
   Chrome ya Files app ke liye Allow karein, phir Install dabayein.
3. App ka naam **FB Live Tool** hoga.

## Step 4 — Pehle TEST karein (Facebook key ke baghair)
1. App kholein, **Video Chunein** se apni gallery se koi video chunein.
2. **Test Mode ON** rakhein (default ON hai), **Start** dabayein.
3. 10 second baad app batayega: Test complete, file ka path.
   Wo file aapke phone ke app documents folder mein hogi.
   Agar test mein watermark nazar nahi aata ya error aata hai,
   to real live mat karein — pehle mujhe error batayein.

## Step 5 — Real Facebook Live
1. Test Mode **OFF** karein.
2. Chrome mein `facebook.com/live/producer` kholein, apna Page chunein,
   Stream Key copy karein. (Persistent Stream Key ho to wahi use karein.)
3. Stream Key **sirf app mein** paste karein — chat mein kabhi mat bhejna.
4. App mein **Start** dabayein. Facebook Live Producer mein PREVIEW nazar aayega.
5. Facebook mein **Go Live** dabayein.
   **Zaroori:** App ko foreground / split-screen mein rakhein jab aap
   Facebook par switch karein. Android background mein stream ko rok sakta hai.
   Agar aapke phone par switch karte hi stream ruk jaye, to ye V1 ki limit hai —
   V2 mein foreground service add karenge.
6. Khatam par: pehle Facebook mein **End Live Video**, phir app mein **Stop**.

## Warnings (zaroori)
- Sirf apni ya ijazat wali video use karein. Doosre ki video se
  copyright strike ya Page restriction lag sakta hai.
- Stream Key password jaisa hai. Agar leak ho jaye to Facebook Live Producer
  mein usko reset karein.
- Ye debug APK hai (personal use ke liye). Play Store par publish karne ke
  liye signing + $25 one-time + GPL license ka khayal rakhna hoga,
  kyunke libx264 GPL bundle use ho raha hai.
- Ye setup yahan (is chat ke computer par) APK build karke test NAHI hua,
  kyunke yahan Flutter/Android SDK nahi hai. Pehla asli test GitHub Actions
  ka build + aapke phone par install hoga. Is liye pehle Test Mode zaroor chalana.

## Files
- `lib/main.dart` — poori app (ek screen)
- `pubspec.yaml` — Flutter + ffmpeg_kit_extended (full + GPL, libx264 ke liye)
- `assets/watermark.png` — AlifYa icon, aapke logo kit se unchanged, sirf resize
- `tools/patch_manifest.py` — Android permissions + minSdk 26 lagata hai
- `.github/workflows/build-apk.yml` — cloud build (Java 17 + Flutter 3.47.0)
