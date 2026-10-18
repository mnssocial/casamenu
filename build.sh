#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# Quit CasaMenu before rebuilding the ad-hoc signed executable.
mkdir -p CasaMenu.app/Contents/{MacOS,Resources}
cp Resources/Info.plist CasaMenu.app/Contents/Info.plist
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 Sources/*.swift -o CasaMenu.app/Contents/MacOS/CasaMenu
cp Assets/CasaMenu.icns CasaMenu.app/Contents/Resources/CasaMenu.icns
codesign --force --sign - CasaMenu.app
