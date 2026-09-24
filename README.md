# ShelterBar

**给菜单栏，留一点空白。** 为 macOS 设计的轻量菜单栏图标收纳工具。

[官网](https://shelterbar.tonyjianchina.chatgpt.site/) · [下载 v0.3.1 预览版](https://github.com/tonyjianchina/ShelterBar/releases/tag/v0.3.1) · [反馈问题](https://github.com/tonyjianchina/ShelterBar/issues)

## 下载与安装

当前提供 **macOS 26.0 及以上、Apple Silicon（M1 及更新芯片）** 安装包，暂不提供 Intel 版本。

- [下载 DMG](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.3.1/ShelterBar-0.3.1-macos-arm64.dmg)：打开后将 ShelterBar.app 拖入 Applications。
- [下载 ZIP](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.3.1/ShelterBar-0.3.1-macos-arm64.zip)：解压后将应用移入“应用程序”。
- [SHA256 校验值](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.3.1/SHA256SUMS)

这是 **早期预览版**，采用 ad-hoc 签名，尚无 Developer ID 签名或 Apple 公证。如果首次打开被系统阻止，可按照 [Apple 官方说明](https://support.apple.com/zh-cn/102445)，在确认来源后通过“系统设置 → 隐私与安全性 → 仍要打开”允许该应用（如系统提供此选项）。

启动后需要“辅助功能”权限来管理图标，以及“屏幕录制”权限来读取原始菜单栏状态图标。应用内提供 **“允许读取图标”** 和 **“打开设置”**；授权后可能需要退出并重新打开 ShelterBar。

v0.3.1 沿用 v0.3.0 的原生菜单栏拖拽与严格状态窗口匹配，并更新了更清晰、更轻量的应用图标。应用使用 ScreenCaptureKit 仅截取与进程、状态窗口和辅助功能（AX）范围严格匹配的单个状态图标。截图只缓存在内存中，不写入磁盘、不录制视频、不采集音频，也不上传。

图标可见时捕获，收纳栏打开时尝试更新隐藏图标；收纳栏关闭时，定时任务不会截图。更新失败保留上次成功的图像。首次没有可用图像时，会展开恢复真实菜单栏项目，避免把它隐藏后留下空白。

应用只显示在菜单栏，不显示 Dock 图标。第三方图标、刘海屏与多显示器的兼容性仍需实际验证；建议避免同时运行其他菜单栏管理工具。完整说明见 [发布与安装指南](docs/RELEASE.md)。

## About

A mouse-first macOS 26 menu-bar shelf. Click the archive icon in the original
top-right menu-bar area to open a row underneath it.

## Use

1. Grant **Accessibility** when ShelterBar requests it. If an older development
   build is already listed, switch ShelterBar off and on in System Settings →
   Privacy & Security → Accessibility.
2. Allow **Screen Recording** to read the original status icons. Use the in-app
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
permission allows ScreenCaptureKit to capture an individual original status icon
only when its process PID, status window, and accessibility (AX) bounds match
strictly. Captured images are cached in memory. ShelterBar does not capture
audio, record video, save screenshots to disk, or upload them.

Monochrome glyphs adapt to the shelf's appearance; colored and multi-shade
status images retain their original colors. All images preserve their aspect
ratio. Icons are captured while visible; hidden icons receive refresh attempts
while the shelf is open. The periodic task does not capture while the shelf is
closed. A failed refresh keeps the last successful image. If there is no usable
image on the first capture, the real menu-bar items are revealed for recovery
instead of remaining hidden behind an empty shelf entry. This is a cached
snapshot, not a guarantee that every changing status will update immediately.

macOS owns the real menu-bar views. ShelterBar puts collected items to the left
of its divider and expands that divider to move them off the top row. Each move
is checked using fresh accessibility geometry before the saved placement
changes. Failed moves leave the bar expanded and display an explanation.

Some system items (clock, Control Center, camera/microphone indicator) are not
draggable through ShelterBar. Items without an accessible menu-bar element
cannot be managed. Anonymous multi-item entries without a stable AX identifier
are kept only for the current app session, to avoid restoring the wrong item.
Only one display's native menu-bar layout is changed per operation; a display
change cancels the operation and reveals the section before recovery.

Clicking a collected item temporarily reveals it and opens its original menu.
Its saved collection is restored on the next shelf opening or explicit refresh,
so the opened menu is not interrupted by a background timer. Quitting removes
the divider and reveals the real items; it does not remove another app's item.

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
./scripts/package-release.sh
```

This creates and verifies the DMG, ZIP, and SHA256 sums under
`dist/releases/v0.3.1/`. See [docs/RELEASE.md](docs/RELEASE.md) for requirements
and release limitations.

## Website

The official website source is in `website/dist/` (plain HTML, CSS, and JavaScript).
Preview it with `python3 -m http.server 4178 --directory website/dist`.
