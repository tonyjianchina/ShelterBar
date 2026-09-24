#!/bin/sh
# Build and verify the Apple Silicon preview artifacts on macOS.
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
plist="$project_dir/Resources/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
case "$version" in
    ''|*[!0-9.]*) echo "Expected a numeric version in Resources/Info.plist." >&2; exit 1 ;;
esac
release_dir="$project_dir/dist/releases/v$version"
asset_name="ShelterBar-$version-macos-arm64"

"$project_dir/scripts/build-app.sh" release
app_dir="$project_dir/dist/ShelterBar.app"
work_dir=$(mktemp -d "$project_dir/dist/.release.XXXXXX")
mount_dir="$work_dir/mounted"
mounted=no
cleanup() {
    if [ "$mounted" = yes ]; then
        if ! hdiutil detach "$mount_dir" -quiet; then
            echo "Could not unmount $mount_dir; leaving $work_dir for manual cleanup." >&2
            return
        fi
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$work_dir/image" "$work_dir/artifacts" "$mount_dir"
ditto "$app_dir" "$work_dir/image/ShelterBar.app"
ln -s /Applications "$work_dir/image/Applications"
cat > "$work_dir/image/INSTALL.txt" <<'INSTALL'
ShelterBar - 预览版 / Preview
Apple Silicon (M1 及更新芯片)，macOS 26.0 或更新版本。

安装：将 ShelterBar.app 拖入 Applications，然后推出磁盘映像。
打开“应用程序”中的 ShelterBar，按提示在“系统设置 → 隐私与安全性
→ 辅助功能”中授权。应用显示在菜单栏，不显示 Dock 图标。

本预览版使用临时签名（ad-hoc），没有 Developer ID 签名或 Apple 公证。
如果首次打开被阻止，请先核实下载来源及 SHA256 校验值，再到
“系统设置 → 隐私与安全性”点击“仍要打开”，随后确认“打开”。
如果系统未提供该选项，请勿绕过安全策略；受管理设备可能不允许例外。
Apple 官方说明：https://support.apple.com/zh-cn/102445

Install: drag ShelterBar.app to Applications, then eject this disk image.
Open ShelterBar from Applications and allow Accessibility when requested.
ShelterBar is a menu-bar app and does not show a Dock icon.

This preview is ad-hoc signed, without Developer ID signing or Apple notarization.
If macOS blocks the first launch, verify the download source and SHA256, then use
System Settings > Privacy & Security > Open Anyway and confirm Open.
Managed devices may not offer an exception. Do not disable Gatekeeper.
Apple guidance: https://support.apple.com/102445
INSTALL

ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$work_dir/artifacts/$asset_name.zip"
hdiutil create -volname "ShelterBar $version" -srcfolder "$work_dir/image" \
    -fs HFS+ -format UDZO "$work_dir/artifacts/$asset_name.dmg"

# Check the artifacts themselves, not just the source app.
hdiutil verify "$work_dir/artifacts/$asset_name.dmg"
hdiutil attach "$work_dir/artifacts/$asset_name.dmg" -readonly -nobrowse \
    -noautoopen -mountpoint "$mount_dir" -quiet
mounted=yes
test "$(readlink "$mount_dir/Applications")" = /Applications
test -f "$mount_dir/INSTALL.txt"
codesign --verify --strict --verbose=2 "$mount_dir/ShelterBar.app"
cmp "$app_dir/Contents/MacOS/ShelterBar" "$mount_dir/ShelterBar.app/Contents/MacOS/ShelterBar"
cmp "$app_dir/Contents/Info.plist" "$mount_dir/ShelterBar.app/Contents/Info.plist"
hdiutil detach "$mount_dir" -quiet
mounted=no

ditto -x -k "$work_dir/artifacts/$asset_name.zip" "$work_dir/unzipped"
codesign --verify --strict --verbose=2 "$work_dir/unzipped/ShelterBar.app"
cmp "$app_dir/Contents/MacOS/ShelterBar" "$work_dir/unzipped/ShelterBar.app/Contents/MacOS/ShelterBar"
cmp "$app_dir/Contents/Info.plist" "$work_dir/unzipped/ShelterBar.app/Contents/Info.plist"
(
    cd "$work_dir/artifacts"
    shasum -a 256 "$asset_name.dmg" "$asset_name.zip" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

mkdir -p "$release_dir"
mv "$work_dir/artifacts/$asset_name.dmg" "$release_dir/"
mv "$work_dir/artifacts/$asset_name.zip" "$release_dir/"
mv "$work_dir/artifacts/SHA256SUMS" "$release_dir/"
printf '\nVerified preview artifacts: %s\n' "$release_dir"
ls -lh "$release_dir/$asset_name.dmg" "$release_dir/$asset_name.zip" "$release_dir/SHA256SUMS"
