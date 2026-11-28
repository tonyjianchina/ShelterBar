# Mac App Store 开发与打包状态（2026-11-28）

**目前不能上传一个「启用沙盒、安装后核心收纳仍可用」的 ShelterBar。** 本分支完成了不依赖该前提的工程和上架配套；没有制作不可用的沙盒包，没有上传或提交 App Store Connect。

基线为公开 `main` 的 `cc5a256`（v0.5.14 / build 38）和 PR #5 的 `1633f4b`。独立分支不包含 PR #4 的提交，也不包含本地尚未发布的 v0.5.15 分支。首次启动的扫描漏洞在本分支单独修复，并复用了本地已存在的针对性回归用例；未带入 QQ 音乐或同版本更新修改。

## 沙盒路径核验

本日第二轮重新检索后的详细记录见 [沙盒核心可行性复核](validation/MAS-SANDBOX-20261128.md)。新增核查了 Hidden Bar 当前商店说明与固定提交源码、macOS 27 公开的考试会话菜单栏接口、System Events 本机脚本字典和近期 DTS 问答。没有找到适用于 ShelterBar 日常收纳的完整合规后端；没有解除 Archive gate。

2026-11-28 通过 ego-browser 读取的 Apple 官方资料：

1. [App Review Guidelines 2.4.5 和 2.5.1](https://developer.apple.com/app-store/review/guidelines/)：Mac App Store 版本必须沙盒化、用 Xcode 技术打包、仅由商店更新，并使用公开 API。
2. [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)：明确将辅助类应用使用辅助功能 API 列为沙盒不兼容功能；内嵌 CLI 工具也必须继承应用沙盒。
3. [Determining if an entitlement is real](https://developer.apple.com/forums/thread/799000)（正文也展示于[官方 Entitlements 列表](https://developer.apple.com/forums/tags/entitlements/?page=6&sortBy=lastUpdated&sortOrder=DESC)）：将 `com.apple.security.accessibility` 列为不存在的 entitlement，并说明用户的隐私设置授权不能使沙盒应用使用这些 API。
4. [App Sandbox Temporary Exception Entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)：`apple-events` 是向指定 bundle ID 发送 Apple Event 的例外；不能用于 AX 或 HID 事件。它不是通用的「控制任意应用」授权。
5. [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)、[length](https://developer.apple.com/documentation/appkit/nsstatusitem/length)、[isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)：控制本应用创建的状态项；文档没有提供枚举、搬移或隐藏其他应用状态项的接口。
6. [App Sandbox information](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information)：临时例外需要解释具体 entitlement、用途和缺失功能的 Feedback ID；不存在自动豁免辅助功能的通用申请。

| 现有核心路径 | 本次处理与结论 |
| --- | --- |
| `ShelfItemSource` / `MenuBarAXPressExecutor` 读其他应用 AX、执行 AXPress | 这是实际收纳和打开原菜单的依赖；尚无已核实的沙盒替代实现。 |
| `MenuBarDragMonitor` 的主动 `CGEvent.tapCreate`，以及 `MenuBarDragEvents` 的 HID 合成拖动 | 现有交互需要跨应用拦截及投递输入。不能把 TCC 授权或 Apple Events 例外等同于沙盒能力。官方沙盒页只具体点名 Open/Save 中的输入模拟；对本应用整条 HID 路径的判断属于结合代码的工程推论，不能谎称文档逐字覆盖全部情形。AX 的明确限制已经足以阻止当前实现。 |
| `MenuBarClientCore` / `MBAssessmentMode*` | 在 `SHELTERBAR_APP_STORE` 审计构建中编译移除，替身明确返回不可用。直装版保留原有 macOS 27 行为。移除私有接口本身不会产生可用的沙盒后端。 |
| GitHub 自动更新、下载校验与 `/bin/sh` 替换安装脚本 | 审计构建从二进制中移除；直装版保留。实际 Mach-O 用字符串和符号扫描核验。 |

考虑过的公开方案也不能被当作已经完成的替代实现：

- **自己的分隔状态项 + 用户按 Command 排列。** Hidden Bar 证明该路线有旧系统的商店先例，但其[当前商店页面](https://apps.apple.com/us/app/hidden-bar/id1452453066?mt=12)和公开源码明确说明 macOS 27 的商店沙盒版不能隐藏图标。不能通过改自身长度就宣称当前系统核心可用；也未完成 ShelterBar 原有收纳架交互的替代。
- **把 Apple Events / System Events 改成新后端。** 本轮专门核查此方向，而非仅以当前没发事件为由排除。System Events 的命名权限组只覆盖窗口位置/大小，没有菜单栏项目对应组；没有找到覆盖任意图标收纳、恢复及原菜单的已记录脚本路径。临时指定目标也不是通用 UI 授权。
- **macOS 27 考试会话的公开菜单栏接口。** `AEAssessmentConfiguration.allowedMenuBarItems` 确实存在，但属于需要 Apple 授权的考试会话，没有被记录为普通收纳工具的能力。没有申请或用考试会话替代日常收纳。
- **Mach 服务临时例外。** 该 entitlement 是真的，但 [2026-11-02 的 DTS 答复](https://developer.apple.com/forums/thread/854711)澄清：没有恢复 AX 的专用例外，内部 Mach 服务名不属于公开 API。不能把调用私有协议包装成合规公开后端。
- **内置不受沙盒约束的 helper/XPC，或要求用户另装直装助手。** 前者不能规避继承沙盒的要求；后者也无法满足单一商店安装后核心可用的目标。
- **申请未记载的 AX / 全局 HID entitlement。** 官方 entitlement 文档及上述技术说明没有提供这种通路；不能自行创造 key。

因此，当前没有已证明成立的沙盒收纳路径。下一步需要真正的公开后端和实机验收，或 Apple 对具体能力的书面技术答复；证书、公证或审核备注不能修复这个功能缺口。

## 三种配置及产物边界

| 配置 | 更新器 | 私有可见性接口 | 沙盒 | 用途 |
| --- | --- | --- | --- | --- |
| Direct / SwiftPM 默认 | 保留 | 保留 | 关闭 | 现有直装版；本次 DMG/ZIP 未发布、未安装 |
| UpdaterFreeAudit / `SHELTERBAR_DISTRIBUTION=app-store` | 移除 | 移除 | 关闭 | 只做编译及二进制审计；不是商店包，不应安装或上传 |
| AppStore | 编译开关移除 | 编译开关移除 | 配置为开启 | 当前前置 gate 明确阻止 Build/Archive，不生成假沙盒应用 |

`Resources/ShelterBar-AppStore.entitlements` 仅声明真实的 `com.apple.security.app-sandbox = true`。没有虚构 entitlement、Apple Events 例外或逃逸 helper。配置存在不代表已构建/运行沙盒后端。

## Xcode 工程与本地构建

已提交 `ShelterBar.xcodeproj` 和共享 schemes，直接使用 Xcode 27.2 或 `xcodebuild` 即可，无需先装 XcodeGen。`project.yml` 是工程源配置；仅在修改工程时使用 XcodeGen 2.46+ 重生成：

```sh
xcodegen generate
```

直装 Xcode Archive（本次已用本地证书成功执行；这不是商店签名）：

```sh
xcodebuild -project ShelterBar.xcodeproj -scheme ShelterBar-Direct \
  -destination 'generic/platform=macOS' \
  -archivePath dist/xcode-direct/ShelterBar.xcarchive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='ShelterBar Local Code Signing' \
  DEVELOPMENT_TEAM='' archive
```

不签名的 Xcode 审计编译：

```sh
xcodebuild -project ShelterBar.xcodeproj -scheme ShelterBar-UpdaterFree-Audit \
  -configuration UpdaterFreeAudit -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

原有 SwiftPM 路径继续可用；两种产物分别存放，审计构建不会覆盖直装版：

```sh
./scripts/build-app.sh release
# dist/ShelterBar.app
SHELTERBAR_DISTRIBUTION=app-store ./scripts/build-app.sh release
# dist/updater-free-audit/ShelterBar.app（不得安装、上传）
./scripts/verify-distribution.sh direct dist/ShelterBar.app
./scripts/verify-distribution.sh app-store dist/updater-free-audit/ShelterBar.app
```

`package-release.sh` 拒绝 `SHELTERBAR_DISTRIBUTION=app-store`，保证 GitHub DMG/ZIP 沿用更新器。`build-app.sh` 继续拒绝为当前实现加沙盒。

未来后端和三屏验收完成后，维护者应在同一个经过评审的改动里替换 `scripts/check-app-store-backend.sh` 的阻止逻辑，然后：

```sh
SHELTERBAR_DEVELOPMENT_TEAM='<实际 Team ID>' ./scripts/archive-app-store.sh
# 仅本地 Archive，不上传
xcodebuild -exportArchive \
  -archivePath dist/app-store/ShelterBar.xcarchive \
  -exportPath dist/app-store/export \
  -exportOptionsPlist xcode/ExportOptions-AppStore.plist
```

ExportOptions 使用本机 Xcode 帮助列出的 `app-store-connect`，`destination=export`，不会上传；团队从 Archive 取得。上述商店命令当前会先明确失败。不要删除 gate 后直接把旧 AX/HID 源码装进沙盒。

## 隐私、首次启动与商店资料

- 官方隐私 URL 统一为 **https://shelterbar.zhengjian.me/privacy**。
- 中英政策位于 `website/dist/privacy/index.html`，应用「更多 → 隐私政策」指向同一 URL；页面包括本地缓存、权限、直装更新网络、网站访问、清理方式和联系方式。
- 本地浏览器已检查 `/privacy` 跳转后双语内容、canonical、CSS、首页链接；截图在验证目录。样式和首页链接使用根路径，兼容 `/privacy` 与 `/privacy/`。
- 线上该 URL 于 2026-11-28 仍返回营销首页。**本次未 SSH、未部署**；由发起人部署整个 `website/dist/` 并配置静态路由，再复核内容。见 `website/README.md`。
- 复用 PR #5 的中英文权限用途说明、Utilities 类别、`ITSAppUsesNonExemptEncryption=false` 及 `PrivacyInfo.xcprivacy`。两套构建均嵌入这些资源；清单声明不追踪、不收集数据，自己的 UserDefaults 使用理由为 `CA92.1`。
- 原 `.collect` 策略会把首轮空扫描/部分扫描后发现的旧图标当成新增项。本分支改为 `.keepVisible`：只恢复用户已保存的选择，添加图标必须手动拖入；晚到项和后续启动的应用也不会自动收纳。
- 中英商店文案和 App Store Connect 交接表见 [APP-STORE-LISTING.md](APP-STORE-LISTING.md)。文案是目标行为草案，须待商店后端实测后才能用于提交。

## 证书、商店流程与未完成项

本机复核只有 `ShelterBar Local Code Signing`、`ShelterBar Self-Signed`、`Apple Development: jian tony (2P9FDGLKXX)` 三个有效代码签名身份。没有本地可用的 Apple Distribution / Mac App Distribution，也没有安装包分发签名身份。已读取本地 12 个 provisioning 文件的必要元数据，没有 ShelterBar 或 wildcard 匹配。未尝试网页登录或反复认证，未创建证书/描述文件；当前后端阻塞时创建生产证书也不会使产物合格。

上传前还需要：

1. 公开 API 沙盒后端实现并完成真实收纳、恢复、点开原菜单、首次安装及多屏验收。
2. 账号持有人确认开发者会员和协议，注册 `com.jensen.shelterbar`，选择实际团队；准备 Mac App Store 应用分发证书、Mac Installer Distribution 证书及匹配的 Mac 描述文件，或让 Xcode 在已授权账号中管理。开发证书和自签名不能替代商店分发签名。
3. 用未来可用的 AppStore scheme Archive、本地 Export，检查签名中的沙盒 entitlement、描述文件、更新器/私有 API、嵌入资源、递增的 build 号及安装后功能。本分支仍使用 0.5.14 / 38，没有伪造新发布版本。
4. 发起人部署并核验隐私页；准备真实截图和最终双语文案，填写隐私、年龄、加密、免费价格和包含中国大陆的地区、DSA 身份及 Connect 实际显示的中国大陆合规字段。仓库不能代替账号持有人声明，也不预先断言备案豁免。
5. 用户已授权整体流程按顺序推进到审核；本轮任务范围仍明确禁止上传和提交，留给后续任务，不能记作已经完成。

**公证区别：** [Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)针对 Developer ID 的商店外分发；Mac App Store 有自己的分发与审核流程，不要求维护者先跑 `notarytool` 公证 DMG。当前直装包仍为自签名、未公证；需要改善商店外安装体验时另做 Developer ID 分发，不混为此次商店阻塞。

本轮实测结果和 GUI 限制见 [验证记录](validation/MAS-20261128.md)。构建/单元测试通过不代表沙盒核心可用，也不代表审核通过。
