/// App-wide configuration values.
///
/// Google Play requires the privacy policy to be reachable from inside the app
/// as well as from the store listing. Paste the public URL below before
/// uploading. While this is empty, the "Privacy Policy" row stays hidden so the
/// app never ships a broken link.
const String privacyPolicyUrl = 'https://doc-hosting.flycricket.io/zen-alpha-launcher/f24a5e44-762e-497f-a267-d5cf09c18b58/privacy';

/// The application ID shared by the Android and iOS builds.
///
/// Keep this in sync with `android/app/build.gradle.kts` and the native
/// `MainActivity` package. It is used for user-facing troubleshooting text.
const String appPackageName = 'com.trend74x.zenalpha';
