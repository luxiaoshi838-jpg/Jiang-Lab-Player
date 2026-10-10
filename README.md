# 随播 · Suibo

Windows PC 与 Android 综合影视播放器（基于 [Kazumi](https://github.com/Predidit/Kazumi) 的独立改造版）。

- 平台：Windows 10/11、Android
- 动漫：保留 Bangumi 元数据与原有播放机制
- 综合影视：通过用户安装且有权访问的规则搜索电影、电视剧、综艺与纪录片
- 规则与解析：复用 Kazumi 的 XPath/API 规则引擎和播放器
- Android 应用 ID：`com.jianglab.suibo`（与 Kazumi 分开安装）
- Android 正式签名：私钥、密码仅在私有 Google Drive 的“签名文件”文件夹保管，不进入本公开仓库。

## 首次导入源码

`.github/workflows/bootstrap.yml` 会从指定的 Kazumi 上游提交复制源代码，执行 `scripts/prepare_suibo.py` 的品牌及综合搜索入口改造，再分别构建 Android 与 Windows。首次导入完成后全部源码会留在这个仓库，而不只是一个引用。

## 签名安全

绝不提交 `*.jks`、`*.keystore`、`key.properties`、签名密码或发布令牌。无签名凭据时 Android CI 仅生成 debug APK；正式 release APK 须在受控环境传入签名凭据进行构建。

## 授权

改造自 Kazumi；保留上游版权和 GPL-3.0 许可证，分发时遵守 GPL-3.0 条款。本项目不提供盗版片源或绕过 DRM 的功能。