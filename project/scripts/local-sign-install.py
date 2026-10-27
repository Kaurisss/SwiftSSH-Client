"""Download (or use a local) IPA, sign with local credentials, and install over USB."""
import argparse
import asyncio
import csv
import datetime as dt
import getpass
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "xtool-local"
ZSIGN = CACHE / "zsign-1.1.3" / "zsign.exe"
OUTPUT = ROOT / ".xtool-output"
RECEIPT = OUTPUT / "installed.json"


def download_ipa(config):
    gh = config["ghPath"]
    repository = config["repository"]
    runs = json.loads(subprocess.check_output(
        [gh, "run", "list", "--repo", repository, "--workflow", "unsigned-ipa.yml",
         "--branch", "main", "--limit", "1", "--json", "databaseId,status,conclusion,url,headSha"],
        encoding="utf-8", timeout=30,
    ))
    if not runs:
        raise ValueError("仓库还没有构建记录，请先在 Actions 中运行 Build unsigned IPA。")
    run = runs[0]
    if run["status"] != "completed" or run["conclusion"] != "success":
        raise ValueError(f"最新 Actions 构建尚未成功，未改用旧产物：{run['url']}")
    print(f"构建：{run['url']}\n提交：{run['headSha']}", flush=True)
    OUTPUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="download-", dir=OUTPUT) as name:
        directory = Path(name)
        subprocess.run(
            [gh, "run", "download", str(run["databaseId"]), "--repo", repository,
             "--name", "SwiftSSH-unsigned", "--dir", str(directory)],
            check=True, timeout=300,
        )
        ipas = list(directory.glob("*.ipa"))
        if len(ipas) != 1:
            raise ValueError("Actions 产物必须包含且只包含一个 IPA。")
        ipa_info(ipas[0])
        destination = OUTPUT / f"SwiftSSH-{run['databaseId']}-unsigned.ipa"
        os.replace(ipas[0], destination)
    return destination


def resolve_ipa(config, ipa_path):
    if ipa_path is None:
        print("[1/3] 下载最新 Actions unsigned IPA…", flush=True)
        return download_ipa(config)
    path = Path(ipa_path).resolve()
    if not path.is_file():
        raise ValueError(f"找不到 IPA 文件：{path}")
    OUTPUT.mkdir(exist_ok=True)
    print(f"[1/3] 使用本地 IPA：{path}", flush=True)
    return path


def validate_profile(profile, certificate_der, device, now):
    expiry = profile["ExpirationDate"].replace(tzinfo=dt.timezone.utc)
    if expiry <= now:
        raise ValueError("描述文件已过期，请向证书商更新。")
    if certificate_der not in profile.get("DeveloperCertificates", []):
        raise ValueError("P12 证书与描述文件不匹配。")
    if not profile.get("ProvisionsAllDevices") and device not in profile.get("ProvisionedDevices", []):
        raise ValueError("描述文件不包含目标 iPhone。")
    prefix, separator, pattern = profile["Entitlements"]["application-identifier"].partition(".")
    if not separator or not pattern or "*" in pattern[:-1]:
        raise ValueError("描述文件的应用标识格式不受支持。")
    if prefix not in profile.get("ApplicationIdentifierPrefix", []):
        raise ValueError("描述文件的应用标识前缀不匹配。")
    return pattern


def choose_device(profile, connected, preferred):
    allowed = connected if profile.get("ProvisionsAllDevices") else [d for d in connected if d in profile.get("ProvisionedDevices", [])]
    if preferred:
        if preferred not in allowed:
            raise ValueError("指定的 iPhone 未通过 USB 连接，或不在描述文件授权范围内。")
        return preferred
    if len(allowed) != 1:
        raise ValueError("请连接唯一一台描述文件授权的 iPhone；多台设备时请初始化时指定 -DeviceUdid。")
    return allowed[0]


def signing_bundle(pattern, original):
    if pattern.endswith("*"):
        if not original.startswith(pattern[:-1]):
            raise ValueError("项目 Bundle ID 不符合描述文件的通配符范围。")
        return original
    return pattern


