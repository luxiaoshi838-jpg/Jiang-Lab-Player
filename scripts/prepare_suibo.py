#!/usr/bin/env python3
"""Adapt a clean Kazumi checkout for 随播. Idempotent; no signing secrets."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def edit(path, old, new, *, required=True):
    file = ROOT / path
    body = file.read_text(encoding="utf-8")
    if new in body:
        return
    if old not in body:
        if required:
            raise RuntimeError(f"Expected source anchor not found: {path}: {old[:55]}")
        return
    file.write_text(body.replace(old, new, 1), encoding="utf-8")

def main():
    edit("android/app/src/main/AndroidManifest.xml",
         'android:label="Kazumi"', 'android:label="随播"')
    edit("android/app/build.gradle",
         'applicationId "com.predidit.kazumi"',
         'applicationId "com.jianglab.suibo"')
    edit("lib/main.dart", "title: 'Kazumi',", "title: '随播',", required=False)
    edit("windows/runner/Runner.rc",
         'VALUE "ProductName", "kazumi" "\\0"',
         'VALUE "ProductName", "随播" "\\0"', required=False)
    edit("windows/runner/Runner.rc",
         'VALUE "FileDescription", "kazumi" "\\0"',
         'VALUE "FileDescription", "随播" "\\0"', required=False)
    edit("windows/runner/Runner.rc",
         'VALUE "InternalName", "kazumi" "\\0"',
         'VALUE "InternalName", "suibo" "\\0"', required=False)
    edit("windows/runner/Runner.rc",
         'VALUE "OriginalFilename", "kazumi.exe" "\\0"',
         'VALUE "OriginalFilename", "suibo.exe" "\\0"', required=False)
    cmake = ROOT / "windows" / "CMakeLists.txt"
    src = cmake.read_text(encoding="utf-8")
    src = src.replace('set(BINARY_NAME "kazumi")', 'set(BINARY_NAME "suibo")')
    cmake.write_text(src, encoding="utf-8")
    gradle = ROOT / "android/app/build.gradle"
    src = gradle.read_text(encoding="utf-8")
    key_config = """// 随播签名文件不得提交仓库；仅从本地 key.properties 中读取。
def suiboKeyProperties = new Properties()
def suiboKeyFile = rootProject.file('key.properties')
if (suiboKeyFile.exists()) {
    suiboKeyFile.withInputStream { suiboKeyProperties.load(it) }
}
"""
    if 'def suiboKeyProperties' not in src:
        src = src.replace('android {\n', key_config + '\nandroid {\n', 1)
        src = src.replace('    buildTypes {\n',
            """    signingConfigs {
        suiboRelease {
            if (suiboKeyFile.exists()) {
                storeFile file(suiboKeyProperties['storeFile'])
                storePassword suiboKeyProperties['storePassword']
                keyAlias suiboKeyProperties['keyAlias']
                keyPassword suiboKeyProperties['keyPassword']
            }
        }
    }
    buildTypes {
""", 1)
        src = src.replace('signingConfig signingConfigs.debug',
            'signingConfig suiboKeyFile.exists() ? signingConfigs.suiboRelease : signingConfigs.debug')
        gradle.write_text(src, encoding="utf-8")
    ignore = ROOT / ".gitignore"
    with ignore.open("a", encoding="utf-8") as f:
        f.write("\n# 随播私有签名资料（禁止上传）\n*.jks\n*.keystore\nkey.properties\n**/key.properties\n")
    print("SUIBO PATCH OK: Android and Windows branding (original layout unchanged).")

if __name__ == "__main__":
    main()
