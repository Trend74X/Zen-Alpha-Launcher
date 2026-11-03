# Zen Alpha Launcher

A minimalist Android launcher built to reduce screen time and notification noise.

- Distraction-resistant home screen with a deliberate "interrupter" before launching apps
- Notification Vault that collects notifications locally (never uploaded)
- Do Not Disturb control
- Hidden applications (biometric gate)
- Double-tap-to-lock via Android Device Admin
- App limits (in progress)

## Build

```bash
flutter pub get
flutter build appbundle --release
```

## Play Store notes

- Application ID: `com.trend74x.zenalpha`
- Target SDK: 36
- No accessibility service, no `QUERY_ALL_PACKAGES`, no battery-optimization exemption permission
- A privacy policy and Data Safety form are required before publishing because the app reads notification content locally
