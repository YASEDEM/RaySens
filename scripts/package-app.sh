#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$ROOT/.build/swiftpm"
APP="$ROOT/.build/RaySens.app"
KEXT_BINARY="$ROOT/Resources/DisableTurboBoost.64bits.kext/Contents/MacOS/DisableTurboBoost"
EXPECTED_KEXT_SHA256="f81f003ccd5827122a41c39bddb78e4ffff37d84718a647dbd5fc3c6a92f987c"

ACTUAL_KEXT_SHA256="$(shasum -a 256 "$KEXT_BINARY" | awk '{print $1}')"
if [[ "$ACTUAL_KEXT_SHA256" != "$EXPECTED_KEXT_SHA256" ]]; then
  echo "Bundled Turbo Boost kext hash mismatch" >&2
  exit 1
fi

SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache" \
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" \
swift build -c release --scratch-path "$SCRATCH" --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$SCRATCH/x86_64-apple-macosx/release/RaySens" "$APP/Contents/MacOS/RaySens"
clang -O2 -arch x86_64 "$ROOT/Resources/smc-temperature.c" -framework IOKit -o "$APP/Contents/Resources/smc-temperature"
ditto "$ROOT/Resources/DisableTurboBoost.64bits.kext" "$APP/Contents/Resources/DisableTurboBoost.64bits.kext"
rm -f "$APP/Contents/Resources/DisableTurboBoost.64bits.kext/Contents/Info.plist~"
cp "$ROOT/Resources/ThirdParty-GPLv2.txt" "$APP/Contents/Resources/ThirdParty-GPLv2.txt"
ditto "$ROOT/Resources/ThirdPartySources/DisableTurboBoost.kext" "$APP/Contents/Resources/ThirdPartySources/DisableTurboBoost.kext"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/Resources/powermetrics-loop.sh" "$APP/Contents/Resources/powermetrics-loop.sh"
cp "$ROOT/Resources/dev.raysens.powermetrics.plist" "$APP/Contents/Resources/dev.raysens.powermetrics.plist"
cp "$ROOT/Resources/disable-turbo-on-start.sh" "$APP/Contents/Resources/disable-turbo-on-start.sh"
cp "$ROOT/Resources/dev.raysens.turbo-startup.plist" "$APP/Contents/Resources/dev.raysens.turbo-startup.plist"
chmod 755 "$APP/Contents/Resources/powermetrics-loop.sh"
chmod 755 "$APP/Contents/Resources/smc-temperature"
chmod 755 "$APP/Contents/Resources/disable-turbo-on-start.sh"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>RaySens</string>
  <key>CFBundleIdentifier</key><string>dev.raysens.app</string>
  <key>CFBundleName</key><string>RaySens</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST
chmod +x "$APP/Contents/MacOS/RaySens"
codesign --force --sign - "$APP"
echo "Created $APP"
