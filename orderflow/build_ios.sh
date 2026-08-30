#!/bin/bash
set -e

echo "============================================="
echo "Building iOS Release (IPA / Archive)"
echo "============================================="

cd "$(dirname "$0")"

# 1. Ensure dependencies are fetched
flutter pub get

# 2. Build iOS Release IPA (or Runner.app)
flutter build ipa --release

echo "============================================="
echo "SUCCESS! iOS IPA built successfully at:"
echo "orderflow/build/ios/ipa/*.ipa"
echo "============================================="
