# SwiftSSH Client

面向 **iPhone / iPad（iOS 18+）** 的 SSH 服务器管理工具，基于
[nirasnet/mssh](https://github.com/nirasnet/mssh) 二次开发，保留 MIT 许可证及原作者声明。

## 当前基线

- 主机分组、收藏、搜索、SSH config 导入；快速连接支持 IPv6 和 `ssh://` 地址。
- 密码 / SSH 密钥登录、首次连接及密钥变更确认；核对指纹时保留等待状态。
- SwiftTerm 交互式终端、多个会话、iPad 分屏、常用命令搜索与原文保存。
- SFTP 目录浏览、文件搜索、按名称/修改时间/大小排序、隐藏文件开关。
- SFTP 分块上传下载，拒绝覆盖远程同名文件；下载完成后可保存到“文件”或分享。
- 本地 SwiftData 数据库；密码和私钥仅保存到设备 Keychain。
- 不启用应用管理的 iCloud 同步、自动云端导入、打赏或占位端口转发。
- 数据库打开失败显示错误及重试入口，保留数据库，不自动清空或改用临时内存库。

界面支持简体中文和英文，默认跟随设备语言。应用外观默认跟随系统，也可在“设置 → 应用外观”中选择浅色或深色。
默认终端主题随外观切换，其他终端主题仍可独立选择。沿用上游应用图标。
系统“文件”选择器仍可由用户主动选择 iCloud Drive 等文件提供者；这不是应用自动同步。

## GitHub Actions 构建 unsigned IPA

私有仓库：https://github.com/Kaurisss/SwiftSSH-Client

在仓库 **Actions → Build unsigned IPA → Run workflow** 手动启动。
工作流使用 macOS 26 Intel / Xcode 26.6，安装 Metal 工具链，生成工程、构建未签名 Release 归档，并将
`Payload/SwiftSSH.app` 打包为 IPA。不需要 Apple 证书、描述文件或签名 Secrets。

构建成功后下载 **Artifacts → SwiftSSH-unsigned**，解压得到
`SwiftSSH-unsigned.ipa`（保留 7 天）。失败时会上传 `archive-log` 便于排查。
私有仓库构建会使用账户的 GitHub Actions 额度。

unsigned IPA 需自行签名后才能安装到常规 iPhone / iPad。
Windows 用户可用 [project/初始化.cmd](project/初始化.cmd) 配置本地证书，
再运行 [project/一键签名安装.cmd](project/一键签名安装.cmd) 自动下载、签名和安装，
详见 [SIGNING.md](project/SIGNING.md)。本地流程不需要 WSL 或 xtool。
此工作流会先运行单元测试和中文界面/外观切换测试，上传 `interface-screenshots`，然后构建设备端 Release IPA。

## 在 Mac 上运行

准备 Xcode（建议 26+，以支持锁定依赖的 Swift 工具链）、已安装的 iOS 模拟器，以及 XcodeGen：

```bash
brew install xcodegen
cd SwiftSSH
xcodegen generate
open SwiftSSH.xcodeproj
```

**必须先生成工程。** 根目录的 `project.yml` 是唯一构建配置来源。
上游 `mssh.xcodeproj` 仅作参考，仍含原作者配置，请勿打开它来构建本分支。
本地为 Windows 环境；工程生成、iOS 编译和模拟器测试由 GitHub Actions 执行。

模拟器直接选择 `SwiftSSH` scheme 运行，不需要设置开发团队。
真机运行时，在 Signing & Capabilities 选择自己的 Team，并将
`project.yml` 中 `com.example.swiftssh` / `com.example.swiftssh.tests`
改为自己的唯一标识后重新生成工程。本地版本不需要 CloudKit 能力。

`com.example.swiftssh` 是开发占位值；本分支不会读取原版 mSSH 的沙盒数据或钥匙串。
如修改 Bundle ID，还应同步修改 `mssh/Services/KeychainService.swift` 的服务名称。

## 验证

在 Mac 上：

```bash
# 选择本机已安装的模拟器
xcrun simctl list devices available
DESTINATION='platform=iOS Simulator,name=iPhone 16' bash build.sh
```

脚本会重新生成工程并执行单元测试和 UI 测试，任一步失败即返回失败。
模拟器使用无需证书的本地 ad-hoc 签名及模拟器专用钥匙串权限；设备归档仍关闭签名。
测试使用独立临时目录和随机 Keychain 账户，覆盖：
- 本地数据库写入后重新打开。
- 损坏数据库报错时保留原文件及相邻数据库。
- 密码、私钥仅存在设备本地 Keychain。
- SFTP 目录失败重试、返回历史、搜索排序、名称校验及下载隔离。

跨平台配置自检（Python 3.10+，无需额外依赖）：

```bash
python scripts/check_baseline.py
python -m unittest discover -s scripts -p test_interface.py -v
```

随后在测试服务器做烟测：密码登录、Ed25519 登录、拒绝未知指纹、终端输入/调整尺寸、
SFTP 小文件上传下载、后台返回后解锁。
CI 已通过实际 OpenSSH 回环服务的 Ed25519 认证、主机指纹、命令和 SFTP 文件往返测试。
测试密钥临时生成，不使用个人服务器凭据。普通本地构建未配置该测试服务时，会明确跳过回环测试。
个人服务器及真机烟测仍待执行。

## 文件位置

- `project.yml`：iOS 应用及测试 target，固定 Citadel 0.12.1 / SwiftTerm 1.13.0。
- `mssh/App/msshApp.swift`：启动、锁屏及存储错误界面。
- `mssh/Services/LocalStore.swift`：仅本地、失败向上传递的存储初始化。
- `mssh/Services/KeychainService.swift`：设备本地凭据。
- `mssh/Resources/Localizable.xcstrings`：英文/简体中文文案及格式化模板。
- `mssh/App/DesignSystem.swift`：自适应配色与外观模式。
- `SwiftSSHTests/`：存储、钥匙串、外观及本地化回归测试。
- `SwiftSSHUITests/`：模拟器中的中文界面、外观切换和截图。
- `UPSTREAM.md`：上游来源及本轮改动边界。

macOS、云同步、打赏等上游源码保留作参考，已从当前 target 排除。
`project.yml.full`、旧归档/发布脚本和商店资料同样是上游参考文件，不是本分支构建入口。
SFTP 每次读写 32,000 字节；下载通过临时文件完成后再替换目标，失败保留原本地文件。
首次确认指纹会重新建立一次握手，并固定校验刚确认的密钥。
