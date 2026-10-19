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
dmg_python=${SHELTERBAR_DMG_PYTHON:-"$project_dir/.build/dmg-tools/bin/python"}
if ! "$dmg_python" -c 'import ds_store, mac_alias' 2>/dev/null; then
    echo "DMG tools missing. Create .build/dmg-tools with Python 3.10+ and install scripts/dmg-requirements.txt; see docs/RELEASE.md." >&2
    exit 1
fi

# Releases are signed with a stable self-signed identity ("ShelterBar Self-Signed")
# so the designated requirement stays constant and users' TCC grants survive
# updates. Its private key lives only in the maintainer's keychain (+ offline
# .p12 backup); never commit it. Set SHELTERBAR_RELEASE_CODESIGN_IDENTITY=- to
# fall back to ad-hoc explicitly.
release_identity=${SHELTERBAR_RELEASE_CODESIGN_IDENTITY:-"ShelterBar Self-Signed"}
if [ "$release_identity" != - ] && ! security find-identity -p codesigning \
        | grep -Fq "\"$release_identity\""; then
    echo "Release signing identity '$release_identity' not found in the keychain." >&2
    echo "Restore it from the .p12 backup (see docs/RELEASE.md); refusing to ship a build with a different requirement." >&2
    exit 1
fi
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

mkdir -p "$work_dir/image/.background" "$work_dir/artifacts" "$mount_dir"
ditto "$app_dir" "$work_dir/image/ShelterBar.app"
ln -s /Applications "$work_dir/image/Applications"
ditto "$app_dir/Contents/Resources/AppIcon.icns" "$work_dir/image/.VolumeIcon.icns"
swift "$project_dir/Tools/GenerateDMGBackground.swift" \
    "$work_dir/image/.background/ShelterBar.png"
cat > "$work_dir/image/.background/INSTALL.txt" <<INSTALL
ShelterBar v$version - 预览版 / Preview
Apple Silicon (M1 及更新芯片)，macOS 14.0 或更新版本。

安装：将 ShelterBar.app 拖入 Applications，然后推出磁盘映像。
打开“应用程序”中的 ShelterBar，按提示在“系统设置 → 隐私与安全性”
中开启辅助功能和输入监控。辅助功能生效后，应用会立即询问“屏幕录制”；它仅用于
读取原始菜单栏状态图标，可以拒绝或稍后开启。未授权时使用占位图标，
收纳与恢复功能仍然可用。
应用内提供“允许读取图标”和“打开设置”，授权后可能需要退出并重新打开。
应用只显示在菜单栏，没有 Dock 图标和窗口；请留意右上角菜单栏的收纳箱图标。

图标读取：使用 ScreenCaptureKit，仅截取与进程 PID、状态窗口及辅助功能
（AX）范围严格匹配的单个状态图标。只有已收纳图标的小尺寸 PNG 会缓存到
~/Library/Application Support/ShelterBar/IconCache/，移回菜单栏即删除；
不采集音频、不录制视频、不保存整屏截图，也不上传任何图像。单色及灰阶图标
随外观调整对比度，同时保留灰阶细节和彩色标记；彩色图标保留原色，浅色彩色
图标在浅色收纳栏上加衬底，均保持比例。可见时捕获，收纳栏打开时尝试更新
隐藏图标；收纳栏关闭时，定时任务不会截图。失败保留上次成功图像，
没有可用图像时显示占位图标，不会中断收纳。
原始图标捕获与第三方图标移动的完整兼容性，仍待授权后的真实会话验证。

本预览版使用固定自签名证书“ShelterBar Self-Signed”签名，没有 Developer ID
签名或 Apple 公证。从 v0.5.6 及更早（ad-hoc）版本升级，需要重新授予一次辅助
功能、输入监控和屏幕录制；之后的更新会保留授权。
第一次打开：在访达“应用程序”里双击 ShelterBar。因为没有经过 Apple 公证，
系统会拦下；先点“完成”，再到“系统设置 → 隐私与安全性”，往下滚到“安全性”，
点“仍要打开”，再确认“打开”。macOS 15 起右键“打开”已不能绕过。
请先核实下载来源及 SHA256 校验值；受管理设备可能不提供该选项。
每次下载只需放行一次。
Apple 官方说明：https://support.apple.com/zh-cn/102445

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
matching its process PID, status window, and accessibility (AX) bounds. Images
are kept in memory; only collected items' small PNGs are cached under
~/Library/Application Support/ShelterBar/IconCache/ and pruned when restored.
No audio capture, video recording, full screenshots, or network uploads.
Monochrome and neutral shaded glyphs adapt their contrast to the shelf
appearance, preserving tonal detail and colored badges. Color-led status images
retain their colors (light ones get a contrast plate). Aspect ratios are preserved.
Icons are captured while visible; hidden icons receive refresh attempts while
the shelf is open. The periodic task does not capture while the shelf is closed.
A failed refresh retains the last successful image. If no capture is available,
the shelf uses a placeholder without interrupting collection or restoration.
Full original-icon and native third-party movement compatibility still requires
validation in an authorized macOS session.

This preview is signed with the fixed self-signed "ShelterBar Self-Signed"
certificate, without Developer ID signing or Apple notarization. Upgrading from
an ad-hoc build (v0.5.6 or earlier) needs one re-grant of Accessibility, Input
Monitoring and Screen Recording; later updates keep them.
macOS blocks the first launch because the app is not notarized: click Done, then
open System Settings > Privacy & Security, scroll to Security, click Open Anyway
and confirm Open. Control-click > Open no longer bypasses this on macOS 15+.
Verify the download source and SHA256 first. Approve once per download.
Managed devices may not offer an exception. Do not disable Gatekeeper.
Apple guidance: https://support.apple.com/102445
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
