# 随播双端安装版：Android APK 与 Windows Setup EXE（2026-10-10）

## 要求与现有能力
- 基于现有 Kazumi/随播源码增量修改，不重做播放器、规则引擎或界面。
- Android 正式交付为签名 APK（固定 `com.jianglab.suibo`，原私有正式 JKS）。
- Windows 正式交付为包含所有 Flutter DLL、assets 的 **Setup 安装程序 EXE**，不是单独可执行文件或“随用版”目录。
- 版本升级为 `2.3.9+20309`；不能保证覆盖未知的更高 versionCode，老 APK 必须使用相同签名证书和包名。
- Windows 固定 Inno AppId：`{FE6015EC-9973-449D-9B64-662CF98C580B}`，后续安装版沿用 AppId 进行就地覆盖更新，保留安装位置和 AppData。
- 上次的 Windows **随用版**没有安装器注册信息；新安装版不会在未知位置自动删除老随用版文件；使用同一用户配置目录时可以保留用户数据，仍须本机验证。
- Windows 进程标题和 mutex 从 Kazumi 改为随播，避免原 Kazumi 的窗口被错误激活、两个应用互斥。
- Windows 安装器 **未配置 Authenticode 代码签名**；Google Drive 现有 Android JKS 不能为 Windows EXE 签名，可能出现 SmartScreen 提示。

## 私有构建（代码已写入）
- Android：`python scripts/private_android_release.py --keys "/PRIVATE/随播_Android_正式签名密钥_20261010.zip" --output-dir "/PRIVATE/SuiboReleases"`
- Windows：`powershell -ExecutionPolicy Bypass -File scripts/build_windows_installer.ps1 -OutputDirectory C:\Private\SuiboReleases`
- Windows 打包实现：`installer/windows/Suibo.iss`，编译完整 `build/windows/x64/runner/Release`，安装时写入正常的 Windows 卸载记录。
- 检查至少包括 EXE、flutter_windows.dll、data/icudtl.dat、flutter_assets；安装器由 Inno Setup 6 构建。
- Windows CI 在临时私有目录构建安装器，尝试静默安装、二次覆盖及卸载；**不使用 upload-artifact，不上传公开 GitHub Releases**。
- 安卓签名报告、Windows 安装报告均记录文件大小、SHA-256、版本、时间；Windows 校验报告还说明是否配置 Authenticode。

## 未完成与禁止夸大
- 2026-10-10 用户明确要求双端**实际安装包**，不能把 GitHub CI 的 Release 可编译称为交付完成。
- 本聊天环境没有 Flutter、Windows C++/Inno Setup、Android SDK，无法直接生成这两个完整二进制安装包；公开 GitHub Actions 也禁止保留或上传安装包。
- 成品实际上传用户私人 Google Drive、安卓旧版覆盖升级、Windows 实机全流程、真实视频播放仍待能够接收**私有产物**的受控构建机验证。
- Windows 真正的“上一安装版→新版升级”必须使用两个不同版本的安装器检验；本轮 CI 两次安装同一版本只验证覆盖行为。
- 若原 Android APK 使用另一签名、另一个 applicationId 或 versionCode 大于 20309，则不能直接覆盖，必须先识别差异，禁止误导用户卸载丢数据。

## 公开仓库安全纪律
- 只提交源代码、配置、测试、日志。**禁止上传 APK、EXE、JKS、key.properties、明文密码和签名 ZIP**。

## 2026-10-10 实际构建与交付审计
- Windows Inno Setup 编译已在 Windows GitHub 构建机实际成功，2.3.8→2.3.9 静默覆盖安装及 Flutter 运行依赖存在性检测执行成功。
- 公开 CI 的静默卸载检查尚未最终通过，已修正为等待卸载进程并获取详细日志；不能将其称为安装器全验收通过。
- 为在聊天中交付安装包，曾尝试只在用户私有构建仓库的隔离临时分支生成短期产物，不修改其主分支、不上传原始 JKS。
- Windows 私有构建编译出完整 EXE，但上传至私有 Actions Artifact 时遭遇账户存储配额耗尽（Failed to CreateArtifact），因此二进制未能传输到聊天文件系统。
- Android 私有 Release 首轮在 GitHub Linux Runner 因 SDK/NDK 占满磁盘失败（No space left on device）；已改为清理无关预装组件后重建 arm64 Release，随后应在本地使用原始 JKS 正式重新签名并验证指纹。
- 在没有经过文件传输、最终签名验证及实际文件存在性检查之前，不得提供伪造的 APK/EXE 下载链接或声称成品已交付。
