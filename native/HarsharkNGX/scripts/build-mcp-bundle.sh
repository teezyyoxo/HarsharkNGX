#!/bin/zsh
set -euo pipefail
project_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$project_root"
destination="${1:?Usage: build-mcp-bundle.sh DESTINATION.app}"
configuration="${MCP_BUILD_CONFIGURATION:-release}"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
# Xcode supplies build variables that should not affect the independent Swift package.
unset SDKROOT
mkdir -p "$destination/Contents/MacOS"
architectures="${ARCHS:-$(uname -m)}"
binaries=()
for architecture in ${=architectures}; do
    scratch_path="$project_root/.build/mcp-$architecture"
    swift build --disable-sandbox --scratch-path "$scratch_path" -c "$configuration" --arch "$architecture" --product harsharkngx-mcp
    build_path="$(swift build --disable-sandbox --scratch-path "$scratch_path" -c "$configuration" --arch "$architecture" --show-bin-path)"
    binaries+=("$build_path/harsharkngx-mcp")
done
lipo -create "${binaries[@]}" -output "$destination/Contents/MacOS/harsharkngx-mcp"
chmod 755 "$destination/Contents/MacOS/harsharkngx-mcp"
cat > "$destination/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>harsharkngx-mcp</string>
  <key>CFBundleIdentifier</key><string>com.teezyyoxo.HarsharkNGX.MCP</string>
  <key>CFBundleName</key><string>harsharkngx-mcp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.3</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[[ -n "$identity" ]] || identity="-"
codesign --force --sign "$identity" --options runtime "$destination"