def ipa_info(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        # shortcut: one profile covers only the main app; extensions need their own profiles.
        if any(".appex/" in name or "/Watch/" in name for name in names):
            raise ValueError("此入口暂不处理 App 扩展或 Watch App 的多描述文件签名。")
        roots = [n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(roots) != 1:
            raise ValueError("IPA 必须包含且只包含一个主应用。")
        return plistlib.loads(archive.read(roots[0])), roots[0].rsplit("/", 1)[0]


def password_bytes(data):
    text = data.decode("utf-8-sig").rstrip("\r\n")
    labeled = re.fullmatch(r"\s*(?:证书)?密码\s*[:：][ \t]*(.*)", text)
    return (labeled[1] if labeled else text).encode("utf-8")


def credentials(config):
    from cryptography.hazmat.primitives.serialization import pkcs12

    directory = Path(config["certificateDirectory"])
    profiles, certificates = list(directory.glob("*.mobileprovision")), list(directory.glob("*.p12"))
    if len(profiles) != 1 or len(certificates) != 1:
        raise ValueError("证书目录必须各有一个 .p12 和 .mobileprovision 文件。")
    password_file = directory / "密码.txt"
    password = password_bytes(password_file.read_bytes()) if password_file.exists() else getpass.getpass("P12 密码（不回显）：").encode("utf-8")
    try:
        key, cert, _ = pkcs12.load_key_and_certificates(certificates[0].read_bytes(), password)
    except ValueError:
        raise ValueError("无法打开 P12：请检查密码以及证书文件。") from None
    if key is None or cert is None:
        raise ValueError("P12 缺少私钥或证书。")
    now = dt.datetime.now(dt.timezone.utc)
    if not (cert.not_valid_before_utc <= now < cert.not_valid_after_utc):
        raise ValueError("签名证书尚未生效或已过期。")
    blob = profiles[0].read_bytes()
    result = subprocess.run(
        [config["opensslPath"], "cms", "-verify", "-noverify", "-inform", "DER"],
        input=blob, capture_output=True, timeout=30,
    )
    if result.returncode:
        raise ValueError("描述文件的 CMS 签名校验失败。")
    return key, cert, blob, plistlib.loads(result.stdout)


def restrict_directory(path):
    # Set a private DACL before writing an unencrypted, short-lived PEM key.
    output = subprocess.check_output(["whoami", "/user", "/fo", "csv", "/nh"])
    sid = next(csv.reader([output.decode(errors="replace").strip()]))[-1]
    subprocess.run(
        ["icacls", str(path), "/inheritance:r", "/grant:r", f"*{sid}:(OI)(CI)F", "*S-1-5-18:(OI)(CI)F"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


async def main(check_only=False, ipa_path=None):
    from cryptography.hazmat.primitives.serialization import Encoding, NoEncryption, PrivateFormat
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.installation_proxy import InstallationProxyService
    from pymobiledevice3.usbmux import list_devices

    config_file = ROOT / ".xtool-local.json"
    if not config_file.is_file():
        raise ValueError("请先运行项目根目录的 初始化.cmd。")
    config = json.loads(config_file.read_text(encoding="utf-8-sig"))
    if not all(config.get(field) for field in ("ghPath", "repository", "opensslPath")):
        raise ValueError("本地配置仍是 xtool 版本，请重新运行 初始化.cmd。")
    ipa = resolve_ipa(config, ipa_path)
    info, _ = ipa_info(ipa)
    key, cert, profile_blob, profile = credentials(config)
    connected = [d.serial for d in await list_devices() if d.connection_type == "USB"]
    device = choose_device(profile, connected, config.get("deviceUdid"))
    pattern = validate_profile(profile, cert.public_bytes(Encoding.DER), device, dt.datetime.now(dt.timezone.utc))
    bundle = signing_bundle(pattern, info["CFBundleIdentifier"])
    print(f"项目：{ROOT.name}\n签名应用标识：{bundle}\n描述文件有效期：{profile['ExpirationDate']} UTC", flush=True)
    print("正在通过 USB 连接 iPhone，请保持解锁并信任此电脑。", flush=True)
    async with await create_using_usbmux(serial=device, connection_type="USB", pair_timeout=20) as phone:
        async with InstallationProxyService(lockdown=phone) as installer:
            existing = await installer.get_apps(bundle_identifiers=[bundle])
    print("USB 连接成功；同标识应用：" + ("已存在" if bundle in existing else "未安装"), flush=True)
    if check_only:
        print("预检查通过；已下载 IPA，未签名或安装。", flush=True)
        return
    previous = json.loads(RECEIPT.read_text(encoding="utf-8")) if RECEIPT.exists() else {}
    identity = {"project": ROOT.name, "bundle": bundle, "device": device}
    if bundle in existing and previous != identity:
        name = existing[bundle].get("CFBundleDisplayName", bundle)
        answer = input(f"手机上已有 {name}。继续会更新此应用；输入 INSTALL 确认，否则取消：")
        if answer != "INSTALL":
            raise ValueError("已取消，未覆盖手机上的应用。")
    print("[2/3] 使用本地证书签名…", flush=True)
    output = OUTPUT / f"{ipa.stem.removesuffix('-unsigned')}-signed.ipa"
    with tempfile.TemporaryDirectory(prefix="sign-", dir=CACHE) as temp_name:
        temp = Path(temp_name)
        restrict_directory(temp)
        (temp / "key.pem").write_bytes(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
        (temp / "cert.pem").write_bytes(cert.public_bytes(Encoding.PEM))
        (temp / "profile.mobileprovision").write_bytes(profile_blob)
        shutil.copyfile(ipa, temp / "unsigned.ipa")
        signed = temp / "signed.ipa"
        subprocess.run(
            [str(ZSIGN), "-q", "-k", str(temp / "key.pem"), "-c", str(temp / "cert.pem"),
             "-m", str(temp / "profile.mobileprovision"), "-b", bundle, "-o", str(signed), str(temp / "unsigned.ipa")],
            check=True, timeout=300, cwd=temp,
        )
        signed_info, app_root = ipa_info(signed)
        with zipfile.ZipFile(signed) as archive:
            if signed_info["CFBundleIdentifier"] != bundle:
                raise ValueError("签名后的应用标识不符合描述文件。")
            if archive.read(app_root + "/embedded.mobileprovision") != profile_blob:
                raise ValueError("签名产物中嵌入的描述文件不匹配。")
            if app_root + "/_CodeSignature/CodeResources" not in archive.namelist():
                raise ValueError("签名产物缺少 CodeResources。")
        staging = output.with_suffix(".ipa.tmp")
        try:
            shutil.copyfile(signed, staging)
            os.replace(staging, output)
        finally:
            staging.unlink(missing_ok=True)
    print(f"已签名 IPA：{output}\n[3/3] 安装到 iPhone…", flush=True)
    # Reconnect after signing to avoid using an idle USB session.
    async with await create_using_usbmux(serial=device, connection_type="USB", pair_timeout=20) as phone:
        async with InstallationProxyService(lockdown=phone) as installer:
            await installer.install_from_local(output)
            installed = await installer.get_apps(bundle_identifiers=[bundle])
    if bundle not in installed:
        raise ValueError("安装后未能在手机上查到该应用，请查看手机提示。")
    RECEIPT.write_text(json.dumps(identity), encoding="utf-8")
    print("安装并查验成功！请在 iPhone 桌面打开应用。", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Download IPA and validate credentials and USB; do not sign or install")
    parser.add_argument("ipa", nargs="?", help="Sign and install this local IPA instead of downloading the latest Actions build")
    args = parser.parse_args()
    try:
        asyncio.run(main(args.check, args.ipa))
    except KeyboardInterrupt:
        print("\n已取消。", flush=True)
        raise SystemExit(1)
    except Exception as error:
        print(f"\n失败：{error}", flush=True)
        raise SystemExit(1)
