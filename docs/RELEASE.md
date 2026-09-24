# ShelterBar v0.2.0 预览版

支持 **Apple Silicon（M1 及更新芯片）和 macOS 26.0 及以上**。当前下载包没有 Intel 版本。

这是采用 ad-hoc 临时签名的预览版，**尚无 Developer ID 签名，也未经过 Apple 公证**。签名验证仅用于检查应用包的内部完整性，并不代表 Apple 已验证开发者身份或批准此应用。

## 下载与安装

从 [GitHub Releases v0.2.0](https://github.com/tonyjianchina/ShelterBar/releases/tag/v0.2.0) 下载 [ShelterBar-0.2.0-macos-arm64.dmg](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.2.0/ShelterBar-0.2.0-macos-arm64.dmg)，打开后将 **ShelterBar.app** 拖入 **Applications**，随后推出磁盘映像。也可下载 [ZIP](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.2.0/ShelterBar-0.2.0-macos-arm64.zip)，解压后将应用移到“应用程序”文件夹。

首次打开时，如果 macOS 提示无法验证开发者或无法检查恶意软件，在确认下载来源及 SHA256 校验值后，可进入 **系统设置 → 隐私与安全性 → 仍要打开**，再确认“打开”。先尝试打开应用，系统才可能显示这个按钮。受管理设备可能不提供该选项；不要关闭 Gatekeeper 或移除系统安全策略。

这套说明依据 [Apple：在 Mac 上安全地打开 App](https://support.apple.com/zh-cn/102445)。若系统提示应用已损坏或包含恶意软件，请停止打开，重新核对下载和问题原因。

启动后需要两项权限：

- **辅助功能**：在“系统设置 → 隐私与安全性 → 辅助功能”中允许 ShelterBar，用于发现和移动菜单栏图标。
- **屏幕录制**：用于读取原始菜单栏状态图标。点击应用内的 **“允许读取图标”**，或通过 **“打开设置”** 前往系统设置授权；授权后可能需要退出并重新打开 ShelterBar。

它是菜单栏应用，不显示 Dock 图标。升级预览版后，可能需要重新授权。

打开收纳栏后，将可移动的菜单栏图标拖入其中即可收纳；拖回顶部菜单栏可恢复。部分系统图标及无法通过辅助功能访问的图标不可管理。原始图标捕获及原生第三方图标移动的完整兼容性，仍待授予权限后的真实会话验证；第三方应用、显示器配置和 macOS 差异不能仅由自动化测试确认。

## v0.2.0 原始状态图标

收纳栏通过 ScreenCaptureKit 截取原始菜单栏状态图标。只有进程 PID、状态窗口及辅助功能（AX）范围严格匹配时，才捕获该单个状态图标；截图仅缓存在内存中。应用不采集音频、不录制视频、不把截图写入磁盘，也不上传截图。

单色 glyph 随收纳栏外观配色；彩色及多灰度状态图标保留原色，均保持原始比例。图标可见时捕获，收纳栏打开时尝试更新隐藏图标；收纳栏关闭时，定时任务不会截图。刷新失败会保留上次成功的图像，因此某些状态变化可能暂时显示旧图像，并非每次变化都能立即更新。

首次捕获没有可用图像时，应用会展开恢复真实菜单栏项目，不会把它们隐藏后留出空白。无法严格匹配的窗口不会被当作图标截取。授权与兼容性验证步骤见 [MVP 验收清单](MVP.md)。

## 核对下载

将两个安装包及 [SHA256SUMS](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.2.0/SHA256SUMS) 下载到同一个文件夹，在该文件夹运行：

```sh
shasum -a 256 -c SHA256SUMS
```

如只下载了 DMG，运行以下命令，将结果与 `SHA256SUMS` 中该文件的一行比较：

```sh
shasum -a 256 ShelterBar-0.2.0-macos-arm64.dmg
```

## 从源码构建与打包

需要 macOS 26 或更新系统，以及支持 macOS 26 SDK 的 Xcode / Command Line Tools（Swift 6.2 或更新版本）。当前发布构建在 Apple Silicon 上验证；Intel 主机上的交叉构建未经验证。首次构建需要联网下载 `Package.resolved` 中锁定的 Swift Testing / Swift Syntax 依赖。

在仓库根目录运行：

```sh
swift test --force-resolved-versions
./scripts/package-release.sh
```

脚本会显式构建 `arm64-apple-macosx26.0` 的 Release 可执行文件，读取 `Resources/Info.plist` 的版本，验证 plist 和架构，使用 ad-hoc 签名封装应用，并输出：

```text
dist/ShelterBar.app
dist/releases/v0.2.0/ShelterBar-0.2.0-macos-arm64.dmg
dist/releases/v0.2.0/ShelterBar-0.2.0-macos-arm64.zip
dist/releases/v0.2.0/SHA256SUMS
```

DMG 包含应用、指向 `/Applications` 的快捷方式和中英双语安装说明。脚本校验 DMG 内部校验和、只读挂载后的内容、ZIP 解压后的内容、两份应用的签名以及最终 SHA256 校验值。生成的挂载点和临时文件会在完成后清理。

可以只构建应用：

```sh
./scripts/build-app.sh release
```

默认 `./scripts/build-app.sh` 仍构建 Debug 版本。构建使用锁定依赖，不自动更新 `Package.resolved`。这提供可重复的发布流程；不同 Swift / SDK 版本、构建路径与归档时间戳仍可能改变产物字节，因此不承诺跨机器逐字节一致。

## 发布检查

- 将 `v0.2.0` 标记为 **Pre-release**，公开说明系统要求、两项权限、未公证状态和已知限制。
- 上传经过校验的 DMG、ZIP 和 `SHA256SUMS` 三个文件。
- 核对公开下载地址、资产文件名、下载后的 SHA256，以及官网指向相同版本的链接。
- 自动化测试与归档校验不等于授权后的原始图标捕获与第三方移动兼容性测试；未完成真实会话验收前，不应宣称完整兼容性已验证。
- 后续正式版需要有效的 Developer ID Application 签名、Apple 公证与公证票据装订，再重新生成安装包和 SHA256；不要把临时签名版本描述为已公证。

没有添加未经实际验证的 GitHub Actions 发布工作流。当前发布流程是在上述 macOS 环境下本地构建、校验后上传。
