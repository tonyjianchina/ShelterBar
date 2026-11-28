# App Store Connect 交接草案（未提交）

当前商店收纳后端尚未成立，文案只描述目标行为，不能当作已可上架的产品承诺。不要上传审计包或用网页动画代替真实 App 截图。

| 项目 | 准备值 / 维护者动作 |
| --- | --- |
| App 名称 | ShelterBar |
| 平台 / Bundle ID | macOS / `com.jensen.shelterbar` |
| 当前代码版本 | 0.5.14 / build 38；正式上传须使用有效且递增的构建号 |
| 主类别 | Utilities / 实用工具 |
| 主语言 / 本地化 | 简体中文、英语 |
| 价格 | 免费；在 Connect 设置所有销售地区的免费档位 |
| 地区 | 目标包含中国大陆及海外；持有人完成 Connect 当时要求的地区表单 |
| 隐私 URL | https://shelterbar.zhengjian.me/privacy（发起人先部署） |
| 支持 URL | https://github.com/tonyjianchina/ShelterBar/issues |
| App 隐私 | 当前应用实现不收集、不追踪；最终后端/SDK 发生变化时重新核对 |
| 加密 | 现有实现只用系统 HTTPS / CryptoKit SHA-256，`ITSAppUsesNonExemptEncryption=false`；最终实现重新核对 |
| 年龄 / 内容问卷 | 实用工具；按最终功能逐项填写，不凭本表跳过问卷 |
| DSA / 中国大陆字段 | 由持有人按账号及实际服务填写；本分支不作法律身份或豁免声明 |
| 截图 | 真实商店签名应用的截图；三个显示器的功能检查另记验收表 |

## 简体中文文案草案

副标题：给菜单栏，留一点空白

描述：

> ShelterBar 把暂时不用的菜单栏图标放进收纳栏。需要时，点开图标原来的菜单，或把它拖回顶部。
>
> 第一次启动保持已有图标可见。只有你手动拖入的图标才会加入收纳；布局保存在这台 Mac 上。
>
> 没有账号、广告或遥测。权限和本地数据的用途可在应用内隐私政策中查看。商店版本只通过 Mac App Store 更新。

关键词草案：菜单栏,收纳,图标,整理,效率

## English draft

Subtitle: A little room for the menu bar

Description:

> ShelterBar puts less-used menu bar icons on a shelf. Open an icon’s original menu when you need it, or drag it back to the menu bar.
>
> Existing icons stay visible on first launch. Only icons you explicitly drag in join the shelf. Your layout stays on this Mac.
>
> No account, advertising, or telemetry. Read the in-app privacy policy for details about permissions and local data. The store version receives updates only through the Mac App Store.

Keyword draft: menu bar,icons,organizer,productivity

## 审核说明与提交前验收

完成真实沙盒后端后重写审核备注，逐步说明商店包的实际操作、必要权限与可选权限，禁止继续复制直装版的 AX/HID 说明冒充可用。至少验收：

- 干净安装时不移动任何已有图标；部分扫描、授权后重新扫描、重启也不能新增收纳。
- 用户手动拖入、恢复、点开原菜单，关闭菜单后行为符合说明。
- 内置 Retina 和外接屏逐一验证，记录分辨率、缩放、刘海、全屏及菜单栏自动隐藏情形。
- 无 GitHub 更新按钮、feed、安装器或私有框架；确认签名实际带沙盒，且安装后功能仍然成立。
- 本地导出且安装验收通过，再由获授权的维护者操作 Connect 上传和审核。
