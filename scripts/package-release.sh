#!/bin/sh
# Build and verify the Apple Silicon release artifacts on macOS.
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
plist="$project_dir/Resources/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
case "$version" in
    ''|*[!0-9.]*) echo "Expected a numeric version in Resources/Info.plist." >&2; exit 1 ;;
esac
release_dir="$project_dir/dist/releases/v$version"
asset_name="ShelterBar-$version-macos-arm64"
dmg_python=${SHELTERBAR_DMG_PYTHON:-"$project_dir/.build/dmg-tools/bin/python"}
if ! "$dmg_python" -c 'import ds_store, mac_alias' 2>/dev/null; then
    echo "DMG tools missing. Create .build/dmg-tools with Python 3.10+ and install scripts/dmg-requirements.txt; see docs/RELEASE.md." >&2
    exit 1
fi

# Release credentials stay in the existing keychain profile. Never pass API
# credentials to this script or create replacement identities automatically.
release_identity=${SHELTERBAR_RELEASE_CODESIGN_IDENTITY:-"Developer ID Application: jian tony (5UKPG93ACW)"}
case "$release_identity" in
    "Developer ID Application:"*) ;;
    *) echo "A notarized release requires a Developer ID Application identity." >&2; exit 1 ;;
esac
if ! security find-identity -v -p codesigning | grep -Fq "\"$release_identity\""; then
    echo "Required Developer ID signing identity is unavailable; stopping." >&2
    exit 1
fi
if [ -e "$release_dir/$asset_name.dmg" ] || [ -e "$release_dir/$asset_name.zip" ]; then
    echo "Release artifacts already exist; refusing to overwrite them." >&2
    exit 1
fi
notary_dir="$release_dir/notarization"
mkdir -p "$notary_dir"
SHELTERBAR_CODESIGN_IDENTITY=$release_identity SHELTERBAR_CODESIGN_CERT_NAME=$release_identity \
    "$project_dir/scripts/build-app.sh" release
if [ "$release_identity" != - ] && [ -n "${SHELTERBAR_EXPECTED_DR:-}" ]; then
    actual_dr=$(codesign -d -r- "$project_dir/dist/ShelterBar.app" 2>&1 | sed -n 's/^designated => //p')
    if [ "$actual_dr" != "$SHELTERBAR_EXPECTED_DR" ]; then
        echo "Designated requirement changed!" >&2
        echo "  expected: $SHELTERBAR_EXPECTED_DR" >&2
        echo "  actual:   $actual_dr" >&2
        exit 1
    fi
