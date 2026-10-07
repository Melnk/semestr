#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SEMESTR_ARCHS="arm64 x86_64" bash scripts/build-macos.sh
release_dir="$PWD/dist/release"
mkdir -p "$release_dir"
stage="$(mktemp -d "$PWD/.local/macos-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

ditto "dist/Семестр.app" "$stage/Семестр.app"
cp docs/install-macos.txt "$stage/Прочитайте перед запуском.txt"
ln -s /Applications "$stage/Программы"
ditto -c -k --sequesterRsrc --keepParent "dist/Семестр.app" "$release_dir/Semestr-macOS-universal.zip"
hdiutil create -volname "Семестр" -srcfolder "$stage" -ov -format UDZO "$release_dir/Semestr-macOS-universal.dmg"
hdiutil verify "$release_dir/Semestr-macOS-universal.dmg"
(
  cd "$release_dir"
  shasum -a 256 Semestr-macOS-universal.dmg Semestr-macOS-universal.zip > SHA256SUMS.txt
)
printf 'Релиз готов: %s\n' "$release_dir"
