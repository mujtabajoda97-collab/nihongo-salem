#!/bin/sh
# Builds an installable test APK on YOUR computer (needs Flutter + Android SDK: run `flutter doctor`).
#   sh tool/build_apk.sh https://your-server.example.com [APP_API_KEY]
set -e
API="${1:-}"
KEY="${2:-}"
[ -d android ] || flutter create . --platforms=android --project-name nihongo_salem --org com.nihongo.salem
sh tool/setup_platforms.sh
rm -f test/widget_test.dart   # the sample test that `flutter create` adds
flutter pub get
flutter test
flutter build apk --release --dart-define=MOCK_PURCHASES=true --dart-define=API_BASE_URL="$API" --dart-define=APP_API_KEY="$KEY"
echo
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
