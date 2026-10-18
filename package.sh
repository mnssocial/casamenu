#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# A portable build never uses personal state from Application Support.
[[ -x HomeKit/runtime/bin/node ]] || { echo 'Provide the official Node 24 macOS arm64 runtime in HomeKit/runtime.'; exit 1; }
export PATH="$PWD/HomeKit/runtime/bin:$PATH"
[[ $(node -p 'process.versions.node.split(".")[0]') == 24 ]]
[[ -d HomeKit/node_modules/homebridge ]] || (cd HomeKit && npm ci --no-audit --no-fund)
./test.sh
./build.sh
bundle='CasaMenu.app/Contents/Resources/HomeKit'
mkdir -p "$bundle"
for item in package.json package-lock.json setup.mjs casamenu-tuya.cjs tuya-command.cjs homebridge-casamenu-ir node_modules; do
  ditto "HomeKit/$item" "$bundle/$item"
done
mkdir -p "$bundle/runtime/bin"
cp HomeKit/runtime/bin/node "$bundle/runtime/bin/node"
cp HomeKit/runtime/LICENSE "$bundle/runtime/LICENSE"
# npm's local plugin link must stay inside the portable app.
rm -f "$bundle/node_modules/homebridge-casamenu-ir" 2>/dev/null || true
[[ -e "$bundle/node_modules/homebridge-casamenu-ir" ]] || ln -s ../homebridge-casamenu-ir "$bundle/node_modules/homebridge-casamenu-ir"
# Sign executable dependencies before the outer bundle.
find "$bundle" -type f \( -name '*.node' -o -name node -o -name ffmpeg -o -name ffprobe \) -exec codesign --force --sign - {} \;
codesign --force --deep --sign - CasaMenu.app
codesign --verify --deep --strict CasaMenu.app
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent CasaMenu.app dist/CasaMenu-0.7.0-macOS-arm64.zip
shasum -a 256 dist/CasaMenu-0.7.0-macOS-arm64.zip > dist/SHA256.txt
