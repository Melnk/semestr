#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# A regular macOS app: bundled web UI + AppKit/WebKit + system SQLite.
# Node/pnpm and Xcode are needed only to build, never to run the app.
for tool in node pnpm xcrun; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Нужен $tool — см. README, раздел сборки."; exit 1; }
done
pnpm --filter @semestr/web build:desktop
mkdir -p dist .local/swift-module-cache
stage="$(mktemp -d "$PWD/.local/macos-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Семестр.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/web"
cp -R apps/web/dist/. "$app/Contents/Resources/web/"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
node scripts/generate-notices.mjs "$app/Contents/Resources/THIRD_PARTY_NOTICES.txt"
read -r -a build_archs <<< "${SEMESTR_ARCHS:-$(uname -m)}"
for build_arch in "${build_archs[@]}"; do
  case "$build_arch" in arm64|x86_64) ;; *) echo "Неизвестная архитектура: $build_arch"; exit 1;; esac
  xcrun swiftc -swift-version 5 -O -target "$build_arch-apple-macosx13.0" \
    -module-cache-path "$PWD/.local/swift-module-cache" \
    -framework AppKit -framework UserNotifications -framework WebKit -framework UniformTypeIdentifiers -lsqlite3 \
    apps/macos/Store.swift apps/macos/Rules.swift apps/macos/CalendarRules.swift \
    apps/macos/Reminders.swift apps/macos/NotificationService.swift apps/macos/ReminderTests.swift \
    apps/macos/Tests.swift apps/macos/main.swift -o "$stage/Semestr-$build_arch"
done
xcrun lipo -create "$stage"/Semestr-* -output "$app/Contents/MacOS/Semestr"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>CFBundleExecutable</key><string>Semestr</string>
  <key>CFBundleIdentifier</key><string>dev.semestr.local</string>
  <key>CFBundleName</key><string>Семестр</string>
  <key>CFBundleDisplayName</key><string>Семестр</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.1</string>
  <key>CFBundleVersion</key><string>7</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Семестр · MIT License</string>
</dict></plist>
PLIST
"$app/Contents/MacOS/Semestr" --self-test
"$app/Contents/MacOS/Semestr" --notification-self-test
"$app/Contents/MacOS/Semestr" --make-icon "$stage/icon.png"
mkdir "$stage/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$stage/icon.png" --out "$stage/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$stage/icon.png" --out "$stage/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$stage/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
# Replace only this build artifact; study data is outside the app bundle.
if [ -d "dist/Семестр.app" ]; then mv "dist/Семестр.app" "$stage/previous.app"; fi
mv "$app" "dist/Семестр.app"
printf 'Готово: %s/dist/Семестр.app\n' "$PWD"
