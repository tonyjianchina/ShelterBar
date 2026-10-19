# ShelterBar v0.5.8 预览版

支持 **Apple Silicon（M1 及更新芯片）和 macOS 26.0 及以上**。当前下载包没有 Intel 版本。

自 v0.5.7（build 22）起，预览版使用固定的自签名证书 **“ShelterBar Self-Signed”** 签名，不再使用 ad-hoc 临时签名；但仍 **没有 Developer ID 签名，也未经过 Apple 公证**。签名验证仅用于检查应用包的完整性和保持稳定的 designated requirement，并不代表 Apple 已验证开发者身份或批准此应用。

## 下载与安装

从 [GitHub Releases v0.5.8](https://github.com/tonyjianchina/ShelterBar/releases/tag/v0.5.8) 下载 [ShelterBar-0.5.8-macos-arm64.dmg](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.8/ShelterBar-0.5.8-macos-arm64.dmg)。打开后会看到图形化安装窗口。也可下载 [ZIP](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.8/ShelterBar-0.5.8-macos-arm64.zip)，解压后将应用移到“应用程序”文件夹。

### 安装与第一次打开

1. **安装**：打开 DMG，把 ShelterBar 拖进「应用程序」（Applications）文件夹，然后推出磁盘。
2. **第一次打开**：在访达的「应用程序」文件夹里双击 ShelterBar（刚安装时，聚焦搜索可能要过几分钟才能搜到）。ShelterBar 没有经过 Apple 公证，系统会拦下并提示无法验证，先点「完成」关闭提示；然后打开「系统设置 → 隐私与安全性」，往下滚到「安全性」部分，点 ShelterBar 旁边的「仍要打开」，再确认一次「打开」（可能需要输入登录密码）。macOS 15 起，右键「打开」已不能绕过这一步。
   - 高级用户也可以在核对 SHA256 后，在终端运行 `xattr -dr com.apple.quarantine /Applications/ShelterBar.app`，再双击打开。
   - 每次下载只需放行一次。以后下载新版本覆盖安装时，如果系统再次拦下，按同样步骤放行即可；辅助功能等授权会保留，不用重新授权（从 v0.5.6 及更早版本升级除外，需重新授权一次）。
3. **打开之后**：ShelterBar 只在菜单栏运行，没有 Dock 图标，也没有普通窗口——请留意屏幕右上角菜单栏里新出现的收纳箱图标，点它即可展开收纳栏。首次启动时，收纳栏会自动在图标下方展开，并按引导请求授权：先是「辅助功能」和「输入监控」（必需），辅助功能生效后再请求「屏幕录制」（可选，只用于显示原始图标）。

先尝试打开一次应用，「隐私与安全性」里才会出现「仍要打开」按钮。请先确认下载来源及 SHA256 校验值；受管理设备可能不提供该选项；不要关闭 Gatekeeper 或全局关闭系统安全策略。

这套说明依据 [Apple：在 Mac 上安全地打开 App](https://support.apple.com/zh-cn/102445)。若系统提示应用已损坏或包含恶意软件，请停止打开，重新核对下载和问题原因。

权限引导的细节：

- **辅助功能与输入监控**：首先询问；在“系统设置 → 隐私与安全性”中允许 ShelterBar，用于发现、拦截拖动并移动菜单栏图标。缺少任何一项都不会开始拦截鼠标。
- **屏幕录制（可选）**：辅助功能一生效就立即继续询问（不再等待输入监控全部生效），用于读取原始菜单栏状态图标。拒绝或稍后授权时，收纳与恢复仍可用，收纳栏使用占位图标。


**从 v0.5.6 及更早版本升级：** 旧版本是 ad-hoc 签名，签名身份变化后需要重新授予一次辅助功能、输入监控和屏幕录制（列表里已有旧条目时，先关闭再打开，或移除后重新添加）。之后用同一证书签名的版本会保留这些授权。

打开收纳栏后，将可移动的菜单栏图标拖入其中即可收纳；拖回顶部菜单栏可恢复。部分系统图标及无法通过辅助功能访问的图标不可管理。本版已完成下述本机真实拖动检查，但原始图标捕获及移动的完整兼容性仍须针对具体第三方应用、显示器配置和 macOS 版本验证，不能仅由自动化测试确认。

## v0.5.8（build 23）更新内容

v0.5.8 取代从未正式发布的 v0.5.7 草稿，应用功能与 v0.5.7 相同：安装盘背景新增“首次打开请到「隐私与安全性」点「仍要打开」”提示，安装盘 INSTALL.txt、README、官网和发布说明补充了第一次打开的放行步骤。完整说明见 [v0.5.8 发布说明](releases/v0.5.8.md)。

## v0.5.7（build 22）更新内容（未单独发布，并入 v0.5.8）

- 固定自签名证书签名，后续升级保留权限（从 ad-hoc 版本升级需重新授权一次）。
- 修复白色/浅色彩色图标在收纳栏中看不清的问题。
- 修复全屏应用和自动隐藏菜单栏下无法收纳的问题；单个图标失败不再展开全部图标；处理刘海区域。
- 点击收纳栏图标时，只把该图标临时放到收纳栏正下方并打开它的菜单，菜单关闭后自动收回；光标复位、宽限期以及崩溃后的自动恢复。
- 已收纳图标缓存到磁盘，重启后不再显示“?”。
- 辅助功能授权后立即询问屏幕录制。

完整说明见 [v0.5.7 发布说明](releases/v0.5.7.md)。
## v0.5.6（build 21）修复保留

修复点击“授予输入权限”后没有反馈的问题。macOS 不再弹出授权框且权限仍未开通时，应用会打开对应的系统权限设置页，并在收纳栏显示操作提示；系统设置打开失败时显示手动授权说明。重复点击按钮仍然有效，后台轮询不会反复打开设置。已经完整授权时不再请求。

v0.5.6 时 107 项自动化测试通过；本机验证了启动和按钮点击后进入辅助功能设置、收纳栏提示可见。未替用户切换隐私开关，不将导航验证等同于完整授权验收。完整变更见 [发布说明](releases/v0.5.6.md)。

## v0.5.5（build 20）安全修复保留

修复权限切换、重装或临时签名更新后，macOS 可能仍报告辅助功能可用，但输入监听或事件发送已经失效，导致 ShelterBar 吞掉鼠标按下而无法完成合成手势的问题。该状态会表现为鼠标仍能移动，但整个系统无法点击或切换窗口。

ShelterBar 把辅助功能、输入监听和事件发送作为一个不可分割的权限门：缺少任意一项时不安装事件拦截；运行中权限失效时立即取消手势并放行后续物理事件；系统禁用 Event Tap 后，也只有权限恢复完整才会重新启用。v0.5.5 的 99 项自动化测试全部通过，新增覆盖启动时缺权和拖动中撤权两种情况。历史变更见 [发布说明](releases/v0.5.5.md)。

## v0.5.4 功能延续

菜单栏中的可见入口现在使用独立的固定宽度状态项，不再与收起用的宽占位项共用。收起前会检查入口处于安全区域和边界的常驻一侧；如果无法保留入口，则保持展开且不保存此次收纳结果。

浅色收纳栏中的白色、灰阶图标现在会提高对比度，深色外观也有对应适配；保留灰阶细节、透明度和彩色小标记，彩色为主的图标保持原色。本机原生面板截图确认 Shadowrocket、Muse、ChatGPT 在浅色背景下可辨认。这不替代顶部入口实际可见性或完整交互验收。

macOS 26 合成显示菜单栏时，实际托管图标的控制中心窗口可能不在“仅可见窗口”列表中。本版改为从完整窗口列表中按实时辅助功能坐标、进程和窗口层级严格匹配，修复尚未发出拖动就报“无法安全整理当前菜单栏”的问题。

连续移动时，辅助功能坐标可能比原生窗口动画提前更新。本版等待两者匹配后再处理下一项；未参与操作的失效辅助功能条目不再造成整体校验失败，也不会被误认为已经收纳。每个实际参与整理的图标仍必须通过位置验证。

收纳箱靠近刘海、左侧没有空间时，应用会先将自身边界移到目标图标右侧，再恢复其他常驻图标并收起。所有实际拖动仍检查完整目标窗口与刘海的交集。

本机实测通过 Shadowrocket、Chrome、网易邮箱大师的“拖入收纳栏 → 后台轮询 → 拖回顶部”，并验证重启恢复、重复刷新和失效飞书辅助功能条目不会干扰收纳。自动化和实机检查的复现命令保存在 `Tools/Diagnostics/`；这不等于所有 macOS、显示器和第三方应用的兼容性保证。

v0.5.4–v0.5.6 的权限引导会等待辅助功能和输入监控全部生效后才询问屏幕录制；v0.5.7 起改为辅助功能生效后立即询问（拖动拦截仍要求三项输入权限齐全）。v0.5.1 的图形化拖拽安装盘继续沿用。

统一收纳引擎继续串行处理扫描、原生移动、位置验证、恢复和图标刷新，并自动收纳运行期间新出现的可移动菜单栏项。对外预览包使用“ShelterBar Self-Signed”固定证书签名。

收纳栏通过 ScreenCaptureKit 截取原始菜单栏状态图标。只有进程 PID、状态窗口及辅助功能（AX）范围严格匹配时，才捕获该单个状态图标。只有**已收纳**图标的小尺寸 PNG 会写入本机 `~/Library/Application Support/ShelterBar/IconCache/`（用于重启后显示），图标移回菜单栏后即删除对应缓存；应用不采集音频、不录制视频、不保存整屏截图，也不上传任何图像。

单色及中性灰阶图标随收纳栏外观调整对比度，保留灰阶细节、透明度和彩色标记；彩色为主的图标保持原色，均保持原始比例。图标可见时捕获，收纳栏打开时尝试更新隐藏图标；收纳栏关闭时，定时任务不会截图。刷新失败会保留上次成功的图像，因此某些状态变化可能暂时显示旧图像，并非每次变化都能立即更新。

没有可用捕获时，收纳栏使用占位图标，不会展开菜单栏或中断收纳。无法严格匹配的窗口不会被当作图标截取。授权与兼容性验证步骤见 [MVP 验收清单](MVP.md)。

## 核对下载

将两个安装包及 [SHA256SUMS](https://github.com/tonyjianchina/ShelterBar/releases/download/v0.5.8/SHA256SUMS) 下载到同一个文件夹，在该文件夹运行：

```sh
shasum -a 256 -c SHA256SUMS
```

如只下载了 DMG，运行以下命令，将结果与 `SHA256SUMS` 中该文件的一行比较：

```sh
shasum -a 256 ShelterBar-0.5.8-macos-arm64.dmg
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

脚本会显式构建 `arm64-apple-macosx14.0` 的 Release 可执行文件，读取 `Resources/Info.plist` 的版本，验证 plist 和架构，使用“ShelterBar Self-Signed”证书签名封装应用（钥匙串中找不到该身份时拒绝打包），并输出：

```text
dist/ShelterBar.app
dist/releases/v0.5.8/ShelterBar-0.5.8-macos-arm64.dmg
dist/releases/v0.5.8/ShelterBar-0.5.8-macos-arm64.zip
dist/releases/v0.5.8/SHA256SUMS
```

DMG 包含应用、指向 `/Applications` 的快捷方式、品牌背景、固定 Finder 图标布局和隐藏的中英双语安装说明。布局直接写入磁盘元数据，不需要控制 Finder、安装或启动应用。脚本校验 DMG 内部校验和、只读挂载后的图标位置和背景引用、ZIP 解压后的内容、两份应用的签名以及最终 SHA256 校验值。生成的挂载点和临时文件会在完成后清理。可通过 `SHELTERBAR_DMG_PYTHON` 指定已安装这两个锁定依赖的 Python 解释器。

可以只构建应用：

```sh
./scripts/setup-local-signing.sh
./scripts/build-app.sh release
```

`setup-local-signing.sh` 只用于没有发布证书的开发机：它创建“ShelterBar Local Code Signing”本地身份，不可对外分发。维护者本机应直接使用发布证书构建：

```sh
SHELTERBAR_CODESIGN_IDENTITY="ShelterBar Self-Signed" ./scripts/build-app.sh release
codesign -d -r- dist/ShelterBar.app
```

## 维护者：签名证书与开关

- 证书：**ShelterBar Self-Signed**，SHA-1 `ABCD7A5B7B4FF47F6E6448FAB665FAF8F0C5F910`，有效期至 2036-10-14。私钥只保存在维护者的登录钥匙串中，**切勿提交到 git**。
- 备份与恢复：`~/Documents/ShelterBar-Signing-Backup/` 中有 `.p12`（证书+私钥）、`.cer.pem`（公钥证书）和 `README.txt`。按 README 用 `security import … -T /usr/bin/codesign` 导入，可选 `security add-trusted-cert` 设置信任，再用 `security find-identity -p codesigning` 确认。`.p12` 密码保存在登录钥匙串中；请把整个文件夹另存到离线介质。私钥一旦丢失，DR 会改变，所有用户都要重新授权。
- 期望的 designated requirement：

  ```text
  identifier "com.jensen.shelterbar" and certificate leaf = H"abcd7a5b7b4ff47f6e6448fab665faf8f0c5f910"
  ```

- 开关：
  - `SHELTERBAR_RELEASE_CODESIGN_IDENTITY`：`package-release.sh` 使用的签名身份，默认 `ShelterBar Self-Signed`，找不到即退出；设为 `-` 会退回 ad-hoc，**不得用于公开发布**。
  - `SHELTERBAR_EXPECTED_DR`：设置后，打包脚本会比较实际 DR，不一致时中止。发布时务必设为上面的字符串。
  - `SHELTERBAR_HARDENED_RUNTIME`：默认 `1`，使用 hardened runtime 签名；设为 `0` 关闭。
  - `SHELTERBAR_CODESIGN_IDENTITY`：`build-app.sh` 使用的签名身份。

发布打包示例：

```sh
SHELTERBAR_EXPECTED_DR='identifier "com.jensen.shelterbar" and certificate leaf = H"abcd7a5b7b4ff47f6e6448fab665faf8f0c5f910"' \
  ./scripts/package-release.sh
```

默认 `./scripts/build-app.sh` 仍构建 Debug 版本。构建使用锁定依赖，不自动更新 `Package.resolved`。这提供可重复的发布流程；不同 Swift / SDK 版本、构建路径与归档时间戳仍可能改变产物字节，因此不承诺跨机器逐字节一致。

## 发布检查

- 将 `v0.5.8` 标记为 **Pre-release**，公开说明系统要求、辅助功能与输入监控必需、屏幕录制可选、自签名但未公证、从 ad-hoc 版本升级需重新授权一次，以及已知限制。
- 打包前确认 `codesign -d -r- dist/ShelterBar.app` 输出的 DR 与上面的期望值一致。
- 上传经过校验的 DMG、ZIP 和 `SHA256SUMS` 三个文件。
- 核对公开下载地址、资产文件名、下载后的 SHA256，以及官网指向相同版本的链接。
- 自动化测试与归档校验不等于授权后的原始图标捕获与第三方移动兼容性测试；未完成真实会话验收前，不应宣称完整兼容性已验证。
- 后续正式版需要有效的 Developer ID Application 签名、Apple 公证与公证票据装订，再重新生成安装包和 SHA256；不要把自签名版本描述为已公证。

没有添加未经实际验证的 GitHub Actions 发布工作流。当前发布流程是在上述 macOS 环境下本地构建、校验后上传。
