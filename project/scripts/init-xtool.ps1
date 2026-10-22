param(
    [string]$CertificateDirectory,
    [string]$DeviceUdid,
    [string]$Repository = 'Kaurisss/SwiftSSH-Client'
)
$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $Project '.xtool-local.json'
$Cache = Join-Path $env:LOCALAPPDATA 'xtool-local'
$Python = Join-Path $Cache 'venv-11.42.0\Scripts\python.exe'
$Zsign = Join-Path $Cache 'zsign-1.1.3\zsign.exe'

function Assert-Native([string]$Message) {
    if ($LASTEXITCODE -ne 0) { throw $Message }
}

try {
    $RepositoryRoot = Split-Path -Parent $Project
    if (-not (Test-Path (Join-Path $RepositoryRoot 'project.yml'))) {
        throw '请将 project 文件夹放在 SwiftSSH 的 project.yml 同级目录。'
    }
    $Existing = if (Test-Path $ConfigPath) { [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json } else { $null }
    $Gh = (Get-Command gh -ErrorAction Stop).Source
    & $Gh auth status *> $null
    Assert-Native '请先安装 GitHub CLI 并运行 gh auth login，登录有私有仓库读取权限的账户。'
    & $Gh repo view $Repository --json nameWithOwner --jq .nameWithOwner
    Assert-Native '无法读取 GitHub 仓库，请检查仓库名称和当前账户权限。'
    $OpenSslCommand = Get-Command openssl -ErrorAction SilentlyContinue
    if ($OpenSslCommand) {
        $OpenSsl = $OpenSslCommand.Source
    } else {
        $GitPath = (Get-Command git -ErrorAction Stop).Source
        $OpenSsl = Join-Path (Split-Path -Parent (Split-Path -Parent $GitPath)) 'usr\bin\openssl.exe'
    }
    if (-not (Test-Path -LiteralPath $OpenSsl)) { throw '未找到 OpenSSL；请安装 Git for Windows 或将 openssl.exe 加入 PATH。' }
    & $OpenSsl version
    Assert-Native 'OpenSSL 无法运行。'
    if (-not $CertificateDirectory) {
        $CertificateDirectory = if ($Existing) { $Existing.certificateDirectory } else { Read-Host '证书目录（含 P12、描述文件，可选 密码.txt）' }
    }
    $CertificateDirectory = (Resolve-Path -LiteralPath $CertificateDirectory).Path
    if ($CertificateDirectory.StartsWith($RepositoryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $CertificateDirectory -eq $RepositoryRoot) {
        throw '证书和密码请保存在项目目录之外，防止误提交。'
    }
    if (@(Get-ChildItem -LiteralPath $CertificateDirectory -Filter '*.p12' -File).Count -ne 1 -or
        @(Get-ChildItem -LiteralPath $CertificateDirectory -Filter '*.mobileprovision' -File).Count -ne 1) {
        throw '证书目录必须各有一个 .p12 和 .mobileprovision 文件。'
    }
    if (-not $DeviceUdid -and $Existing) { $DeviceUdid = $Existing.deviceUdid }

    # Ignore local configuration before creating it; refuse to write an already tracked config.
    $Git = Get-Command git -ErrorAction SilentlyContinue
    $GitDirectory = [IO.DirectoryInfo]::new($Project)
    while ($GitDirectory -and -not (Test-Path -LiteralPath (Join-Path $GitDirectory.FullName '.git'))) {
        $GitDirectory = $GitDirectory.Parent
    }
    if ($Git -and $GitDirectory) {
        $Tracked = (& $Git.Source -C $Project ls-files -- .xtool-local.json | Out-String).Trim()
        Assert-Native '无法检查 Git 跟踪状态。'
        if ($Tracked) { throw '.xtool-local.json 已被 Git 跟踪，请先移出版本控制。' }
    }
    $Ignore = Join-Path $Project '.gitignore'
    $IgnoreText = if (Test-Path $Ignore) { [IO.File]::ReadAllText($Ignore) } else { '' }
    foreach ($Entry in @('/.xtool-local.json', '/.xtool-output/', '__pycache__/')) {
        if (($IgnoreText -split '\r?\n') -notcontains $Entry) { $IgnoreText = $IgnoreText.TrimEnd() + "`n" + $Entry + "`n" }
    }
    [IO.File]::WriteAllText($Ignore, $IgnoreText, [Text.UTF8Encoding]::new($false))

    New-Item -ItemType Directory -Path $Cache -Force | Out-Null
    if (-not (Test-Path $Python)) {
        $SystemPython = (Get-Command python -ErrorAction Stop).Source
        & $SystemPython -c "import sys, struct; assert sys.version_info >= (3, 10) and struct.calcsize('P') == 8, 'Need 64-bit Python 3.10+'"
        Assert-Native '需要 Windows 64 位 Python 3.10 或更新版本。'
        & $SystemPython -m venv (Split-Path (Split-Path $Python))
        Assert-Native '无法创建本地 Python 虚拟环境。'
    }
    $InstalledVersion = (& $Python -c "import importlib.util as u, importlib.metadata as m; print(m.version('pymobiledevice3') if u.find_spec('pymobiledevice3') and u.find_spec('cryptography') else '')" | Out-String).Trim()
    Assert-Native '无法检查 Python 依赖版本。'
    if ($InstalledVersion -ne '11.42.0') {
        & $Python -m pip install --disable-pip-version-check 'pymobiledevice3==11.42.0'
        Assert-Native '安装 pymobiledevice3 失败。'
    }
    $Archive = Join-Path $Cache 'zsign-windows-x64-1.1.3.zip'
    $ExpectedHash = '6fb5e12a5b7179cfe7e729aa471b35ccf86474eba33d8203df119bf62bad77f7'
    if (-not (Test-Path $Archive)) {
        Invoke-WebRequest 'https://github.com/zhlynn/zsign/releases/download/v1.1.3/zsign-windows-x64.zip' -OutFile $Archive -UseBasicParsing
    }
    $Hasher = [Security.Cryptography.SHA256]::Create()
    $Stream = [IO.File]::OpenRead($Archive)
    try { $ActualHash = [BitConverter]::ToString($Hasher.ComputeHash($Stream)).Replace('-', '').ToLowerInvariant() }
    finally { $Stream.Dispose(); $Hasher.Dispose() }
    if ($ActualHash -ne $ExpectedHash) {
        throw 'zsign 下载文件的 SHA-256 不匹配，已停止。请删除缓存中的该 ZIP 后重试。'
    }
    if (-not (Test-Path $Zsign)) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($Archive, (Split-Path $Zsign))
    }
    if (-not (Test-Path $Zsign)) { throw 'zsign 解压失败。' }
    $Config = [ordered]@{
        repository = $Repository
        ghPath = $Gh
        opensslPath = $OpenSsl
        certificateDirectory = $CertificateDirectory
        deviceUdid = $DeviceUdid
    }
    [IO.File]::WriteAllText($ConfigPath, ($Config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Write-Host '初始化完成。双击本目录的 一键签名安装.cmd 即可下载 Actions IPA、签名并安装。'
    Write-Host '证书和密码未复制到项目；本次初始化未安装或覆盖手机上的应用。'
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
