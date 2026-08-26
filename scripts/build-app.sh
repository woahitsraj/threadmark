#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-release}"
app_path="$project_root/dist/T3 Menubar.app"
icon_temp="$(mktemp -d)"
iconset_path="$icon_temp/AppIcon.iconset"
trap 'rm -rf "$icon_temp"' EXIT

cd "$project_root"
swift build -c "$configuration" --product T3MenuBar
binary_path="$(swift build -c "$configuration" --show-bin-path)/T3MenuBar"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/T3MenuBar"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
mkdir -p "$iconset_path"
sips -z 16 16 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_16x16.png" >/dev/null
sips -z 32 32 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_32x32.png" >/dev/null
sips -z 64 64 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_128x128.png" >/dev/null
sips -z 256 256 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_256x256.png" >/dev/null
sips -z 512 512 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$project_root/Resources/AppIcon.png" --out "$iconset_path/icon_512x512.png" >/dev/null
cp "$project_root/Resources/AppIcon.png" "$iconset_path/icon_512x512@2x.png"
iconutil -c icns "$iconset_path" -o "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"

echo "$app_path"
