# Flutter Liveness SDK test app

This is the testing app bundled with the library. Run it on an Android or iOS device with a front camera. It does not modify KomerceOS.

The **Test Lab** page lets you select face actions, switch audit evidence on or off, set a timeout, start or cancel a native capture session, and inspect progress events, the final selfie, evidence images, and error codes. Images are stored in the app's temporary/cache directory.

```bash
cd example
flutter run -d <device-id>
```

See the repository [README](../README.md) for OS requirements and build instructions. The ML Kit pods used here do not support Apple Silicon arm64 iOS simulators; use a physical iPhone for iOS camera testing.
