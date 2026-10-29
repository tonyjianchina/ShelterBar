# ShelterBar

**重点适配 macOS 27 的菜单栏图标收纳工具。**

菜单栏太挤时，把暂时不用的图标拖进 ShelterBar。需要时点开原来的菜单，或者再拖回顶部。没有账号、广告或遥测，布局和图标缓存只保存在本机。

[官网](https://shelterbar.tonyjianchina.chatgpt.site/) · [下载 v0.5.12](https://github.com/tonyjianchina/ShelterBar/releases/tag/v0.5.12) · [反馈问题](https://github.com/tonyjianchina/ShelterBar/issues)

## macOS 27 重点适配

macOS 27 改变了菜单栏图标的管理方式，传统的 Command 拖动在部分场景下已经不可靠。ShelterBar 针对新版系统增加了专用收纳路径，让图标仍可被收起、恢复和点击使用。

- 运行时适配 macOS 27 的系统 `MenuBarAgent` 可见性机制。
- 收纳后仍可点击图标，打开它原来的菜单；菜单关闭后自动收回。
- 应用启动、退出或操作失败时，会校验并恢复真实菜单栏状态。
- 同时兼容 macOS 14 Sonoma 及以上版本。

> macOS 27 下的系统接口以应用为单位。同一应用提供多个菜单栏图标时，目前不能逐个独立收纳。系统后续更新也可能改变这一行为。

## 能做什么

- **拖入收纳**：打开收纳栏，把可移动的顶部图标直接拖进去，不需要按住 Command。
- **拖回恢复**：把收纳栏里的图标拖回顶部菜单栏，也可以横向拖动调整顺序。
- **直接使用**：点击已收纳图标，会临时显示该图标并打开原菜单，使用完自动收回。
- **自动记住**：保存收纳布局，应用重启后继续生效；运行期间新出现的图标也会被发现。
- **随时找回**：可固定收纳栏，也可从“更多”菜单显示全部图标或刷新并恢复布局。
- **适配复杂布局**：处理刘海区域、自动隐藏菜单栏、全屏空间和多显示器切换等情况。

## 下载

当前版本：**v0.5.12 · build 35 · 预览版**

系统要求：**macOS 14 Sonoma 及以上，Apple Silicon（M1 及更新芯片）**。暂不提供 Intel 版本。

- [下载 DMG](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.12/ShelterBar-0.5.12-macos-arm64.dmg)
- [下载 ZIP](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.12/ShelterBar-0.5.12-macos-arm64.zip)
- [查看 SHA256 校验值](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.12/SHA256SUMS)

这是使用固定自签名证书构建的早期预览版，尚未使用 Developer ID 签名，也未经过 Apple 公证。

## 安装与第一次打开

1. 打开 DMG，把 ShelterBar 拖进“应用程序”，然后推出安装盘。
2. 在访达的“应用程序”中双击 ShelterBar。
3. 如果 macOS 提示无法验证，先点“完成”，再前往“系统设置 → 隐私与安全性 → 安全性”，点击 ShelterBar 旁的“仍要打开”。
4. 打开成功后，留意右上角菜单栏里的收纳箱图标。ShelterBar 没有 Dock 图标，也没有普通窗口。

高级用户核对 SHA256 后，也可以运行：

```sh
xattr -dr com.apple.quarantine /Applications/ShelterBar.app
```

从 v0.5.6 或更早的 ad-hoc 签名版本升级时，需要重新授权一次。v0.5.7 及之后使用同一签名身份，正常覆盖安装会保留权限。

## 权限说明

| 权限 | 是否必需 | 用途 |
| --- | --- | --- |
| 辅助功能 | 必需 | 发现菜单栏图标，并请求系统移动它们 |
| 输入监控 | 必需 | 识别从菜单栏到收纳栏的鼠标拖动 |
| 屏幕录制 | 可选 | 首次读取尚未缓存的菜单栏图标；拒绝后仍能收纳，但会显示占位图标 |

申请输入权限时，ShelterBar 只触发 macOS 原生权限弹窗，不会同时打开系统设置。请在弹窗里点击“打开系统设置”；如果系统没有再次显示弹窗，再使用收纳栏里的“打开设置”。

屏幕录制权限不会用于录音、录像或保存整屏截图。ShelterBar 只读取严格匹配的单个状态图标，并按稳定的应用与菜单项标识保存到本地缓存；缓存命中后的周期扫描不会再截图或重新检查录屏权限。

## 使用方法

1. 点击右上角的收纳箱图标，打开收纳栏。
2. 把可移动的菜单栏图标拖进收纳栏。
3. 点击收纳后的图标，可打开它原来的菜单。
4. 把图标拖回顶部菜单栏，即可取消收纳。
5. 使用图钉保持收纳栏展开；使用“更多”菜单显示全部图标或重新应用布局。

按 `Esc` 或把图标放到无效区域会取消本次拖动，不会改变现有布局。

## 隐私与本地数据

ShelterBar 不需要账号，不包含广告和遥测，也不会上传图像或使用记录。

已收纳图标的小尺寸 PNG 会缓存在：

```text
~/Library/Application Support/ShelterBar/IconCache/
```

图标恢复到顶部菜单栏后，对应缓存会被删除。捕获失败时会保留上次成功的图标；没有缓存时使用占位图标，不影响收纳和恢复。

## 已知限制

- 时钟、控制中心、摄像头或麦克风指示器等系统固定项目不能收纳。
- 没有提供辅助功能接口的第三方菜单栏图标无法管理。
- macOS 27 下，同一应用的多个菜单栏图标不能逐个独立收纳。
- 刘海旁没有安全空间时，ShelterBar 会拒绝移动并显示提示。
- 原始图标可能短暂显示旧状态；点击菜单后，图标通常约 1.5 秒后自动收回。
- 请避免与其他菜单栏管理工具同时运行。

这是预览版。第三方应用、刘海屏、多显示器和未来 macOS 更新仍可能带来兼容性变化。

## 从源码运行

```sh
./scripts/build-app.sh
open dist/ShelterBar.app --args --preview
```

运行测试：

```sh
swift test --force-resolved-versions
git diff --check -- .
```

打包发布版本：

```sh
python3.11 -m venv .build/dmg-tools
.build/dmg-tools/bin/pip install -r scripts/dmg-requirements.txt
./scripts/package-release.sh
```

脚本会生成并验证 DMG、ZIP 和 SHA256SUMS。发布签名、designated requirement、验收范围与已知限制见 [发布指南](docs/RELEASE.md)。

## 更多信息

- [v0.5.12 发布说明](docs/releases/v0.5.12.md)
- [完整发布与安装指南](docs/RELEASE.md)
- [MVP 验收清单](docs/MVP.md)
- [问题反馈](https://github.com/tonyjianchina/ShelterBar/issues)
