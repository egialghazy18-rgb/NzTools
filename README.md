# NzTools 2.4.1 — yt-dlp Instagram Backend

NzTools is a Flutter media utility. The Android app handles preview/download UI while the optional Node backend resolves supported social links.

## Resolver engine

Instagram now uses the backend `yt-dlp` resolver first, with Scrapr as fallback. The app surfaces backend errors rather than silently switching to a less reliable in-app Instagram scraper. TikTok and other platforms use the universal Scrapr resolver and existing fallback.

Supported through the universal engine include TikTok, Instagram, YouTube, Facebook, X/Twitter, Pinterest, Reddit, Threads, SoundCloud, Spotify, Bilibili/Douyin and other platforms exposed by the installed Scrapr version.

## Backend

```bash
cd backend
npm install
npm start
```

The Dockerfile installs Python, yt-dlp and ffmpeg. Deploy this backend publicly over HTTPS, then build the APK with that exact backend URL. The APK cannot connect to a backend until its URL is configured.

The main endpoint is:

`GET /api/resolve?url=<media-url>`

or POST JSON:

`POST /api/resolve` with `{ "url": "https://..." }`

Health check:

`GET /health`

## Android build — keep the APK small

This project is configured for a single `arm64-v8a` release APK, which avoids bundling the other CPU architectures into the same APK. Flutter documents that a fat APK containing multiple ABIs is larger; split/ABI-specific builds reduce download size. citeturn0search0turn0search1

For a normal release build:

```bash
flutter pub get
flutter build apk --release --dart-define=NZTOOLS_API_URL=https://YOUR-BACKEND-DOMAIN
```

If your build service accepts build arguments, this is also useful:

```bash
flutter build apk --release --target-platform=android-arm64 --obfuscate --split-debug-info=build/symbols --dart-define=NZTOOLS_API_URL=https://YOUR-BACKEND-DOMAIN
```

Release builds are much smaller than debug builds, and Flutter recommends measuring/reducing size with release builds and size analysis. citeturn0search1turn0search3

**Target:** the project is tuned to aim for a sub-50 MB arm64 APK. Exact size still depends on Flutter SDK, native plugins and assets, so it cannot be honestly guaranteed without the same build environment used to generate the final APK.

## Notes

- The APK does not run Node/yt-dlp itself. The resolver backend must be deployed and its URL supplied through `NZTOOLS_API_URL`.
- Download media only when you have the right to save it and follow the source platform's terms.
