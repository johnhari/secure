#!/bin/bash
set -e

echo "============================================="
echo "Building macOS Release App & DMG Installer"
echo "============================================="

flutter build macos --release

mkdir -p build/macos/dmg
hdiutil create -volname "ADVANCE ORDERFLOW ANALYZER" \
  -srcfolder "build/macos/Build/Products/Release/orderflow.app" \
  -ov -format UDZO "build/macos/dmg/Orderflow-Installer.dmg"

echo "============================================="
echo "SUCCESS! DMG created at:"
echo "orderflow/build/macos/dmg/Orderflow-Installer.dmg"
echo "============================================="
