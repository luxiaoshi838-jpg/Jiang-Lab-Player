# 随播 Android 正式签名

签名密钥已保存在受控 Google Drive「签名文件」目录：
**随播_Android_正式签名密钥_20261010.zip**

此公开仓库不包含正式 JKS、keystore 密码、key 密码或可还原它们的材料。

## 在受控构建机上生成正式 APK

1. 下载上述 ZIP 并在私有目录解压，不要解压到本 Git 仓库。
2. 用压缩包中 `signing-credentials.txt` 提供的密码和别名，在项目本地建立 **android/key.properties**（此文件已被 .gitignore 排除）。

```properties
storeFile=/secure/absolute/path/suibo-release.jks
storePassword=从私有凭据文件读取
keyAlias=suibo
keyPassword=从私有凭据文件读取
```

3. 检查 `android/app/build.gradle` 读取以上四项，然后运行：

```sh
flutter pub get
flutter build apk --release
```

4. 用 apksigner 检查 APK 包名和签名指纹；保留同一密钥供后续升级签名。
5. 禁止向公开 GitHub 提交密钥或其密码。GitHub Actions 的无凭据构建仅提供 debug APK，不作为正式发布 APK。

### Windows
Windows Release 从同一 Flutter 工程编译。Windows 的代码签名证书（如需 SmartScreen 信任）与 Android JKS 不同，不能互相替代。

### 密钥管理
密钥丢失将影响 Android 后续覆盖升级；请另行保留受控备份。压缩包内的凭据是敏感内容，禁止公开共享。
