# ImagePeek 分阶段开发路线图

> 本路线图严格继承 `PROJECT_HANDOFF.md`。每个阶段完成后都必须通过对应测试与安全检查，再进入下一阶段。

## 模型选择原则

- **Luna**：确定性强、边界清晰、可用纯函数或单元测试证明结果的任务。
- **Terra**：跨应用 Accessibility、并发取消/缓存一致性、AppKit 输入安全、真实环境回归和签名发布任务。
- 不以模型“最强”为默认依据；如果 Luna 可以达到相同结果，就使用 Luna。

## 阶段拆分

| 阶段 | 工作内容 | 推荐模型 | 完成标准 |
| --- | --- | --- | --- |
| 0 | 分支、基线、测试工具和权限检查 | Luna | 工作区干净、基线测试通过、约束清单可追溯 |
| 1 | WPS Accessibility 只读 Adapter | Terra | 文本与可信 Frame 可读；Clipboard fallback 有超时、保存/恢复；失败安全返回 |
| 2 | ActiveAppDetector 与导航状态机 | Luna | 点击、方向键、Tab/Enter 等事件只转换为可测试状态，不做全局吞事件 |
| 3 | ImageSourceResolver 与 Aliyun OSS Rule | Luna | HTTP/HTTPS、本地路径、file URL 正确识别；未知 CDN 不改 URL |
| 4 | URLSession 加载与请求取消 | Terra | 当前请求优先；旧请求取消或完成后不能覆盖新单元格图片 |
| 5 | 内存 LRU 与磁盘缓存 | Terra | 约 200 张内存 LRU；磁盘 1GB/30 天双条件淘汰；异常不阻塞预览 |
| 6 | NSPanel 预览与缩放 | Terra | 单元格附近定位、边界回退、50%–500% 缩放；不抢焦点、不接管全局滚轮 |
| 7 | Excel Adapter | Terra | Accessibility 优先；必要时 Adapter 内部 AppleScript fallback；不污染 Core |
| 8 | 安全快捷键与固定图 | Terra | 只在支持应用+有效图片上下文时接管；禁止全局鼠标吞事件和裸字母键 |
| 9 | 设置持久化、图片列和登录启动 | Luna | 设置可持久化、默认值稳定、列过滤不改变 Adapter 边界 |
| 10 | WPS/Excel 真实回归与性能诊断 | Terra | 连续浏览、错误恢复、剪贴板恢复、性能指标和安全约束通过验收 |
| 11 | Developer ID、Notarization、DMG/ZIP | Terra | 可重复构建、签名、Notarization 和安装说明完整 |

## 当前执行策略

当前从阶段 1 开始。每个阶段都遵循：

1. 创建或更新该阶段的测试；
2. 运行测试确认失败原因属于缺少目标行为；
3. 写最小实现；
4. 运行完整测试和安全扫描；
5. 创建独立提交并推送；
6. 在进入下一阶段前报告使用的推荐模型、变更、验证结果和剩余风险。
