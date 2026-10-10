# 随播完整版：阶段4 验收与私有交付（2026-10-10）

## 本次 CI
- 与 Android、Windows 相互独立的完整功能回归、Android debug 构建和 Windows release 编译。
- 不公开上传产物，不新建 GitHub Release/Actions Artifact；Android release 正式签名不使用 GitHub 公共 CI。
- 真机及 Windows 实际播放、登录授权、综艺分集/弹幕和同一视频在不同源间切换需安装测试，不能以编译成功替代。
- 验收作品：凡人修仙传、亮剑、大明王朝1566、一饭封神，以及真实可授权的电影/B站录播；要求实际播放并记录结果，不能用假 URL 单测代替。
- 私有签名素材不得写入日志、公开代码、workflow secret 输出。正式签名和上传应在受控的 Windows/Android 构建机完成；确认原有签名和包名一致后再覆盖升级测试。
- 连续包阶段划分：1索引与聚合、2片源/错误、3弹幕关联、4设备与签名。
