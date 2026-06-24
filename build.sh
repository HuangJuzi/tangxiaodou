#!/bin/bash
set -euo pipefail

# Build release APK and rename to tangxiaodou-<version>.apk

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d+ -f1)
OUTPUT="build/app/outputs/flutter-apk/tangxiaodou-${VERSION}.apk"

echo "==> Building tangxiaodou v${VERSION} ..."
flutter build apk --release --target-platform android-arm64

cp build/app/outputs/flutter-apk/app-release.apk "$OUTPUT"
echo "==> Done: ${OUTPUT}"
ls -lh "$OUTPUT"

# Install to device if connected
if adb devices | grep -q 'device$'; then
    echo "==> Installing to device ..."
    adb install -r "$OUTPUT"
fi
