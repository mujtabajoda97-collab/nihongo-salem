#!/bin/sh
# Run ONCE after `flutter create . --platforms=android,ios`.
# Adds the microphone/internet permissions the live call needs, raises the
# Android minSdk to 24 (the `record` plugin needs 23+) and sets the app name.
set -e

MANIFEST="android/app/src/main/AndroidManifest.xml"
PLIST="ios/Runner/Info.plist"

if [ -f "$MANIFEST" ]; then
  for perm in RECORD_AUDIO INTERNET; do
    if ! grep -q "android.permission.$perm" "$MANIFEST"; then
      sed -i.bak "s#<manifest\([^>]*\)>#<manifest\1>\n    <uses-permission android:name=\"android.permission.$perm\"/>#" "$MANIFEST"
      echo "Android: added $perm"
    fi
  done
  sed -i.bak 's#android:label="[^"]*"#android:label="نيهونغو مع سالم"#' "$MANIFEST"
  # Test builds may talk to a plain-http server on the home network (Android blocks that by default).
  if ! grep -q usesCleartextTraffic "$MANIFEST"; then
    sed -i.bak 's#<application#<application android:usesCleartextTraffic="true"#' "$MANIFEST"
  fi
  rm -f "$MANIFEST.bak"
else
  echo "Missing $MANIFEST - run 'flutter create . --platforms=android,ios' first." >&2
fi

for gradle in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$gradle" ]; then
    sed -i.bak -E 's/minSdk(Version)?( =|) +flutter\.minSdkVersion/minSdk\1\2 24/' "$gradle"
    rm -f "$gradle.bak"
    grep -n "minSdk" "$gradle" || true
  fi
done

if [ -f "$PLIST" ]; then
  if ! grep -q "NSMicrophoneUsageDescription" "$PLIST"; then
    sed -i.bak "s#<dict>#<dict>\n\t<key>NSMicrophoneUsageDescription</key>\n\t<string>نحتاج الميكروفون لتتحدث مع المعلم بالصوت.</string>#" "$PLIST"
    rm -f "$PLIST.bak"
    echo "iOS: added NSMicrophoneUsageDescription"
  fi
fi
echo "Done."
