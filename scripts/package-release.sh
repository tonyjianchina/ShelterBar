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

# A machine-local self-signed identity is useful for preserving TCC permissions
# during development, but must never be shipped to other Macs. Preview releases
# stay ad-hoc unless an explicit release identity is provided.
SHELTERBAR_CODESIGN_IDENTITY=${SHELTERBAR_RELEASE_CODESIGN_IDENTITY:--} \
    "$project_dir/scripts/build-app.sh" release
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
Apple Silicon (M1 及更新芯片)，macOS 26.0 或更新版本。

安装：将 ShelterBar.app 拖入 Applications，然后推出磁盘映像。
打开“应用程序”中的 ShelterBar，按提示在“系统设置 → 隐私与安全性
→ 辅助功能”中授权。“屏幕录制”仅用于读取原始菜单栏状态图标，可以
按需开启；未授权时使用占位图标，收纳与恢复功能仍然可用。
应用内提供“允许读取图标”和“打开设置”，授权后可能需要退出并重新打开。
应用显示在菜单栏，不显示 Dock 图标。

图标读取：使用 ScreenCaptureKit，仅截取与进程 PID、状态窗口及辅助功能
（AX）范围严格匹配的单个状态图标。截图仅缓存在内存中，不采集音频、
不录制视频、不把截图写入磁盘，也不上传截图。单色图标随外观配色，彩色
及多灰度状态图标保留原色，均保持比例。可见时捕获，收纳栏打开时尝试更新
隐藏图标；收纳栏关闭时，定时任务不会截图。失败保留上次成功图像，
没有可用图像时显示占位图标，不会中断收纳。
原始图标捕获与第三方图标移动的完整兼容性，仍待授权后的真实会话验证。

本预览版使用临时签名（ad-hoc），没有 Developer ID 签名或 Apple 公证。
如果首次打开被阻止，请先核实下载来源及 SHA256 校验值，再到
“系统设置 → 隐私与安全性”点击“仍要打开”，随后确认“打开”。
如果系统未提供该选项，请勿绕过安全策略；受管理设备可能不允许例外。
Apple 官方说明：https://support.apple.com/zh-cn/102445

Install: drag ShelterBar.app to Applications, then eject this disk image.
Open ShelterBar from Applications and allow Accessibility. Screen Recording is
optional and only enables original status icons; placeholders are used without it.
Use “允许读取图标” (Allow icon access) or “打开设置” (Open Settings) in the app.
You may need to quit and reopen ShelterBar after granting permission.
ShelterBar is a menu-bar app and does not show a Dock icon.

ScreenCaptureKit captures a single original status icon only after strictly
matching its process PID, status window, and accessibility (AX) bounds. Images
are cached in memory: no audio capture, video recording, screenshot files,
or network uploads. Monochrome glyphs follow the shelf appearance; colored and
multi-shade status images retain their colors. Aspect ratios are preserved.
Icons are captured while visible; hidden icons receive refresh attempts while
the shelf is open. The periodic task does not capture while the shelf is closed.
A failed refresh retains the last successful image. If no capture is available,
the shelf uses a placeholder without interrupting collection or restoration.
Full original-icon and native third-party movement compatibility still requires
validation in an authorized macOS session.

This preview is ad-hoc signed, without Developer ID signing or Apple notarization.
If macOS blocks the first launch, verify the download source and SHA256, then use
System Settings > Privacy & Security > Open Anyway and confirm Open.
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

osascript - "ShelterBar $version" <<'APPLESCRIPT'
on run argv
  set volumeName to item 1 of argv

  tell application "Finder"
    tell disk volumeName
      open
      set installerWindow to container window
      set current view of installerWindow to icon view
      set toolbar visible of installerWindow to false
      set statusbar visible of installerWindow to false
      set pathbar visible of installerWindow to false
      set bounds of installerWindow to {180, 120, 900, 630}

      set viewOptions to icon view options of installerWindow
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 112
      set text size of viewOptions to 16
      set background picture of viewOptions to file ".background:ShelterBar.png"

      set position of item "ShelterBar.app" of installerWindow to {170, 286}
      set position of item "Applications" of installerWindow to {550, 286}

      update without registering applications
      delay 2
      close installerWindow
      open
      delay 2
    end tell
  end tell
end run
APPLESCRIPT

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
