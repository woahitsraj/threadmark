#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-release}"
app_path="$project_root/dist/Threadmark.app"
sparkle_framework="$project_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
icon_temp="$(mktemp -d)"
iconset_path="$icon_temp/AppIcon.iconset"
trap 'rm -rf "$icon_temp"' EXIT

cd "$project_root"
swift build -c "$configuration" --product Threadmark
binary_path="$(swift build -c "$configuration" --show-bin-path)/Threadmark"

test -d "$sparkle_framework"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
cp "$binary_path" "$app_path/Contents/MacOS/Threadmark"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
ditto "$sparkle_framework" "$app_path/Contents/Frameworks/Sparkle.framework"
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$app_path/Contents/Info.plist"
fi
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
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  embedded_sparkle="$app_path/Contents/Frameworks/Sparkle.framework"
  sparkle_version="$embedded_sparkle/Versions/B"
  sign_args=(--force --sign "$CODE_SIGN_IDENTITY" --options runtime --timestamp)
  codesign "${sign_args[@]}" "$sparkle_version/XPCServices/Installer.xpc"
  codesign "${sign_args[@]}" --preserve-metadata=entitlements \
    "$sparkle_version/XPCServices/Downloader.xpc"
  codesign "${sign_args[@]}" "$sparkle_version/Autoupdate"
  codesign "${sign_args[@]}" "$sparkle_version/Updater.app"
  codesign "${sign_args[@]}" "$embedded_sparkle"
  codesign "${sign_args[@]}" "$app_path"
else
  codesign \
    --force \
    --sign - \
    --requirements '=designated => identifier "com.rajan.threadmark"' \
    "$app_path"
fi

echo "$app_path"
