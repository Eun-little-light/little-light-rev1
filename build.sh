#!/bin/zsh
# 작은 빛.Rev.1.app 빌드 (Xcode 없이 Command Line Tools만으로)
set -euo pipefail
# CLT의 최신 SDK가 swiftc보다 새로우면 빌드가 깨지므로, 컴파일러와 맞는 SDK를 고른다
for cand in MacOSX26.5.sdk MacOSX26.sdk MacOSX15.4.sdk; do
  if [ -d "/Library/Developer/CommandLineTools/SDKs/$cand" ]; then export SDKROOT="/Library/Developer/CommandLineTools/SDKs/$cand"; break; fi
done
[ -n "${GHOST_SDKROOT:-}" ] && export SDKROOT="$GHOST_SDKROOT"
echo "› SDK: ${SDKROOT:-default}"
cd "$(dirname "$0")"

APP="dist/작은 빛.Rev.1.app"
rm -rf "$APP" .build-tmp
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web" .build-tmp

echo "› compile"
swiftc -O -target arm64-apple-macos13.0 mac/main.swift -o "$APP/Contents/MacOS/GhostCore" \
  -framework Cocoa -framework WebKit

echo "› web resources"
cp index.html lore.js "$APP/Contents/Resources/web/"

echo "› icon"
swift mac/make_icon.swift .build-tmp/icon.png
ICONSET=.build-tmp/AppIcon.iconset; mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s .build-tmp/icon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) .build-tmp/icon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>CFBundleName</key><string>작은 빛.Rev.1</string>
  <key>CFBundleDisplayName</key><string>작은 빛.Rev.1</string>
  <key>CFBundleIdentifier</key><string>com.local.ghostcore.rev1</string>
  <key>CFBundleExecutable</key><string>GhostCore</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>3.5</string>
  <key>CFBundleVersion</key><string>7</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>고스트가 볼륨, 다크 모드, 메모, 미리 알림을 제어하려면 권한이 필요해요.</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

echo "› sign (ad-hoc)"
# iCloud 동기화 폴더(바탕화면·문서)나 Finder가 붙인 확장 속성이 있으면 서명이 거부되므로 먼저 제거
xattr -cr "$APP"
codesign --force --deep -s - "$APP"
rm -rf .build-tmp
echo "✓ built: $APP"
