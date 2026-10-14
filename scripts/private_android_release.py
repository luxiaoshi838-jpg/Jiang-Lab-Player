#!/usr/bin/env python3
"""Build and verify Suibo Android release locally using a *private* Drive ZIP.

Usage (on a trusted machine with Flutter + Android SDK installed):
  python scripts/private_android_release.py --keys "/private/随播_Android_正式签名密钥_20261010.zip" --output-dir "/private/releases"

No keys, passwords or binary outputs are ever written to GitHub.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PACKAGE = "com.jianglab.suibo"
ZIP_KEY = "suibo-release.jks"
ZIP_CREDS = "signing-credentials.txt"


def parse_credentials(raw: bytes) -> dict[str, str]:
    data = raw.decode("utf-8-sig")
    fields = {}
    for line in data.splitlines():
        if ":" not in line and "：" not in line:
            continue
        key, value = re.split(r"\s*[:：]\s*", line, maxsplit=1)
        fields[key.strip().lower()] = value.strip()
    required = ("key alias", "key store", "store password", "key password")
    if any(not fields.get(key) for key in required):
        raise ValueError("The private signing ZIP is missing required credentials")
    if Path(fields["key store"]).name != ZIP_KEY:
        raise ValueError("The private signing ZIP references an unexpected keystore")
    return fields


def load_private_package(path: Path) -> tuple[bytes, dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError("Private signing ZIP was not found")
    with zipfile.ZipFile(path) as bundle:
        names = set(bundle.namelist())
        if ZIP_KEY not in names or ZIP_CREDS not in names:
            raise ValueError("The ZIP does not contain the expected key files")
        if any(item.flag_bits & 1 for item in bundle.infolist()):
            raise ValueError("Encrypted ZIP entries are unsupported")
        if bundle.getinfo(ZIP_KEY).file_size > 128 * 1024:
            raise ValueError("Unexpected keystore size")
        key = bundle.read(ZIP_KEY)
        credentials = parse_credentials(bundle.read(ZIP_CREDS))
        return key, credentials


def find_android_tool(name: str) -> str:
    suffixes = (".bat", ".exe", "") if os.name == "nt" else ("",)
    for suffix in suffixes:
        found = shutil.which(name + suffix)
        if found:
            return found
    roots = [
        os.environ.get("ANDROID_SDK_ROOT"),
        os.environ.get("ANDROID_HOME"),
        str(Path.home() / "AppData/Local/Android/Sdk"),
        str(Path.home() / "Android/Sdk"),
    ]
    for base in roots:
        if not base:
            continue
        directory = Path(base) / "build-tools"
        if not directory.is_dir():
            continue
        versions = sorted(directory.iterdir(), reverse=True)
        for version in versions:
            for suffix in suffixes:
                executable = version / (name + suffix)
                if executable.is_file():
                    return str(executable)
    raise RuntimeError(f"Android SDK build-tool {name} is not installed")


def run_safe(command: list[str], *, cwd: Path, environment: dict[str, str],
             redactions: tuple[str, ...] = ()) -> str:
    result = subprocess.run(
        command, cwd=str(cwd), env=environment,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace",
        check=False,
    )
    output = result.stdout
    for value in redactions:
        if value:
            output = output.replace(value, "[REDACTED]")
    if result.returncode != 0:
        # Never expose raw Gradle exceptions or user secrets in CI/logs.
        raise RuntimeError(
            f"Command {Path(command[0]).name} failed "
            f"(exit {result.returncode}); check trusted build environment"
        )
    return output


def property_value(value: str) -> str:
    # Java .properties escapes backslashes and control characters.
    return (value.replace("\\", "\\\\")
            .replace("\r", "\\r").replace("\n", "\\n")
            .replace("=", "\\="))


def normalized_hash(fingerprint: str) -> str:
    return re.sub(r"[^0-9a-f]", "", fingerprint.lower())


def checked_cert_hash(output: str, pattern: str) -> str:
    hit = re.search(pattern, output, re.IGNORECASE)
    if not hit:
        raise RuntimeError("Cannot verify signing certificate SHA-256")
    value = normalized_hash(hit.group(1))
    if len(value) != 64:
        raise RuntimeError("Invalid signing fingerprint length")
    return value


def parse_apk_identity(badging: str) -> tuple[str, int, str]:
    """Parse aapt badging so upgrade checks use the actual APK manifest."""
    package = re.search(
        r"package:\s+name='([^']+)'\s+versionCode='(\d+)'\s+versionName='([^']+)'",
        badging,
    )
    if not package:
        raise RuntimeError("Cannot parse APK identity and version")
    return package.group(1), int(package.group(2)), package.group(3)


def build(keys: Path, output_dir: Path,
          previous_apk: Path | None = None) -> Path:
    flutter = shutil.which("flutter")
    keytool = shutil.which("keytool")
    if not flutter or not keytool:
        raise RuntimeError("A trusted machine with Flutter and JDK keytool is required")
    apksigner = find_android_tool("apksigner")
    aapt = find_android_tool("aapt")
    output_dir = output_dir.expanduser().resolve()
    if output_dir == ROOT or ROOT in output_dir.parents:
        raise RuntimeError("The private output directory must be outside the Git repository")
    props_path = ROOT / "android/key.properties"
    if props_path.exists():
        raise RuntimeError("android/key.properties already exists; refusing to overwrite secrets")

    jks, credentials = load_private_package(keys.expanduser().resolve())
    secrets = (
        credentials["store password"],
        credentials["key password"],
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    # Keep private key files out of the source tree and remove all temporary
    # files even when Flutter, Gradle or verification fails.
    with tempfile.TemporaryDirectory(prefix="suibo-private-") as temporary:
        keystore = Path(temporary) / ZIP_KEY
        keystore.write_bytes(jks)
        os.chmod(keystore, 0o600)
        props = {
            "storeFile": keystore.as_posix(),
            "storePassword": credentials["store password"],
            "keyAlias": credentials["key alias"],
            "keyPassword": credentials["key password"],
        }
        props_path.write_text(
            "\n".join(f"{k}={property_value(v)}" for k, v in props.items()) + "\n",
            encoding="utf-8",
        )
        os.chmod(props_path, 0o600)
        try:
            environment = os.environ.copy()
            environment["SUIBO_PRIVATE_STOREPASS"] = secrets[0]
            environment["SUIBO_PRIVATE_KEYPASS"] = secrets[1]
            # Verify the private-key password too, not only the JKS store.
            run_safe([
                keytool, "-certreq", "-alias", credentials["key alias"],
                "-keystore", str(keystore),
                "-storepass:env", "SUIBO_PRIVATE_STOREPASS",
                "-keypass:env", "SUIBO_PRIVATE_KEYPASS",
                "-file", str(Path(temporary) / "verification.csr"),
            ], cwd=ROOT, environment=environment, redactions=secrets)
            keytool_output = run_safe([
                keytool, "-list", "-v", "-keystore", str(keystore),
                "-alias", credentials["key alias"],
                "-storepass:env", "SUIBO_PRIVATE_STOREPASS",
                "-J-Duser.language=en",
            ], cwd=ROOT, environment=environment, redactions=secrets)
            expected_cert = checked_cert_hash(
                keytool_output, r"SHA256:\s*([0-9a-f:]{64,})"
            )
            run_safe([flutter, "pub", "get"], cwd=ROOT,
                     environment=environment, redactions=secrets)
            run_safe([flutter, "build", "apk", "--release"], cwd=ROOT,
                     environment=environment, redactions=secrets)
            candidate = ROOT / "build/app/outputs/flutter-apk/app-release.apk"
            if not candidate.is_file():
                raise RuntimeError("Flutter did not produce the expected release APK")
            verification = run_safe(
                [apksigner, "verify", "--verbose", "--print-certs", str(candidate)],
                cwd=ROOT, environment=environment, redactions=secrets
            )
            signed_cert = checked_cert_hash(
                verification, r"Signer #1 certificate SHA-256 digest:\s*([0-9a-f:]{64,})"
            )
            if signed_cert != expected_cert:
                raise RuntimeError("Signed APK certificate differs from private signing key")
            badging = run_safe([aapt, "dump", "badging", str(candidate)],
                               cwd=ROOT, environment=environment, redactions=secrets)
            package_name, version_code, version_name = parse_apk_identity(badging)
            if package_name != EXPECTED_PACKAGE:
                raise RuntimeError("Release APK application ID is not com.jianglab.suibo")
            previous_version = "NOT CHECKED"
            if previous_apk is not None:
                older = previous_apk.expanduser().resolve()
                if not older.is_file():
                    raise RuntimeError("Previous APK file does not exist")
                old_badging = run_safe(
                    [aapt, "dump", "badging", str(older)],
                    cwd=ROOT, environment=environment, redactions=secrets,
                )
                old_package, old_code, old_version = parse_apk_identity(old_badging)
                if old_package != package_name:
                    raise RuntimeError("Previous APK uses a different Android applicationId")
                old_signing = run_safe(
                    [apksigner, "verify", "--print-certs", str(older)],
                    cwd=ROOT, environment=environment, redactions=secrets,
                )
                old_cert = checked_cert_hash(
                    old_signing,
                    r"Signer #1 certificate SHA-256 digest:\s*([0-9a-f:]{64,})",
                )
                if old_cert != signed_cert:
                    raise RuntimeError("Previous APK has a different signing certificate")
                if old_code >= version_code:
                    raise RuntimeError("New versionCode must exceed the previous APK")
                previous_version = f"{old_version} ({old_code}), UPGRADABLE"

            safe_version = re.sub(r"[^A-Za-z0-9_.-]", "_", version_name)
            destination = output_dir / f"Suibo-Android-{safe_version}-{version_code}-release.apk"
            report = output_dir / f"Suibo-Android-signing-report-{version_code}.txt"
            if destination.exists() or report.exists():
                raise RuntimeError("Version already exists in private output; refusing overwrite")
            shutil.copy2(candidate, destination)
            digest = hashlib.sha256(destination.read_bytes()).hexdigest()
            report.write_text(
                "\n".join([
                    "Suibo private Android release verification",
                    f"Verified UTC: {datetime.now(timezone.utc).isoformat()}",
                    f"Application ID: {package.group(1)}",
                    f"Version code: {version_code}",
                    f"Previous APK upgrade preflight: {previous_version}",
                    f"Version name: {version_name}",
                    f"APK file: {destination.name}",
                    f"APK bytes: {destination.stat().st_size}",
                    f"APK SHA-256: {digest}",
                    f"Signing certificate SHA-256: {expected_cert.upper()}",
                    "APK signature: apksigner verify passed",
                    "Device installation / update test: NOT YET VERIFIED",
                ]) + "\n", encoding="utf-8",
            )
            if not report.is_file():
                raise RuntimeError("Signing report was not created")
            print(f"PRIVATE APK: {destination}")
            print(f"REPORT: {report} ({report.stat().st_size} bytes)")
            print("Verification: signing certificate and package identity match")
            return destination
        finally:
            # Removing the plaintext key.properties is mandatory.
            props_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keys", required=True, type=Path,
                        help="Private signing ZIP from the user's Google Drive")
    parser.add_argument("--output-dir", required=True, type=Path,
                        help="Private directory OUTSIDE the public repository")
    parser.add_argument("--previous-apk", type=Path,
                        help="Optional existing APK for real signature/package/version upgrade check")
    args = parser.parse_args()
    try:
        build(args.keys, args.output_dir, previous_apk=args.previous_apk)
        return 0
    except Exception as error:
        # Deliberately suppress stack traces for signing operations.
        print(f"PRIVATE SIGNING FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
