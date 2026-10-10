# 随播 Android 正式签名审计（2026-10-10）

## 已验证的私有材料
- Google Drive「签名文件」文件夹内的「随播_Android_正式签名密钥_20261010.zip」，大小 4,126 字节。
- ZIP SHA-256：cde7f613cbfea4bc6906bb18d5c2e2ff0a4592582d56ac6ad8024c1198a32f35
- ZIP 包含 suibo-release.jks、signing-credentials.txt、key.properties.example。
- 已在隔离环境验证 JKS 密码、别名、私钥密码均有效，类型 PrivateKeyEntry；不在仓库写入密码或私钥。
- 签名证书 SHA-256：06:19:32:CC:DE:0F:C6:BA:F4:92:F9:73:B0:E7:CB:D1:D3:55:D8:E1:5E:6D:58:2E:DE:F2:A3:21:DC:F1:A0:F4
- 证书有效期：2026-10-10 至 2054-02-25。

## 发布安全修复
- 原 Android Release 无私有 key.properties 时回退 Debug 签名，现改为正式发布必须验证私有签名，禁止默默回退。
- scripts/prepare_suibo.py 初次导入源码亦使用相同安全规则。
- scripts/private_android_release.py 在受控 Flutter+JDK+Android SDK 主机本地读取 ZIP，临时释放私钥，构建后强制删除临时 key.properties。
- 使用 keytool、apksigner 和 aapt 验证签名指纹、APK 证书、包名 com.jianglab.suibo、版本号。
- 输出目录必须位于 GitHub 工作树之外，自动生成本地签名报告（APK SHA-256、大小、证书指纹），不向公共仓库/Actions/Release 上传 APK 或凭据。

## 当前验证边界
- 公共 CI 先前已成功构建 Android Debug 和 Windows Release，但不等于正式 Android APK 已签名。
- 当前工作容器仅具备 Java/keytool，缺少 Flutter SDK 与 Android SDK，且无外部网络安装通道。因此不能在本会话完成正式 APK 编译；CI 仅执行安全守卫和假凭据单测。
- 真实 APK 成品仍需由具备上述环境的受控构建机生成，再检查覆盖升级、运行及实际视频播放。

## 私有构建命令
python scripts/private_android_release.py --keys /PRIVATE/随播_Android_正式签名密钥_20261010.zip --output-dir /PRIVATE/SuiboReleases

所有私有密码和密钥仅在用户指定的 Drive 文件与受控私有构建环境存在；不得写入公开 CI 日志。