fi
app_dir="$project_dir/dist/ShelterBar.app"
work_dir=$(mktemp -d "$project_dir/dist/.release.XXXXXX")
mount_dir="$work_dir/mounted"
readwrite_image="$work_dir/ShelterBar-rw.dmg"
layout_device=""
mounted=no
cleanup() {
    if [ -n "$layout_device" ]; then
        hdiutil detach "$layout_device" -force >/dev/null 2>&1 || true
    fi
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

# First obtain an app ticket. The temporary ZIP is only the notary input;
# create the distributable ZIP after stapling the app.
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$notary_dir/ShelterBar-app.zip"
python3 "$project_dir/scripts/notarize-artifact.py" \
    "$notary_dir/ShelterBar-app.zip" "$notary_dir/app"
xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"
spctl --assess -vv --type execute "$app_dir"

mkdir -p "$work_dir/image/.background" "$work_dir/artifacts" "$mount_dir"
ditto "$app_dir" "$work_dir/image/ShelterBar.app"
ln -s /Applications "$work_dir/image/Applications"
ditto "$app_dir/Contents/Resources/AppIcon.icns" "$work_dir/image/.VolumeIcon.icns"
swift "$project_dir/Tools/GenerateDMGBackground.swift" \
    "$work_dir/image/.background/ShelterBar.png"
cat > "$work_dir/image/.background/INSTALL.txt" <<INSTALL
ShelterBar v$version - 正式版 / Release
Apple Silicon (M1 及更新芯片)，macOS 14.0 或更新版本。

安装：将 ShelterBar.app 拖入 Applications，然后推出磁盘映像。
打开“应用程序”中的 ShelterBar，按提示在“系统设置 → 隐私与安全性”
中开启辅助功能和输入监控。辅助功能生效后，应用会立即询问“屏幕录制”；它仅用于
读取原始菜单栏状态图标，可以拒绝或稍后开启。未授权时使用占位图标，
收纳与恢复功能仍然可用。
应用内提供“允许读取图标”和“打开设置”，授权后可能需要退出并重新打开。
应用只显示在菜单栏，没有 Dock 图标和窗口；请留意右上角菜单栏的收纳箱图标。

图标读取：使用 ScreenCaptureKit，仅截取与进程 PID、状态窗口及辅助功能
（AX）范围严格匹配的单个状态图标。具有稳定应用与菜单项标识的小尺寸 PNG
会缓存到 ~/Library/Application Support/ShelterBar/IconCache/，并受容量上限约束；
不采集音频、不录制视频、不保存整屏截图，也不上传任何图像。单色及灰阶图标
随外观调整对比度，同时保留灰阶细节和彩色标记；彩色图标保留原色，浅色彩色
图标在浅色收纳栏上加衬底，均保持比例。只有当前可见且尚未缓存的稳定图标才会
读取；缓存命中后的周期扫描不会再截图或重新检查录屏权限。首次读取失败也会记入
本地负缓存，后台轮询和重启不会反复录屏；只有点击“刷新并恢复收纳”才会再尝试。
失败时保留上次成功图像，没有可用图像时显示占位图标，不会中断收纳。
原始图标捕获与第三方图标移动的完整兼容性，仍待授权后的真实会话验证。

本版本使用 Developer ID Application 签名，并经过 Apple 公证。
从 v0.5.14 或更早的自签名版本升级，请手动安装：旧版更新器不接受新证书。
更换签名证书后，需要重新授予辅助功能、输入监控及所需的屏幕录制权限。
请核实下载来源及 SHA256 校验值。

Install: drag ShelterBar.app to Applications, then eject this disk image.
Open ShelterBar from Applications and allow Accessibility and Input Monitoring.
Once Accessibility is granted, the app
immediately asks for optional Screen Recording to show original status icons;
placeholders are used without it.
Use “允许读取图标” (Allow icon access) or “打开设置” (Open Settings) in the app.
You may need to quit and reopen ShelterBar after granting permission.
ShelterBar runs only in the menu bar: no Dock icon and no window. Look for its
archive-box icon at the top right of the menu bar.

ScreenCaptureKit captures a single original status icon only after strictly
matching its process PID, status window, and accessibility (AX) bounds. Small
PNGs with a stable application and status-item identity are cached under
~/Library/Application Support/ShelterBar/IconCache/ with bounded storage.
No audio capture, video recording, full screenshots, or network uploads.
Monochrome and neutral shaded glyphs adapt their contrast to the shelf
appearance, preserving tonal detail and colored badges. Color-led status images
retain their colors (light ones get a contrast plate). Aspect ratios are preserved.
Only visible stable items missing a cached glyph are captured. Periodic scans
with a cache hit neither capture again nor recheck Screen Recording permission.
A failed refresh retains the last successful image. If no capture is available,
the shelf uses a placeholder without interrupting collection or restoration.
Full original-icon and native third-party movement compatibility still requires
validation in an authorized macOS session.

This release uses Developer ID Application signing and Apple notarization.
Install manually when upgrading from v0.5.14 or earlier: the old updater pins
its self-signed certificate and cannot accept this new signing identity.
After switching certificates, re-grant Accessibility, Input Monitoring and any
Screen Recording access you need. Verify the download source and SHA256.

INSTALL

ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$work_dir/artifacts/$asset_name.zip"
if [ -e "/Volumes/ShelterBar $version" ]; then
    echo "ShelterBar $version is already mounted; eject it before packaging." >&2
    exit 1
fi
hdiutil create -volname "ShelterBar $version" -srcfolder "$work_dir/image" \
    -fs HFS+ -format UDRW -ov "$readwrite_image" >/dev/null

attach_output=$(hdiutil attach -readwrite -noverify -noautoopen "$readwrite_image")
layout_device=$(printf '%s\n' "$attach_output" | awk -F '\t' \
    '$3 != "" { sub(/[[:space:]]+$/, "", $1); print $1; exit }')
layout_mount_dir=$(printf '%s\n' "$attach_output" | awk -F '\t' \
    '$3 != "" { print $3; exit }')
if [ -z "$layout_device" ] || [ -z "$layout_mount_dir" ] || [ ! -d "$layout_mount_dir" ]; then
    echo "Failed to mount the temporary DMG for Finder layout." >&2
    exit 1
fi

/usr/bin/SetFile -a C "$layout_mount_dir"
/usr/bin/SetFile -a V "$layout_mount_dir/.background" "$layout_mount_dir/.VolumeIcon.icns"

# Generate Finder's on-disk layout directly: no UI automation, app registration,
# or installation is needed on the release machine.
"$dmg_python" "$project_dir/Tools/DMGLayout.py" "$layout_mount_dir"

sync
hdiutil detach "$layout_device" >/dev/null
layout_device=""

hdiutil convert "$readwrite_image" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$work_dir/artifacts/$asset_name.dmg" >/dev/null

# The website download is a signed, notarized and stapled DMG.
codesign --force --sign "$release_identity" --timestamp "$work_dir/artifacts/$asset_name.dmg"
python3 "$project_dir/scripts/notarize-artifact.py" \
    "$work_dir/artifacts/$asset_name.dmg" "$notary_dir/dmg"
xcrun stapler staple "$work_dir/artifacts/$asset_name.dmg"
xcrun stapler validate "$work_dir/artifacts/$asset_name.dmg"
spctl --assess -vv --type open --context context:primary-signature "$work_dir/artifacts/$asset_name.dmg"

# Check the artifacts themselves, not just the source app.
hdiutil verify "$work_dir/artifacts/$asset_name.dmg"
hdiutil attach "$work_dir/artifacts/$asset_name.dmg" -readonly -nobrowse \
    -noautoopen -mountpoint "$mount_dir" -quiet
mounted=yes
test "$(readlink "$mount_dir/Applications")" = /Applications
test -f "$mount_dir/.DS_Store"
test -f "$mount_dir/.background/ShelterBar.png"
test -f "$mount_dir/.background/INSTALL.txt"
"$dmg_python" "$project_dir/Tools/DMGLayout.py" "$mount_dir" --verify
codesign --verify --strict --verbose=2 "$mount_dir/ShelterBar.app"
xcrun stapler validate "$mount_dir/ShelterBar.app"
cmp "$app_dir/Contents/MacOS/ShelterBar" "$mount_dir/ShelterBar.app/Contents/MacOS/ShelterBar"
cmp "$app_dir/Contents/Info.plist" "$mount_dir/ShelterBar.app/Contents/Info.plist"
hdiutil detach "$mount_dir" -quiet
mounted=no

ditto -x -k "$work_dir/artifacts/$asset_name.zip" "$work_dir/unzipped"
codesign --verify --strict --verbose=2 "$work_dir/unzipped/ShelterBar.app"
xcrun stapler validate "$work_dir/unzipped/ShelterBar.app"
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
printf '\nVerified release artifacts: %s\n' "$release_dir"
ls -lh "$release_dir/$asset_name.dmg" "$release_dir/$asset_name.zip" "$release_dir/SHA256SUMS"
