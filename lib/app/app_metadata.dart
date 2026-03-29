// Keep this fallback in sync with pubspec.yaml; app_metadata_test.dart enforces it.
const kickDefaultAppVersion = '1.2.0';
const kickBuildAppVersion = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: kickDefaultAppVersion,
);
const kickAppIconAssetPath = 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png';
const kickWindowsTrayIconAssetPath = 'windows/runner/resources/app_icon.ico';
const kickRepositoryUrl = 'https://github.com/mxnix/kick';
const kickLatestReleaseUrl = '$kickRepositoryUrl/releases/latest';
const kickLatestReleaseApiUrl = 'https://api.github.com/repos/mxnix/kick/releases/latest';
