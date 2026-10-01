# ShelterBar v0.5.4 预览版

支持 **Apple Silicon（M1 及更新芯片）和 macOS 26.0 及以上**。当前下载包没有 Intel 版本。

这是采用 ad-hoc 临时签名的预览版，**尚无 Developer ID 签名，也未经过 Apple 公证**。签名验证仅用于检查应用包的内部完整性，并不代表 Apple 已验证开发者身份或批准此应用。

## 下载与安装

从 [GitHub Releases v0.5.4](https://github.com/tonyjianchina/ShelterBar/releases/tag/v0.5.4) 下载 [ShelterBar-0.5.4-macos-arm64.dmg](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.4/ShelterBar-0.5.4-macos-arm64.dmg)。打开后会看到图形化安装窗口，将左侧 **ShelterBar** 拖到右侧 **Applications** 文件夹即可安装，随后推出磁盘映像。也可下载 [ZIP](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.4/ShelterBar-0.5.4-macos-arm64.zip)，解压后将应用移到“应用程序”文件夹。

首次打开时，如果 macOS 提示无法验证开发者或无法检查恶意软件，在确认下载来源及 SHA256 校验值后，可进入 **系统设置 → 隐私与安全性 → 仍要打开**，再确认“打开”。先尝试打开应用，系统才可能显示这个按钮。受管理设备可能不提供该选项；不要关闭 Gatekeeper 或移除系统安全策略。

这套说明依据 [Apple：在 Mac 上安全地打开 App](https://support.apple.com/zh-cn/102445)。若系统提示应用已损坏或包含恶意软件，请停止打开，重新核对下载和问题原因。

启动后应用会依次引导两项权限：

- **辅助功能**：首先询问；在“系统设置 → 隐私与安全性 → 辅助功能”中允许 ShelterBar，用于发现和移动菜单栏图标。
- **屏幕录制（可选）**：应用检测到辅助功能已授权后会立即继续询问，用于读取原始菜单栏状态图标。拒绝或稍后授权时，收纳与恢复仍可用，收纳栏使用占位图标。

它是菜单栏应用，不显示 Dock 图标。升级预览版后，可能需要重新授权。

打开收纳栏后，将可移动的菜单栏图标拖入其中即可收纳；拖回顶部菜单栏可恢复。部分系统图标及无法通过辅助功能访问的图标不可管理。本版已完成下述本机真实拖动检查，但原始图标捕获及移动的完整兼容性仍须针对具体第三方应用、显示器配置和 macOS 版本验证，不能仅由自动化测试确认。

## v0.5.4（build 19）修复内容

菜单栏中的可见入口现在使用独立的固定宽度状态项，不再与收起用的宽占位项共用。收起前会检查入口处于安全区域和边界的常驻一侧；如果无法保留入口，则保持展开且不保存此次收纳结果。

浅色收纳栏中的白色、灰阶图标现在会提高对比度，深色外观也有对应适配；保留灰阶细节、透明度和彩色小标记，彩色为主的图标保持原色。96 项自动化测试通过；本机原生面板截图确认 Shadowrocket、Muse、ChatGPT 在浅色背景下可辨认。这不替代顶部入口实际可见性或完整交互验收。完整变更见 [发布说明](releases/v0.5.4.md)。

macOS 26 合成显示菜单栏时，实际托管图标的控制中心窗口可能不在“仅可见窗口”列表中。本版改为从完整窗口列表中按实时辅助功能坐标、进程和窗口层级严格匹配，修复尚未发出拖动就报“无法安全整理当前菜单栏”的问题。

连续移动时，辅助功能坐标可能比原生窗口动画提前更新。本版等待两者匹配后再处理下一项；未参与操作的失效辅助功能条目不再造成整体校验失败，也不会被误认为已经收纳。每个实际参与整理的图标仍必须通过位置验证。

收纳箱靠近刘海、左侧没有空间时，应用会先将自身边界移到目标图标右侧，再恢复其他常驻图标并收起。所有实际拖动仍检查完整目标窗口与刘海的交集。

本机实测通过 Shadowrocket、Chrome、网易邮箱大师的“拖入收纳栏 → 后台轮询 → 拖回顶部”，并验证重启恢复、重复刷新和失效飞书辅助功能条目不会干扰收纳。自动化和实机检查的复现命令保存在 `Tools/Diagnostics/`；这不等于所有 macOS、显示器和第三方应用的兼容性保证。

v0.5.2 引入的两项权限串联引导保持不变：先请求辅助功能，检测到授权后立即且只请求一次可选的屏幕录制权限。v0.5.1 的图形化拖拽安装盘继续沿用。

统一收纳引擎继续串行处理扫描、原生移动、位置验证、恢复和图标刷新，并自动收纳运行期间新出现的可移动菜单栏项。对外预览包继续使用 ad-hoc 签名。

收纳栏通过 ScreenCaptureKit 截取原始菜单栏状态图标。只有进程 PID、状态窗口及辅助功能（AX）范围严格匹配时，才捕获该单个状态图标；截图仅缓存在内存中。应用不采集音频、不录制视频、不把截图写入磁盘，也不上传截图。

单色及中性灰阶图标随收纳栏外观调整对比度，保留灰阶细节、透明度和彩色标记；彩色为主的图标保持原色，均保持原始比例。图标可见时捕获，收纳栏打开时尝试更新隐藏图标；收纳栏关闭时，定时任务不会截图。刷新失败会保留上次成功的图像，因此某些状态变化可能暂时显示旧图像，并非每次变化都能立即更新。

没有可用捕获时，收纳栏使用占位图标，不会展开菜单栏或中断收纳。无法严格匹配的窗口不会被当作图标截取。授权与兼容性验证步骤见 [MVP 验收清单](MVP.md)。

## 核对下载

将两个安装包及 [SHA256SUMS](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.4/SHA256SUMS) 下载到同一个文件夹，在该文件夹运行：

```sh
shasum -a 256 -c SHA256SUMS
```

如只下载了 DMG，运行以下命令，将结果与 `SHA256SUMS` 中该文件的一行比较：

```sh
shasum -a 256 ShelterBar-0.5.4-macos-arm64.dmg
```

## 从源码构建与打包

需要 macOS 26 或更新系统，以及支持 macOS 26 SDK 的 Xcode / Command Line Tools（Swift 6.2 或更新版本）。DMG 布局工具需要 Python 3.10 或更新版本。当前发布构建在 Apple Silicon 上验证；Intel 主机上的交叉构建未经验证。首次构建需要联网下载 `Package.resolved` 中锁定的 Swift Testing / Swift Syntax 依赖。

在仓库根目录运行：

```sh
swift test --force-resolved-versions
python3.11 -m venv .build/dmg-tools
.build/dmg-tools/bin/pip install -r scripts/dmg-requirements.txt
./scripts/package-release.sh
```

脚本会显式构建 `arm64-apple-macosx26.0` 的 Release 可执行文件，读取 `Resources/Info.plist` 的版本，验证 plist 和架构，使用 ad-hoc 签名封装应用，并输出：

```text
dist/ShelterBar.app
dist/releases/v0.5.4/ShelterBar-0.5.4-macos-arm64.dmg
dist/releases/v0.5.4/ShelterBar-0.5.4-macos-arm64.zip
dist/releases/v0.5.4/SHA256SUMS
```

DMG 包含应用、指向 `/Applications` 的快捷方式、品牌背景、固定 Finder 图标布局和隐藏的中英双语安装说明。布局直接写入磁盘元数据，不需要控制 Finder、安装或启动应用。脚本校验 DMG 内部校验和、只读挂载后的图标位置和背景引用、ZIP 解压后的内容、两份应用的签名以及最终 SHA256 校验值。生成的挂载点和临时文件会在完成后清理。可通过 `SHELTERBAR_DMG_PYTHON` 指定已安装这两个锁定依赖的 Python 解释器。

可以只构建应用：

```sh
./scripts/setup-local-signing.sh
./scripts/build-app.sh release
```

首个命令只需在本机执行一次：它会在登录钥匙串中创建专用的本地代码签名身份，使后续本地构建保持稳定的 designated requirement，从而保留辅助功能和屏幕录制授权。这个自签名身份仅用于本机开发，不可对外分发。`package-release.sh` 默认仍使用 ad-hoc 签名；正式发布时应通过 `SHELTERBAR_RELEASE_CODESIGN_IDENTITY` 指定 Developer ID Application 身份。

默认 `./scripts/build-app.sh` 仍构建 Debug 版本。构建使用锁定依赖，不自动更新 `Package.resolved`。这提供可重复的发布流程；不同 Swift / SDK 版本、构建路径与归档时间戳仍可能改变产物字节，因此不承诺跨机器逐字节一致。

## 发布检查

- 将 `v0.5.4` 标记为 **Pre-release**，公开说明系统要求、辅助功能必需、屏幕录制可选、未公证状态和已知限制。
- 上传经过校验的 DMG、ZIP 和 `SHA256SUMS` 三个文件。
- 核对公开下载地址、资产文件名、下载后的 SHA256，以及官网指向相同版本的链接。
- 自动化测试与归档校验不等于授权后的原始图标捕获与第三方移动兼容性测试；未完成真实会话验收前，不应宣称完整兼容性已验证。
- 后续正式版需要有效的 Developer ID Application 签名、Apple 公证与公证票据装订，再重新生成安装包和 SHA256；不要把临时签名版本描述为已公证。

没有添加未经实际验证的 GitHub Actions 发布工作流。当前发布流程是在上述 macOS 环境下本地构建、校验后上传。
