# ShelterBar

**给菜单栏，留一点空白。** 为 macOS 设计的轻量菜单栏图标收纳工具。

[官网](https://shelterbar.tonyjianchina.chatgpt.site/) · [下载 v0.1.0 预览版](https://github.com/tonyjianchina/ShelterBar/releases/tag/v0.1.0) · [反馈问题](https://github.com/tonyjianchina/ShelterBar/issues)

## 下载与安装

当前提供 **macOS 26.0 及以上、Apple Silicon（M1 及更新芯片）** 安装包，暂不提供 Intel 版本。

- [下载 DMG](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.1.0/ShelterBar-0.1.0-macos-arm64.dmg)：打开后将 ShelterBar.app 拖入 Applications。
- [下载 ZIP](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.1.0/ShelterBar-0.1.0-macos-arm64.zip)：解压后将应用移入“应用程序”。
- [SHA256 校验值](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.1.0/SHA256SUMS)

这是 **早期预览版**，采用 ad-hoc 签名，尚无 Developer ID 签名或 Apple 公证。如果首次打开被系统阻止，可按照 [Apple 官方说明](https://support.apple.com/zh-cn/102445)，在确认来源后通过“系统设置 → 隐私与安全性 → 仍要打开”允许该应用（如系统提供此选项）。启动后需授予“辅助功能”权限，才能管理菜单栏图标。

应用只显示在菜单栏，不显示 Dock 图标。第三方图标、刘海屏与多显示器的兼容性仍需实际验证；建议避免同时运行其他菜单栏管理工具。完整说明见 [发布与安装指南](docs/RELEASE.md)。

## About

A mouse-first macOS 26 menu-bar shelf. Click the archive icon in the original
top-right menu-bar area to open a row underneath it.

## Use

1. Grant **Accessibility** when ShelterBar requests it. If an older development
   build is already listed, switch ShelterBar off and on in System Settings →
   Privacy & Security → Accessibility.
2. Open the shelf, then drag a movable icon from the top menu bar into the row.
3. Drag an icon from the shelf back to the right-hand menu-bar area to restore it.
   You do not need to hold Command.
4. Drag shelf icons sideways to reorder them. Escape or dropping elsewhere
   cancels the gesture.
5. Use the pin to keep the row open. The More menu provides **Show all top icons**
   for recovery and **Refresh and restore collection** to retry the saved layout.

The handle uses a native template image: macOS chooses white or dark tint to
match its menu bar. There are no app-created top-bar icon proxies.

## Permissions and boundaries

Accessibility is required to discover other apps' menu-bar items, intercept a
drag while the shelf is open, and request native rearrangement. ShelterBar does
not request Screen Recording, store screen content, or use network services.
Shelf thumbnails currently use application icons, rather than screenshots of
the live status glyph; the tooltip identifies each item.

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
macOS to require Accessibility authorization again after rebuilding. Avoid
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
Native third-party movement also needs an authorized macOS session; unit tests
do not establish OS compatibility. See [docs/MVP.md](docs/MVP.md) for acceptance.

## Package a release

```sh
./scripts/package-release.sh
```

This creates and verifies the DMG, ZIP, and SHA256 sums under
`dist/releases/v0.1.0/`. See [docs/RELEASE.md](docs/RELEASE.md) for requirements
and release limitations.

## Website

The official website source is in `website/dist/` (plain HTML, CSS, and JavaScript).
Preview it with `python3 -m http.server 4178 --directory website/dist`.
