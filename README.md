# ShelterBar

**给菜单栏，留一点空白。** 为 macOS 设计的轻量菜单栏图标收纳工具。

[官网](https://shelterbar.tonyjianchina.chatgpt.site/) · [下载 v0.5.4 预览版](https://github.com/tonyjianchina/ShelterBar/releases/tag/v0.5.4) · [反馈问题](https://github.com/tonyjianchina/ShelterBar/issues)

## 下载与安装

当前提供 **macOS 26.0 及以上、Apple Silicon（M1 及更新芯片）** 安装包，暂不提供 Intel 版本。

- [下载 DMG](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.4/ShelterBar-0.5.4-macos-arm64.dmg)：打开后将左侧 ShelterBar 拖到右侧 Applications 文件夹。
- [下载 ZIP](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.4/ShelterBar-0.5.4-macos-arm64.zip)：解压后将应用移入“应用程序”。
- [SHA256 校验值](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.4/SHA256SUMS)

这是 **早期预览版**，采用 ad-hoc 签名，尚无 Developer ID 签名或 Apple 公证。如果首次打开被系统阻止，可按照 [Apple 官方说明](https://support.apple.com/zh-cn/102445)，在确认来源后通过“系统设置 → 隐私与安全性 → 仍要打开”允许该应用（如系统提供此选项）。

启动后会先询问“辅助功能”权限；检测到授权成功后，会立即继续询问“屏幕录制”权限。辅助功能用于发现和移动图标；屏幕录制只用于读取原始菜单栏状态图标，拒绝或稍后授权都不影响收纳，收纳栏会使用占位图标。

v0.5.4（build 19）包含原生窗口发现、菜单栏入口和图标对比度修复：兼容 macOS 26 合成显示的状态栏窗口，等待移动动画与辅助功能坐标同步，忽略未参与整理的失效条目；可见入口与收起边界分离，并在收起前检查入口位置；白色及灰阶图标会随收纳栏外观调整对比度，保留彩色标记。详见 [版本说明](docs/releases/v0.5.4.md)。

图标可见时捕获，收纳栏打开时尝试更新隐藏图标；收纳栏关闭时，定时任务不会截图。更新失败保留上次成功的图像，没有可用图像时使用占位图标，不会中断收纳。新出现的可移动菜单栏项由实时扫描自动纳入，无需预先枚举应用或图标。

应用只显示在菜单栏，不显示 Dock 图标。第三方图标、刘海屏与多显示器的兼容性仍需实际验证；建议避免同时运行其他菜单栏管理工具。完整说明见 [发布与安装指南](docs/RELEASE.md)。

## About

A mouse-first macOS 26 menu-bar shelf. Click the archive icon in the original
top-right menu-bar area to open a row underneath it.

## Use

1. Grant **Accessibility** when ShelterBar requests it. ShelterBar detects the
   grant and immediately continues to the Screen Recording request. If an older development
   build is already listed, switch ShelterBar off and on in System Settings →
   Privacy & Security → Accessibility.
2. The **Screen Recording** request follows automatically and remains optional.
   It shows the original status icons; collection
   and restoration continue to work with placeholders when it is denied. Use the in-app
   **允许读取图标** (Allow icon access) or **打开设置** (Open Settings) control.
   You may need to quit and reopen ShelterBar after granting access.
3. Open the shelf, then drag a movable icon from the top menu bar into the row.
4. Drag an icon from the shelf back to the right-hand menu-bar area to restore it.
   You do not need to hold Command.
5. Drag shelf icons sideways to reorder them. Escape or dropping elsewhere
   cancels the gesture.
6. Use the pin to keep the row open. The More menu provides **Show all top icons**
   for recovery and **Refresh and restore collection** to retry the saved layout.

The handle uses a native template image: macOS chooses white or dark tint to
match its menu bar. There are no app-created top-bar icon proxies.

## Permissions and boundaries

Accessibility is required to discover other apps' menu-bar items, intercept a
drag while the shelf is open, and request native rearrangement. Screen Recording
is optional and allows ScreenCaptureKit to capture an individual original status icon
only when its process PID, status window, and accessibility (AX) bounds match
strictly. Captured images are cached in memory. ShelterBar does not capture
audio, record video, save screenshots to disk, or upload them.

Monochrome and neutral shaded glyphs adapt their contrast to the shelf's
appearance while preserving tonal detail and small colored badges. Color-led
status images retain their original colors. All images preserve their aspect
ratio. Icons are captured while visible; hidden icons receive refresh attempts
while the shelf is open. The periodic task does not capture while the shelf is
closed. A failed refresh keeps the last successful image; without one, the shelf
uses a placeholder without interrupting collection. This is a cached
snapshot, not a guarantee that every changing status will update immediately.

macOS owns the real menu-bar views. ShelterBar keeps a fixed-width visible archive
entry separate from the expanding collection boundary. Collected items sit to
the boundary's left; the entry stays on its resident side. Before collapsing,
ShelterBar checks that the entry is in the display's safe area and outside the
camera housing. Each destination frame is checked before a move is posted, and
fresh accessibility geometry must confirm the result before saved placement
changes. Failed moves or entry checks leave the bar expanded and display an
explanation.

Some system items (clock, Control Center, camera/microphone indicator) are not
draggable through ShelterBar. Items without an accessible menu-bar element
cannot be managed. Anonymous multi-item entries without a stable AX identifier
are kept only for the current app session, to avoid restoring the wrong item.
Only one display's native menu-bar layout is changed per operation; a display
change cancels the operation and reveals the section before recovery.

Clicking a collected item temporarily reveals it and opens its original menu.
Its saved collection is restored on the next shelf opening or explicit refresh,
so the opened menu is not interrupted by a background timer. Quitting removes
ShelterBar's handle and reveals the real items; it does not remove another app's item.

This is an early preview release, not a notarized release. Ad-hoc signing can cause
macOS to require permissions again after rebuilding. Avoid
running another menu-bar manager at the same time.

## Build and run

```bash
./scripts/build-app.sh
open dist/ShelterBar.app --args --preview
```

The build targets Apple Silicon and macOS 26+. The first test build downloads the
official Swift Testing package (the Command Line Tools installation here does
not expose a standalone Testing module).

## Verify

```bash
swift test --force-resolved-versions
git diff --check -- .
```

Automated coverage includes gesture cancellation, synthetic-event bypass,
physical move confirmation, cross-display rejection, permission revocation,
stable identity handling, and exclusion of top-visible icons from the shelf.
Original-icon capture and native third-party movement still need an authorized
macOS session for full compatibility validation; unit tests do not establish OS
compatibility. See [docs/MVP.md](docs/MVP.md) for acceptance.

## Package a release

```sh
python3.11 -m venv .build/dmg-tools
.build/dmg-tools/bin/pip install -r scripts/dmg-requirements.txt
./scripts/package-release.sh
```

This creates and verifies the DMG, ZIP, and SHA256 sums under
`dist/releases/v0.5.4/`. See [docs/RELEASE.md](docs/RELEASE.md) for requirements
and release limitations.

## Website

The official website source is in `website/dist/` (plain HTML, CSS, and JavaScript).
Preview it with `python3 -m http.server 4178 --directory website/dist`.
