# 随播 · Suibo

Windows PC 与 Android 综合影视播放器（基于 [Kazumi](https://github.com/Predidit/Kazumi) 的独立改造版）。

- 平台：Windows 10/11、Android
- 动漫：保留 Bangumi 元数据与原有播放机制
- 综合影视：通过用户安装且有权访问的规则搜索电影、电视剧、综艺与纪录片
- 规则与解析：复用 Kazumi 的 XPath/API 规则引擎和播放器
- Android 应用 ID：`com.jianglab.suibo`（与 Kazumi 分开安装）
- Android 正式签名：私钥、密码仅在私有 Google Drive 的“签名文件”文件夹保管，不进入本公开仓库。

## 功能与界面原则

**保留 Kazumi 原有功能与布局**：推荐、时间表、追番、我的四个导航项不变，不新增单独影视页。原搜索框同时查找动画、电影、电视剧、纪录片和综艺；原搜索卡片、详情页、播放器、进度记录和追番书架直接复用。

- Bangumi 搜索包括动画（类型 2）与三次元（类型 6），有档案的影视条目可使用原封面、评分与详情。
- 普通关键词还会依次搜索用户已经安装的资源规则。没有 Bangumi 档案但规则能检索到的影片，也显示在原搜索结果中并可以加入原追番书架。
- 规则返回结果只有片名和地址时不虚构海报、评分或简介，原卡片显示默认图；分组筛选条件只作用于可被 Bangumi 元数据检索的条目。
- 规则来源的作品保留原来源地址，观看时可找回；仅保存在本地/WebDAV，不传到 Bangumi 动画账户。
- 不保证所有平台或 DRM/需要授权的视频可播放。

## 首次导入源码

`.github/workflows/bootstrap.yml` 会从指定的 Kazumi 上游提交复制源代码，执行 `scripts/prepare_suibo.py` 的品牌与平台适配，再分别构建 Android 与 Windows。首次导入完成后全部源码会留在这个仓库，而不只是一个引用。

## 签名安全

绝不提交 `*.jks`、`*.keystore`、`key.properties`、签名密码或发布令牌。无签名凭据时 Android CI 仅生成 debug APK；正式 release APK 须在受控环境传入签名凭据进行构建。

## 授权

改造自 Kazumi；保留上游版权和 GPL-3.0 许可证，分发时遵守 GPL-3.0 条款。本项目不提供盗版片源或绕过 DRM 的功能。