# NzTools backend — deploy via Render

This repository includes a Docker backend with yt-dlp and ffmpeg. Render will assign a public `onrender.com` URL after deployment; this file does not create the URL by itself.

## From an Android phone
1. Extract this ZIP on your phone.
2. Create a new repository on GitHub.
3. Upload the **extracted project files and folders** to the repository (do not upload only the ZIP file).
4. Open https://render.com and sign in with GitHub.
5. In Render, choose **New + → Blueprint** and select the GitHub repository containing `render.yaml`.
6. Review and deploy the `nztools-api` service. The first Docker build may take several minutes.
7. When Render shows the service URL, open `https://YOUR-SERVICE.onrender.com/health`. A healthy response should contain `"status":true` and service `NzTools API`.
8. Use the real service URL in the Flutter build command:

```sh
flutter build apk --release --target-platform=android-arm64 --dart-define=NZTOOLS_API_URL=https://YOUR-SERVICE.onrender.com
```

Replace `https://YOUR-SERVICE.onrender.com` with the actual URL assigned by Render. Do not include `/health` at the end of the value.

## Important
- This package prepares deployment configuration; it does not create a live domain or deploy without your GitHub/Render account action.
- Render free services can sleep after inactivity and may have build/runtime limits.
- Instagram download success depends on yt-dlp, the post being public/accessibly available, and changes made by Instagram. This is not guaranteed for private or login-gated content.
- Only download content you own or have permission to save.
