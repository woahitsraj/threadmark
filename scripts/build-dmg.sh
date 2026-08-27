#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-release}"
app_path="$project_root/dist/Threadmark.app"
staging_path="$(mktemp -d)"
trap 'rm -rf "$staging_path"' EXIT

"$project_root/scripts/build-app.sh" "$configuration" >/dev/null

version="$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")"
architectures="$(lipo -archs "$app_path/Contents/MacOS/Threadmark")"
architecture="${architectures// /-}"
dmg_path="$project_root/dist/Threadmark-$version-macOS-$architecture.dmg"

ditto "$app_path" "$staging_path/Threadmark.app"
ln -s /Applications "$staging_path/Applications"
rm -f "$dmg_path"
hdiutil create \
    -quiet \
    -volname "Threadmark" \
    -srcfolder "$staging_path" \
    -format UDZO \
    "$dmg_path"

echo "$dmg_path"
