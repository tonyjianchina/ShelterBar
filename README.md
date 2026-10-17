# ShelterBar

**给菜单栏，留一点空白。** 为 macOS 设计的轻量菜单栏图标收纳工具。

[官网](https://shelterbar.tonyjianchina.chatgpt.site/) · [下载 v0.5.8 预览版](https://github.com/tonyjianchina/ShelterBar/releases/tag/v0.5.8) · [反馈问题](https://github.com/tonyjianchina/ShelterBar/issues)

## 下载与安装

当前提供 **macOS 26.0 及以上、Apple Silicon（M1 及更新芯片）** 安装包，暂不提供 Intel 版本。

- [下载 DMG](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.8/ShelterBar-0.5.8-macos-arm64.dmg)：打开后把 ShelterBar 拖进「应用程序」（Applications），然后推出磁盘。
- [下载 ZIP](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.8/ShelterBar-0.5.8-macos-arm64.zip)：解压后将应用移入“应用程序”。
- [SHA256 校验值](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.8/SHA256SUMS)

这是 **早期预览版**。自 v0.5.7 起使用固定的自签名证书 **“ShelterBar Self-Signed”** 签名（不再是 ad-hoc），但仍 **没有 Developer ID 签名，也未经过 Apple 公证**。

### 安装与第一次打开

1. **安装**：打开 DMG，把 ShelterBar 拖进「应用程序」（Applications）文件夹，然后推出磁盘。
2. **第一次打开**：在访达的「应用程序」文件夹里双击 ShelterBar（刚安装时，聚焦搜索可能要过几分钟才能搜到）。ShelterBar 没有经过 Apple 公证，系统会拦下并提示无法验证，先点「完成」关闭提示；然后打开「系统设置 → 隐私与安全性」，往下滚到「安全性」部分，点 ShelterBar 旁边的「仍要打开」，再确认一次「打开」（可能需要输入登录密码）。macOS 15 起，右键「打开」已不能绕过这一步。
   - 高级用户也可以在核对 SHA256 后，在终端运行 `xattr -dr com.apple.quarantine /Applications/ShelterBar.app`，再双击打开。
   - 每次下载只需放行一次。以后下载新版本覆盖安装时，如果系统再次拦下，按同样步骤放行即可；辅助功能等授权会保留，不用重新授权（从 v0.5.6 及更早版本升级除外，需重新授权一次）。
3. **打开之后**：ShelterBar 只在菜单栏运行，没有 Dock 图标，也没有普通窗口——请留意屏幕右上角菜单栏里新出现的收纳箱图标，点它即可展开收纳栏。首次启动时，收纳栏会自动在图标下方展开，并按引导请求授权：先是「辅助功能」和「输入监控」（必需），辅助功能生效后再请求「屏幕录制」（可选，只用于显示原始图标）。

请先确认下载来源与 SHA256；不要关闭 Gatekeeper。受管理的 Mac 可能不提供「仍要打开」。参考 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

**从 v0.5.6 及更早版本（ad-hoc 签名）升级：** 签名身份变化后，macOS 会把它视为新应用，需要重新授予一次“辅助功能”“输入监控”和“屏幕录制”（如列表里已有旧的 ShelterBar，先将其关闭再打开，或移除后重新添加）。此后的版本使用同一证书签名，授权会自动保留。

启动后会先请求“辅助功能”和“输入监控”权限；辅助功能一旦生效，就会立即询问“屏幕录制”，不再等待输入监控全部生效。前两项用于发现、拦截拖动并移动图标，缺少任何一项都不会开始拦截鼠标；屏幕录制只用于读取原始菜单栏状态图标，拒绝或稍后授权都不影响收纳，收纳栏会使用占位图标。

v0.5.8（build 23）取代未正式发布的 v0.5.7（build 22），功能相同，补充了安装与第一次打开的引导（含安装盘背景提示）。v0.5.7 起改用固定自签名证书，后续升级保留权限；修复浅色/白色图标对比度、全屏与自动隐藏菜单栏下的收纳、单个图标失败导致全部展开、刘海屏处理；点击收纳栏图标时只把这一个图标临时放回收纳栏正下方并打开其菜单，随后自动收回；图标缓存到磁盘，重启后不再显示“?”。详见 [版本说明](docs/releases/v0.5.8.md)。

图标可见时捕获，收纳栏打开时尝试更新隐藏图标；收纳栏关闭时，定时任务不会截图。更新失败保留上次成功的图像，没有可用图像时使用占位图标，不会中断收纳。已收纳图标的小尺寸 PNG 会缓存到本机 `~/Library/Application Support/ShelterBar/IconCache/`，重启后直接显示；图标被移回菜单栏后即删除对应缓存，缓存从不上传。新出现的可移动菜单栏项由实时扫描自动纳入，无需预先枚举应用或图标。

应用只显示在菜单栏，不显示 Dock 图标。第三方图标、刘海屏与多显示器的兼容性仍需实际验证；建议避免同时运行其他菜单栏管理工具。完整说明见 [发布与安装指南](docs/RELEASE.md)。

## About

A mouse-first macOS 26 menu-bar shelf. Click the archive icon in the original
top-right menu-bar area to open a row underneath it.

## Install and first launch

1. **Install:** open the DMG, drag ShelterBar into Applications, then eject the disk image.
2. **First launch:** double-click ShelterBar in Finder → Applications (Spotlight may need a
   few minutes to index a fresh install). ShelterBar is not notarized by Apple, so macOS
   blocks it: click **Done**, open **System Settings → Privacy & Security**, scroll down to
   **Security**, click **Open Anyway** next to ShelterBar and confirm **Open** (you may be
   asked for your password). Since macOS 15, Control-click → Open no longer bypasses this.
   - Advanced: after checking the SHA256, run
     `xattr -dr com.apple.quarantine /Applications/ShelterBar.app`, then open the app.
   - Approve once per download. If macOS blocks a newly downloaded update, repeat the same
     step; permission grants are kept (except when upgrading from v0.5.6 or earlier).
3. **After launch:** ShelterBar runs only in the menu bar — no Dock icon and no regular
   window. Look for the new archive-box icon at the top right of the menu bar. On first
   launch the shelf opens under it and onboarding asks for **Accessibility** and **Input
   Monitoring** (required), then **Screen Recording** (optional, only for original icons)
   once Accessibility is granted.

Verify the download source and SHA256 first, and do not disable Gatekeeper. Managed
Macs may not offer Open Anyway. See [Apple's guidance](https://support.apple.com/102445).

## Use

1. Grant **Accessibility** and **Input Monitoring** when ShelterBar requests them. Both are
   required before ShelterBar intercepts any drag. If an older (ad-hoc signed, v0.5.6 or
   earlier) build is already listed, switch ShelterBar off and on — or remove and re-add it —
   in System Settings → Privacy & Security → Accessibility, Input Monitoring and Screen
   Recording. This is needed once; later releases keep the grants.
2. The **Screen Recording** request follows as soon as Accessibility is granted (it does
   not wait for Input Monitoring) and remains optional.
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

Accessibility and Input Monitoring are required to discover other apps' menu-bar
items, intercept a drag while the shelf is open, and request native rearrangement. Screen Recording
is optional and allows ScreenCaptureKit to capture an individual original status icon
only when its process PID, status window, and accessibility (AX) bounds match
strictly. Only collected (stowed) items' small icon PNGs are written to
`~/Library/Application Support/ShelterBar/IconCache/` so the shelf can show them
after a restart; an item's entry is deleted when it is restored to the menu bar.
ShelterBar does not capture audio, record video, save full screenshots, or upload
anything.

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
changes. A single item that refuses to move is reported and left visible; it
no longer expands every collected item. A failed entry check still leaves the
bar expanded with an explanation. Full-screen and auto-hidden menu bars are
handled, and releases that would land under the notch are refused.

Some system items (clock, Control Center, camera/microphone indicator) are not
draggable through ShelterBar. Items without an accessible menu-bar element
cannot be managed. Anonymous multi-item entries without a stable AX identifier
are kept only for the current app session, to avoid restoring the wrong item.
Only one display's native menu-bar layout is changed per operation; a display
change cancels the operation and reveals the section before recovery.

Clicking a collected item temporarily reveals only that item right under the
shelf panel, opens its menu, and moves it back after the menu closes (with a
short grace period). The cursor is restored after each synthetic drag, and a
pending restore is recorded first, so a crash or quit mid-way is repaired on the
next launch. If there is no room (for example next to the notch), ShelterBar
explains instead of expanding the bar. Known issues: the cursor may flicker
briefly, the item returns about 1.5 s after the menu closes, and macOS 27 will
likely need a different approach. Quitting removes ShelterBar's handle and
boundary and reveals the real items; it does not remove another app's item.

This is an early preview release, not a notarized release. Since v0.5.7 it is
signed with the fixed self-signed certificate "ShelterBar Self-Signed", so macOS
keeps Accessibility, Input Monitoring and Screen Recording grants across
updates. Upgrading from an ad-hoc build (v0.5.6 or earlier) requires granting
them once more. The first launch needs System Settings → Privacy & Security →
Open Anyway (see Install and first launch). Avoid running another menu-bar manager at the same time.

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
`dist/releases/v0.5.8/`. See [docs/RELEASE.md](docs/RELEASE.md) for requirements
and release limitations.

## Maintainer: signing identity

Release and local builds are signed with the self-signed identity
**ShelterBar Self-Signed** (SHA-1 `ABCD7A5B7B4FF47F6E6448FAB665FAF8F0C5F910`, valid
until 2036-10-14). The private key lives only in the maintainer's login keychain;
never commit it.

- Backup/restore: `~/Documents/ShelterBar-Signing-Backup/` holds the `.p12`
  (certificate + key), the public `.cer.pem`, and a `README.txt` with the restore
  commands (`security import … -T /usr/bin/codesign`, optional
  `security add-trusted-cert`, then `security find-identity -p codesigning`). The
  `.p12` password is stored in the login keychain; keep an offline copy of the folder.
  Losing the key changes the designated requirement and every user must re-grant
  permissions.
- Expected designated requirement (DR):

  ```text
  identifier "com.jensen.shelterbar" and certificate leaf = H"abcd7a5b7b4ff47f6e6448fab665faf8f0c5f910"
  ```

- Switches:
  - `SHELTERBAR_RELEASE_CODESIGN_IDENTITY` — identity used by `package-release.sh`
    (default `ShelterBar Self-Signed`; packaging refuses to run if it is missing;
    `-` forces ad-hoc and must not be used for public releases).
  - `SHELTERBAR_EXPECTED_DR` — when set, `package-release.sh` aborts if the built
    app's DR differs from this string. Always set it to the value above when releasing.
  - `SHELTERBAR_HARDENED_RUNTIME` — `1` (default) signs with the hardened runtime;
    `0` disables it.
  - `SHELTERBAR_CODESIGN_IDENTITY` — identity for `build-app.sh`; for local builds use
    `SHELTERBAR_CODESIGN_IDENTITY="ShelterBar Self-Signed" ./scripts/build-app.sh release`.

Verify with `codesign -d -r- dist/ShelterBar.app`.

## Website

The official website source is in `website/dist/` (plain HTML, CSS, and JavaScript).
Preview it with `python3 -m http.server 4178 --directory website/dist`.
