# ShelterBar 沙盒收纳可行性复核（2026-11-28）

**结论：本轮没有找到同时满足当前 macOS、App Sandbox、公开 API 和 ShelterBar 核心收纳的已记录路径。没有实现可用的沙盒后端，也没有解除 AppStore Build/Archive 的保护。** 这是本轮检索与源码核对所得的工程结论，不是对所有未来接口的“不可能”证明，也不是 Apple 给 ShelterBar 作出的审核决定。

续做 PR [#6](https://github.com/tonyjianchina/ShelterBar/pull/6)，分支 `codex/mac-app-store-packaging-20261128`，起点 `3b7385026ff5c7df49fb1f5696fdb66ae3dc3e21`。没有引入 PR #4，没有修改现有收纳、首次启动或更新器实现。本轮通过 ego-browser 重新读取在线资料，检查本机 SDK 和 System Events 字典，不把上一轮结论当作前提。

## 需要保住的行为

1. 首次安装保持已有图标可见；用户自己选择并拖入收纳。
2. 收纳第三方菜单栏图标，之后能够恢复。
3. 能打开原应用的菜单，而非只展示图标图片或启动应用。
4. 商店安装包自己提供核心功能，在当前系统可用；不依赖另装一个非沙盒助手。
5. 商店构建开启沙盒、没有 GitHub 更新器、没有私有 `MenuBarClientCore`。直装风味保留既有更新器。

## 新证据一：分隔状态项曾经成立，但当前系统已经破坏它

“只创建自己的 NSStatusItem，用户 Command 拖动排序，再增大分隔项长度”值得重新调查。这并非从未上架过的方案，也不能笼统说菜单栏收纳一概无法沙盒化。

[Hidden Bar 当前 App Store 页面](https://apps.apple.com/us/app/hidden-bar/id1452453066?mt=12)公开说明：商店版在 macOS 13–26 使用 Command 拖动分区、伸缩分隔项实现隐藏；在 macOS 27 上，商店沙盒版不能完成隐藏。页面显示版本 1.13.1，并建议 macOS 27 用户改用非商店直装版。这是开发者在 Apple 托管页面上的说明，不能冒充 Apple 的平台接口承诺。

进一步核对其公开源码，固定到提交 `496b64d28645ef6aaaff018b6612641ca860a137`，避免只凭商店宣传下判断：

- [MenuBarEngineFactory.swift](https://github.com/consolelabs/hidden/blob/496b64d28645ef6aaaff018b6612641ca860a137/hidden/Features/StatusBar/Engine/MenuBarEngineFactory.swift)：商店构建仍走旧长度引擎；直装构建才在 macOS 27 选择原生可见性实现。源码注释说明 macOS 27 会把过宽的分隔项移出布局。
- [LegacyLengthEngine.swift](https://github.com/consolelabs/hidden/blob/496b64d28645ef6aaaff018b6612641ca860a137/hidden/Features/StatusBar/Engine/LegacyLengthEngine.swift)：通过自身分隔项的长度切换展开/收起。设置长度成功或内部状态变成 collapsed，不等于其他图标真的隐藏。
- [架构说明](https://github.com/consolelabs/hidden/blob/496b64d28645ef6aaaff018b6612641ca860a137/docs/ARCHITECTURE.md)：明确区分商店沙盒版与直装版，以及 macOS 27 的限制。

**对 ShelterBar 的判断：**这可以解释旧系统上的商店先例，但不能交付本机 macOS 27.0.1 可用的核心。即使接受从收纳架改成“展开后手点原生图标”，当前系统的隐藏环节仍缺失；不能只把 `boundary.length` 写大就宣称完成。本轮没有运行分隔项实验、改变真实菜单栏布局或复现该产品的故障，以上是厂商说明及源码证据。

## 新证据二：确有公开的菜单栏限制接口，但它属于考试会话

不能继续使用“Apple 完全没有公开的第三方菜单栏限制 API”这种过宽说法。

macOS 27 的 [AEAssessmentConfiguration.allowedMenuBarItems](https://developer.apple.com/documentation/automaticassessmentconfiguration/aeassessmentconfiguration/allowedmenubaritems)是公开属性，可在考试会话允许显示菜单栏时指定可见项目。本机 SDK 的 `AEMenuBarItem.h` 还记录了以第三方 bundle identifier 指定项目的方式。

然而，[automatic-assessment-configuration entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.automatic-assessment-configuration)用于创建考试会话，使用前必须获得 Apple 授权。[WWDC26 介绍](https://developer.apple.com/videos/play/wwdc2026/230/)也将该框架用于教育考试环境。它没有把菜单栏限制单独开放成普通收纳工具的能力。

**对 ShelterBar 的判断：**ShelterBar 是日常菜单栏工具，当前没有考试业务、该 entitlement 的批准或 Apple 对此用途的支持说明。[指南 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)还要求按框架原定用途使用 API。不能借考试会话包装日常隐藏，也不能把真实存在的考试 entitlement 当作本产品已经获得的授权。本轮未申请 entitlement、未启动考试会话、未触发系统限制。

## Apple 的沙盒规则与真实 entitlement 边界

| 资料 | 核实到的内容 | 对本任务的含义 |
| --- | --- | --- |
| [审核指南 2.4.5(i)、(ii)、(iv)、(vii)、(viii)，2.5.1](https://developer.apple.com/app-store/review/guidelines/) | 商店应用需要沙盒、独立安装包、商店更新、当前系统可用及公开 API；不能下载额外独立应用补核心功能。 | 仅成功编译、旧版曾上架或另外下载助手，都不能单独满足本任务。 |
| [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) | 将辅助类应用使用辅助功能 API 列为不兼容功能；内嵌命令行工具须继承沙盒。 | 不能仅开启沙盒或要求用户勾选 TCC 就沿用现有 AX 链路；内嵌工具也不能作为逃逸后端。 |
| [DTS：Determining if an entitlement is real](https://developer.apple.com/forums/thread/799000) | `com.apple.security.accessibility` 不是真实 entitlement；TCC 与沙盒是不同约束。 | 不添加虚构的 AX entitlement。 |
| [DTS：跨应用窗口管理问答，2026-11-02](https://developer.apple.com/forums/thread/854711) | 对该窗口管理场景答复没有支持的沙盒路径；没有恢复 AX 的专用临时例外，用内部 Mach 服务名也不构成公开 API。 | 这是窗口管理答复，不能说它专门裁定了 ShelterBar；但它直接澄清了通用 AX/Mach 例外思路的问题。 |
| [App Sandbox Temporary Exception Entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html) | `apple-events` 指定接收应用；`mach-lookup.global-name` 只允许查找指定服务。其他文件、IOKit、偏好例外各有范围。 | 临时例外是真的，但其存在不授权任意跨应用 UI 控制，更不使内部服务协议变成公开 API。该参考页更新于 2017 年，需结合现行文档和近期 DTS 答复阅读。 |
| [App Store Connect：App Sandbox information](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information) | 使用临时例外须说明每个 key/value、用途、如何评估，缺失平台能力时附 Feedback ID。 | 这是已有真实例外的说明流程，不是通用 AX 豁免或审核保证。 |
| [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)及本机 SDK `NSStatusItem.h` / `NSStatusBar.h` | 创建自己的状态项、改变该对象的长度/可见性、管理自身展开界面；未给出控制任意第三方项目的接口。 | 新的 expanded-interface 会话也只管理所属项目的界面，不能替代第三方菜单调用。 |

注意：Apple 沙盒文章对输入模拟具体点名 Open/Save 对话框；它没有逐字断言所有 `CGEvent` 调用在所有沙盒场景都失败。本轮没有做 HID 注入实验，也不据此杜撰一个全局 HID entitlement。现有 AX 依赖和私有可见性后端已经足以阻止直接开启沙盒。

## System Events / AppleScript 是否能成为真正的新后端

这条路线需要调查，不能只因为当前 ShelterBar 没发 Apple Event 就排除新实现。

本机只读解析了 `/System/Library/CoreServices/System Events.app/Contents/Resources/SystemEvents.sdef`。其中命名的 `com.apple.systemevents.window.position` 权限组覆盖窗口集合读取和窗口 position/size；菜单栏、菜单栏项目、`click` 和 `perform` 没有对应的命名权限组。字典内磁盘 `move` 命令的 `*` 组也不是任意 UI 控制授权。

[DTS 对 System Events 的说明](https://developer.apple.com/forums/thread/125703?answerId=393709022#393709022)指出需检查目标脚本字典，且不能把 `NSUserScriptTask` 用作绕过沙盒的办法。该答复来自 2019 年，所以本轮另查当前系统字典，以及 [2026 年相关追问](https://developer.apple.com/forums/thread/854881)；不把旧问答或提问者自己的试验当作新授权。

**判断：**没有找到支持任意第三方状态项收纳/恢复/菜单调用的命名 scripting-target；临时指定 `com.apple.systemevents` 仍需具体操作与审核依据，不能据此宣称已获得整个链路。即便个别 click 可以在某种配置下运行，也没有解决当前系统上任意状态项的隐藏。用户脚本安装、脚本调用外部工具也不能充当商店包内自足核心。本轮没有发 Apple Event、运行 UI 脚本、请求 Automation 或修改辅助功能授权。

## 同类商店应用核查

| 产品与当前页面 | 核实到的事实 | 未证明的内容 |
| --- | --- | --- |
| [Hidden Bar](https://apps.apple.com/us/app/hidden-bar/id1452453066?mt=12)，页面版本 1.13.1 | 开发者明确承认商店版在 macOS 27 不能隐藏；旧系统使用分隔项，直装版采用不同后端。另有公开源码可核对。 | 它的上架不证明 ShelterBar 当前系统核心可用，也不保证其直装实现适合商店。 |
| [Barbee](https://apps.apple.com/us/app/barbee-hide-menu-bar-items/id1548711022?mt=12)，页面版本 5.0 | 商店页面宣传收纳、自定义间距等功能；读取了其公开反馈仓库和 Wiki。 | 未找到开发者公开的当前系统完整后端、entitlement 或 Apple 审批说明。用户评论中提到 helper，不能代替安装包和签名证据。未下载安装或付费。 |
| [iBar](https://apps.apple.com/us/app/ibar-menubar-icon-control-tool/id6443843900)，页面版本 2.1.1 | 页面宣传普通折叠、聚合窗口、临时移回菜单栏后打开原菜单等功能。 | 页面未给出 macOS 27 的受支持沙盒实现或特许 entitlement；宣传与历史评价不能证明完整链路。未下载安装或付费。 |

不能从“同类 App 在商店里”推导它没有助手、没有私有 API、当前系统能用或 Apple 会批准同样方案；也不能反过来宣称它们违规。本任务没有这些产品的实际签名/运行证据。

## 对本仓库逐段核查

| 路径 | 当前依赖 | 本轮处理 |
| --- | --- | --- |
| `ShelfItemSource.swift` | 读外部应用 AXExtrasMenuBar、子项和坐标，建立图标引用。 | 保留直装实现；没有可替换的公开沙盒枚举后端。 |
| `MenuBarAXPressExecutor.swift` / `ShelfItemSource.swift` | AXPress 打开原应用菜单。 | 没有以“启动应用”或假菜单替代。 |
| `MenuBarDragMonitor.swift` | 主动 CGEvent tap 跟踪及拦截拖入操作。 | 未创建真实事件 tap，未模拟输入。 |
| `MenuBarItemMover.swift` / `MenuBarDragEvents.swift` | 合成 Command 拖动、向 HID 投递事件、旧系统分隔项长度布局。 | 未把这些操作仅加 entitlement 后冒充新沙盒后端。 |
| `MenuBarAgentVisibility.swift` | macOS 27 直装版使用私有 MenuBarClientCore。 | 商店/审计编译分流继续排除私有实现；没有从别的产品复制私有接口。 |
| `ShelterBarDistribution.swift` 与更新器编译条件 | 商店/审计排除 GitHub 更新器，直装保留。 | 未改产品代码；对两种既有 Release 产物重新做二进制审计。 |
| `MenuBarCollectionEngineTests.swift` | 首次空/部分扫描、晚到图标、手动收纳与恢复。 | 没有修改 `.keepVisible` 策略或放宽断言；完整回归覆盖。 |

没有写一个假沙盒应用来“试过算完成”。本轮实际执行的是在线资料检索、公开源码与本机 SDK/字典静态核查、现有测试、二进制分流检查和预期失败的 Archive。**没有实机沙盒收纳实验，也没有三屏 GUI 验收。**

## 验证与交接

环境：MacBook Pro `Mac17,2` / arm64，macOS 27.0.1（26A434），Xcode 27.2（27B52）。

| 本轮实际执行 | 结果 |
| --- | --- |
| `swift test --force-resolved-versions --no-parallel` | 193 项应用测试 + 32 项核心测试通过；包含首次安装保持可见、晚到图标和手动收纳回归。 |
| 同命令增加 `-Xswiftc -DSHELTERBAR_APP_STORE` | 181 项应用测试 + 32 项核心测试通过；这是去更新器/私有后端编译条件测试，不是沙盒运行。 |
| `sh -n scripts/check-app-store-backend.sh`、`git diff --check` | 通过；没有放宽测试断言，没有新增假后端。 |
| AppStore scheme、本地无签名 Archive | 最终实测退出 65，失败来自后端保护脚本；没有生成 xcarchive 或 ShelterBar 可执行文件，不是因缺证书而失败。 |
| 既有 Direct Release 二进制重新审计、严格验签 | 通过，GitHub feed / 安装器仍存在。使用上一轮已构建产物，本轮未重新构建直装包。 |
| 既有 UpdaterFreeAudit Release 二进制重新审计、严格验签 | 通过，已知更新器符号/字符串和 MenuBarClientCore / MBAssessmentMode 字符串均未检出；产物仍未沙盒化。 |

最终 Archive 命令如下，使用独立输出目录且关闭签名，验证功能保护不依赖开发者登录或分发证书：

```sh
xcodebuild -project ShelterBar.xcodeproj -scheme ShelterBar-AppStore \
  -configuration AppStore -destination 'generic/platform=macOS' \
  -derivedDataPath '<本轮独立构建缓存>' \
  -archivePath '<本轮独立输出>/ShelterBar.xcarchive' \
  CODE_SIGNING_ALLOWED=NO archive
```

原始记录在本轮 outbox 的 `REPORT.md` 和 `evidence/`，包括两套测试日志、最终 Archive 日志、二进制审计结果、带读取时间和 URL 的在线资料快照、本机 SDK/脚本字典核查记录。商店 Archive 的阻止结果不能计作商店构建成功；审计测试和去更新器产物均不是沙盒运行证明。本轮原有 150ms 时限用例通过，未对历史 flaky 原因作出新的诊断结论。

继续的实质条件是获得适用于日常菜单栏管理的公开机制，或 Apple 针对具体产品用途的可执行技术答复。可以将以下问题交给 DTS / Apple Developer Support；本轮只准备问题，没有发送：

> ShelterBar needs user-selected third-party menu-bar item conceal/reveal and access to the original menus on current macOS, inside one sandboxed Mac App Store installation. NSStatusItem length-based concealment no longer works on macOS 27; AX is sandbox-incompatible. Is there a supported public API or documented entitlement for this ordinary utility use case, without private MenuBarClientCore, a separate unsandboxed helper, or an assessment session? If so, what OS availability, entitlement approval and supported operations apply?

三屏验收、商店签名/描述文件、部署隐私页、上传和提审均未在本轮执行；沙盒核心阻塞也不会被证书或网站部署消除。用户已授权整体流程按顺序推进，但这些仍是后续任务，不能记成完成。
