# 随播 VOD 弹幕匹配升级记录（2026-10-10）

## 范围
- 保持原 Bangumi 真正作品 ID → 弹弹play → 分集弹幕流程；不修改播放器的弹幕画布、屏蔽或偏移功能。
- 规则视频及 Bangumi 非动画降级路径按作品原名/中文名（最多3个非重复检索词）检索弹弹play。
- 影视作品标题支持常见标点、全角 ASCII、明确第1季/S01/Season 1 等表示；未知季数不猜测第2季及之后。
- 同名候选超过1个或搜索结果截断时拒绝自动匹配。
- 从弹弹play实际分集列表中选择 episodeId；校验“第N集/话/期”与特别版/纯享/加更等类型，日期格式支持 YYYY-MM-DD、YYYY.MM.DD、YYYY年M月D日。
- 无法证明一对一时保留现有手动选源入口，不会以列表第 N 个冒充第 N 集。
- B站 BV/av 视频使用 CID 获取原生弹幕的路径保留，不涉及直播。
- 手动检索界面改用“作品”而不是仅“番剧”。

## 修改文件
- lib/services/danmaku/media_danmaku_service.dart
- lib/pages/video/video_controller.dart
- lib/pages/player/danmaku_source_sheet.dart
- test/services/danmaku/media_danmaku_match_test.dart

## 测试及限制
- 已添加单元测试：标题季数/歧义、分集乱序、日期匹配、加更/纯享版本、电影单集、B站录播识别。
- 环境缺少 Flutter/Dart SDK，**尚未运行 flutter test、flutter analyze、Android/Windows构建**；不得将代码提交视为构建通过。
- 尚未实现“用户手动选择后，持久记住当前视频到弹弹play episodeId 的关联”，现有手动切换功能仍可用。
- 弹弹play不存在对应资源、API拒绝访问或原站不开放弹幕时，仍不能保证一定出现弹幕。
- 不改变任何 API Key 用户设置，也未提交签名材料、APK 或 EXE。
- 官方说明：https://doc.dandanplay.com/open/ ；弹弹play建议用明确的 episodeId 调用 comment API，并对 API 请求和结果做按需缓存。
