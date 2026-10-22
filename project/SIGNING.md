# Windows 下载、签名并安装 Actions IPA

流程：GitHub Actions 编译 → Windows 下载 unsigned IPA → zsign 本地签名 → USB 安装并查询结果。
本地不再依赖 WSL、xtool、Swift 或 Darwin SDK。脚本沿用原有的本地缓存名称。

## 首次初始化

准备 Windows x64、Python 3.10+、Git for Windows（含 OpenSSL）、GitHub CLI，以及运行中的 Apple Mobile Device Service。

1. 运行 `gh auth login`，登录能读取私有仓库 `Kaurisss/SwiftSSH-Client` 的账户。
2. 在仓库 Actions 中成功完成一次 **Build unsigned IPA**。
3. 将一个 `.p12` 和配套 `.mobileprovision` 保存在 **整个 SwiftSSH 仓库目录之外**。
4. 可在证书目录放 UTF-8 `密码.txt`，支持纯密码、`密码：...` 或 `证书密码: ...`；不放此文件则运行时隐式输入。
5. 双击本目录的 **初始化.cmd**，输入证书目录。已有 xtool 本地配置需重新初始化一次。

初始化只检查 GitHub/工具和证书文件位置，安装本地依赖并保存路径；不签名或安装手机应用。
完整证书匹配、有效期和设备授权检查在签名入口执行。

可直接传入目录，避免交互：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\init-xtool.ps1 -CertificateDirectory 'C:\path\to\certificates'
```

可用 `-Repository owner/repo` 指向自己的副本，`-DeviceUdid` 固定设备。
无需 Apple ID 登录，也不上传证书或密码到 GitHub。

## 日常使用

双击 **一键签名安装.cmd**。脚本读取仓库 `main` 分支最新一次 `unsigned-ipa.yml` 构建：

- 最新构建成功：下载该 run 的 `SwiftSSH-unsigned` 产物，显示 run 链接和提交 SHA。
- 最新构建失败、排队或进行中：停止，不自动退回旧产物。
- 产物已过期：下载报错，需要重新运行 Actions。
- unsigned / signed IPA 均保存到本目录 `.xtool-output/`，文件名包含 run ID。

手机保持 USB 插线、解锁并信任此电脑。签名会验证 P12 与描述文件匹配、有效期及设备授权。
描述文件限定固定 Bundle ID 时使用该标识，不改源码。首次遇到手机已有同标识应用会要求输入
`INSTALL`；本入口安装并记录过的同一项目后续可更新。安装后手动打开应用。

只做下载和预检查（不签名、不安装）：

```powershell
.\一键签名安装.cmd --check
```

## 本地数据与测试

`.xtool-local.json` 保存仓库和工具路径、证书目录及可选设备 UDID；`.xtool-output/` 保存产物与安装记录。
两者及 Python 缓存已加入 `.gitignore`。证书、密码不复制进仓库、不写入命令行参数。
临时 PEM 私钥在仅当前用户 / SYSTEM 可访问的 Windows 临时目录中使用，结束后删除。

工具缓存：`%LOCALAPPDATA%\xtool-local`，包含 zsign 1.1.3（SHA-256 校验）和隔离的 pymobiledevice3 11.42.0。
OpenSSL 使用 PATH 中的版本或 Git for Windows 附带版本。GitHub 授权使用 `gh` 的本机登录。

离线测试（不使用真实证书或手机）：

```powershell
python -m unittest discover -s scripts -p test_local_sign_install.py -v
```

此入口适用于没有 App 扩展或 Watch App 的单应用 IPA。未做真实证书签名及手机安装验证。
