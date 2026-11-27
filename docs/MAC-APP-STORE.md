# Mac App Store 就绪审计

结论：ShelterBar **现在不能提交** Mac App Store 审核。本分支没有给应用加上 App Sandbox，也没有登录 Apple 账号或上传构建。沙盒能否承载「把别人的菜单栏图标拖进收纳栏」仍是下一道门；在一台 Mac 上证明有可行路径之前，不要上传。

审计依据是仓库里 v0.5.14（`main`，`cc5a256`）的代码，以及 2026-11-27 仍有效的 Apple 文档。[App Store 审核指南](https://developer.apple.com/app-store/review/guidelines/) 标注的最近更新是 2026-10-16。[保护用户数据：App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) 写明，App Store 分发必须使用 App Sandbox，并列出沙盒中被系统禁止的行为。未合并的 [PR #4](https://github.com/tonyjianchina/ShelterBar/pull/4) 不在本分支上。

## 已经符合的部分

- 只做 Apple Silicon（`arm64`），最低系统 macOS 14。这和菜单栏工具的产品范围一致；macOS 27 起系统本身也不再支持 Intel Mac。
- `LSUIElement` 菜单栏应用可以没有 Dock 图标。类别按实用工具准备：`LSApplicationCategoryType` = `public.app-category.utilities`。
- 直接分发的构建脚本默认打开 Hardened Runtime（`SHELTERBAR_HARDENED_RUNTIME` 默认为 1）。
- 应用目标没有第三方运行时依赖。测试才使用 Swift Testing。
- 没有账号、广告或遥测 SDK。隐私清单声明不追踪、不收集数据；本应用只因读写自己的 `UserDefaults` 使用了需要理由的 API，理由是 `CA92.1`。
- 屏幕录制在代码里仍然是可选的。拒绝后收纳和恢复继续可用，只是显示占位图标。本次没有把它改成必需。
- 首次启动的第一次盘点会把当时已经在菜单栏上的图标记为已知项，因此不会把它们自动收进收纳栏。运行期间之后新出现的可移动图标，仍按现有 `.collect` 策略自动收纳。本分支没有改这条行为。
- 加密只用系统提供的 HTTPS 和 CryptoKit SHA-256。`ITSAppUsesNonExemptEncryption` 为 false。

## 不能提交的原因

指南 2.4.5 要求 Mac App Store 应用沙盒化，用 Xcode 提供的方式打包，并且只能通过 Mac App Store 更新。Apple 的沙盒文档把下面几件事列为沙盒里被禁止的行为：

- 在辅助类应用中使用辅助功能 API
- 向任意应用发送 Apple Event
- 在「打开」和「存储」对话框里模拟用户输入

同一页没有给出能覆盖「辅助功能操作其他应用」或「向其他进程注入键鼠事件」的常规临时例外授权。`com.apple.security.temporary-exception.apple-events` 只适用于点名的目标应用，而且 ShelterBar 的收纳路径并不发送 Apple Event。

当前核心路径正好落在这份限制里：

| 行为 | 代码 | 和沙盒文档的关系 |
| --- | --- | --- |
| 读取其他应用的菜单栏项，并执行 `AXPress` | `MenuBarAXPressExecutor.swift`、`AccessibilityPermission.swift` | 辅助类应用使用辅助功能 API。文档明确禁止。 |
| 全局事件钩子吞掉其他应用菜单栏图标上的鼠标按下、拖动和松开 | `MenuBarDragMonitor.swift` 使用 `CGEvent.tapCreate`，位置是 `.headInsertEventTap`，选项是 `.defaultTap`，回调返回 `nil` 即吞掉事件 | 这是跨应用的输入拦截，不是只监听自己的窗口。没有对应的常规沙盒授权。 |
| 向其他进程投递带 Command 的 HID 拖动，用来搬走它的菜单栏图标 | `MenuBarItemMover.swift` 的 `CGEvent.post(tap: .cghidEventTap)`，`MenuBarDragEvents.swift` 设置 `eventTargetUnixProcessID` | 这是对其他应用的输入模拟。文档点名的例子是打开/存储对话框；ShelterBar 做的是同一类跨应用模拟，目标是别人的菜单栏窗口。没有文档化的授权可以打开它。 |
| macOS 27 上通过私有框架隐藏其他应用的菜单栏图标 | `MenuBarAgentVisibility.swift` 在运行时 `dlopen` `/System/Library/PrivateFrameworks/MenuBarClientCore.framework`，再使用 `MBAssessmentModeAssertion` 和 `MBAssessmentModeConfiguration` | 指南 2.5.1 只允许公开 API。这条路径即使沙盒问题不存在也会被拒。README 写明 macOS 27 上传统 Command 拖动已经不可靠，所以删掉它会得到一个在目标系统上不完整的应用。 |

屏幕录制解决不了这个问题。它只给图标图像使用，而且必须继续保持可选。`CGWindowListCopyWindowInfo` 在较新的系统上会受屏幕录制权限影响，但收纳动作本身依赖的是辅助功能和合成拖动，不是截图。

因此这里没有、也不应该产出一个打开了 App Sandbox 的构建。`scripts/build-app.sh` 在 `SHELTERBAR_APP_SANDBOX=1` 或 `SHELTERBAR_ENABLE_APP_SANDBOX=1` 时直接退出，并在签名后拒绝任何已经带上 `com.apple.security.app-sandbox` 的产物。

下一道门是在一台真实的 Mac 上验证：是否存在一条**仍然能收纳、恢复、点开原菜单**的沙盒实现。以今天的官方文档和这份代码，现有实现过不了这道门。在那之前不要上传，也不要对外说已经提交审核。

若产品以后改成只使用自己的 `NSStatusItem`、让用户用系统自带的 Command 拖动排列图标，并且二进制里不再包含辅助功能控制其他应用、事件钩子、`CGEvent.post` 跨应用拖动和 `MenuBarClientCore`，那才是重新讨论沙盒的时候。那是另一种交互，不是本分支要做的事。

## 本分支做了什么

这些改动不改变直装版的收纳行为，也不给应用加沙盒。

1. **权限说明和商店元数据**写进 `Resources/Info.plist`。英文是开发区域的默认文案，简体中文在 `zh-Hans.lproj/InfoPlist.strings`。屏幕录制的说明写明它是可选的。输入监控没有单独的 Usage Description 键；系统对话框不使用 Info.plist 文案，应用里原有的引导文案仍然负责说明用途。
2. **隐私清单** `Resources/PrivacyInfo.xcprivacy` 会打进应用包。不追踪，收集的数据类型为空，`UserDefaults` 的理由是 `CA92.1`（只读写本应用自己的信息）。
3. **中英隐私政策页**在 `website/dist/privacy/index.html`。首页页脚加了链接。应用「更多」菜单的「隐私政策」打开 `https://shelterbar.tonyjianchina.chatgpt.site/privacy`。指南 5.1.1 要求 App Store Connect 和应用程序内都有这个链接。
4. **App Store 编译开关**会从二进制里去掉 GitHub 更新器。直装打包脚本拒绝这个开关，所以 GitHub 的 DMG/ZIP 仍保留更新器。

这个开关**不是**可上传的商店包。它只满足指南 2.4.5(iv) 和 2.4.5(vii)：商店版本不能再自带下载并替换 `.app` 的更新器。私有 API 和跨应用拖动都还在。

```sh
SHELTERBAR_DISTRIBUTION=app-store ./scripts/build-app.sh release
```

`./scripts/package-release.sh` 只构建直装版。更新器feed、下载、校验和 `/bin/sh` 替换脚本都包在 `#if !SHELTERBAR_APP_STORE` 里。商店风味的构建还会检查二进制中不再出现 `api.github.com/repos/tonyjianchina/ShelterBar/releases`。

## 隐私政策地址还没有生效

2026-11-27 检查时，下面两个地址返回的仍是营销首页，不是隐私政策：

- `https://shelterbar.tonyjianchina.chatgpt.site/privacy`
- `https://shelterbar.zhengjian.me/privacy`

仓库里的页面还没有部署。部署必须由维护者来做，并且要确认主机是按文件提供 `privacy/index.html`，而不是把所有未知路径都回退到首页。在那之前，应用里的「隐私政策」会打开到现在的首页。不要把当前线上的 `/privacy` 填进 App Store Connect。

## 若沙盒路径以后被证明可行，商店侧还要做的事

这些步骤都要维护者在自己的 Mac 上、用已加入 Apple Developer Program 的账号和双重认证完成。这台云主机做不了。

### 签名与打包

- 在开发者账号里注册 App ID `com.jensen.shelterbar`（Mac App Store）。不要换 bundle ID，除非决定和直装版彻底分开。
- 创建 **Apple Distribution** 证书，以及用来签安装包的 **Mac Installer Distribution**（或当前账号里对应的安装包证书）。
- 创建包含 App Sandbox 的 Mac App Store 描述文件。描述文件会带上 `com.apple.application-identifier` 和 `com.apple.developer.team-identifier`。
- 用 Xcode 或 Transporter 接受的方式打出 `.pkg`。现在的 SwiftPM 脚本加自签名，不符合指南 2.4.5(ii)。
- 直装版的 designated requirement 钉的是自签名证书。换成 Apple Distribution 之后，已有用户的辅助功能授权不会自动沿用。

### App Store Connect 清单

- 新建 macOS App，主语言简体中文，并添加英文本地化。名称 ShelterBar。副标题可以用现有口号「给菜单栏，留一点空白」/ “A little room for the menu bar”。主类别 Utilities。
- 价格：免费（USD 0）。这会让包括中国大陆在内的所有店面都是 0 元。
- 销售范围：**所有国家和地区**（All Countries or Regions），从而包含中国大陆、港澳台和欧盟。
- 隐私政策 URL：部署完成并确认不再是首页之后，填 `https://shelterbar.tonyjianchina.chatgpt.site/privacy`。支持 URL 可用官网或 GitHub Issues。
- App 隐私问卷：不收集数据。不要勾选追踪。
- 出口合规：应用只使用系统 HTTPS 和 SHA-256，Info.plist 已声明非豁免加密为 false。若 Connect 仍追问，按「仅使用操作系统提供的加密」回答。
- 年龄分级按实用工具填写。应用没有不受限制的网页浏览。
- 人工智能 / 安全相关声明：ShelterBar 没有生成式模型、Apple Intelligence 或自动化决策。若问卷仍是当前这种是非题，回答 **否**。
- 欧盟《数字服务法》交易者身份：因为销售范围包含全部欧盟店面，Connect 会要求账号持有人完成交易者声明。本仓库不能判断维护者是否属于「交易者」。这是账号持有人在双重认证后填写的事项。
- 中国大陆：本应用是本地实用工具。Apple 的 App 信息说明只要求「部分 App」提供 ICP 备案号，并没有把每一款本地工具都列为必须备案。软件著作权也不是 Apple 提交 Mac App Store 的条件。按 Connect 里中国大陆供应情况表单的原文填写；不要为了提交去额外办理一份仓库无法证明的许可。游戏、新闻、出版、宗教类证件与本应用无关。
- 截图：至少准备一张真实的 Mac 截图，尺寸用 Connect 当时接受的 16:10（常见为 1280×800、1440×900、2560×1600 或 2880×1800）。这台 Linux 云主机截不到菜单栏，不要用网页示意图冒充。
- 审核备注要写清：辅助功能和输入监控用来收纳用户拖入的图标；屏幕录制可选，只读取单个图标；首次打开不会自动收纳全部图标。在沙盒实现存在之前，这些备注也不能让当前二进制过审。

### 这台云主机明确做不到的事

- 创建或下载证书、描述文件、双重认证。
- 登录 App Store Connect 或 Transporter。
- 在 macOS 上编译、签名、跑 `swift test`，或实际验证沙盒里的拖动。
- 部署 `shelterbar.zhengjian.me` 或 `shelterbar.tonyjianchina.chatgpt.site`。
- 代替维护者完成 DSA 交易者声明或中国大陆表单。
