# ImagePeek 飞书 Accessibility 适配实施计划

> **供自动化执行者使用：** 使用 `superpowers:executing-plans` 按任务执行，并在真实 Chrome 飞书回归前暂停。

**目标：** 让前台 Chrome 的飞书在线表格当前单元格可复用 ImagePeek 的既有预览能力。

**架构：** `WebSheetAdapter` 限制于 Chrome 的飞书 sheets URL，通过 Accessibility 读取 A1 地址和相邻可编辑文本；运行时把它视为新的 `SpreadsheetApp`，其余管线不变。

**技术栈：** Swift、ApplicationServices、AppKit、XCTest。

**设计依据：** `docs/superpowers/specs/2026-08-25-imagepeek-feishu-accessibility-design.md`

## 约束

- 仅 `com.google.Chrome` 和 `*.feishu.cn/sheets/`。
- 不使用浏览器扩展、JS 注入、剪贴板、OCR 或网页写入。
- 读不到可信文本/页面时返回 nil；不得影响 WPS、Excel 或全局快捷键安全策略。

## 任务 1：网页表格纯逻辑

**文件：** 修改 `ImagePeek/SpreadsheetEngine/SpreadsheetModels.swift`、创建 `ImagePeek/SpreadsheetEngine/WebSheetAdapter.swift`、修改 `ImagePeekTests/SpreadsheetCoreTests.swift`。

- [x] 写失败测试：飞书 Chrome URL 被接受、非飞书 Chrome URL 被拒绝、`E4` 解析为 row 4/column 5、非图片文本被拒绝。
- [x] 运行目标测试确认类型缺失导致失败。
- [x] 最小实现 `SpreadsheetApp.feishuChrome`、URL 安全边界、A1 解析和 Accessibility 值提取接口。
- [x] 重跑目标测试并提交 `1d6850e`（后续运行时接入提交 `9aadaf0`）。

## 任务 2：运行时接入和安全选择策略

**文件：** 修改 `ImagePeek/AppShell/ImagePeekApp.swift`、`ImagePeek/SpreadsheetEngine/ActiveAppDetector.swift`、`ImagePeekTests/SpreadsheetCoreTests.swift`。

- [x] 写失败测试并验证选择事件策略。
- [x] 注入 `WebSheetAdapter` 到 `PreviewRuntimeController`；仅 `.feishuChrome` 调用它。
- [x] 重跑目标测试和完整 XCTest；运行时接入提交 `9aadaf0`。
- [x] 修复真实辅助功能树遍历顺序与 A1 溢出边界，提交 `aca2a1e`、`448cf7e`。

## 任务 3：真实 Chrome 回归与交付

**文件：** 修改 `README.md`、`docs/superpowers/plans/2026-08-25-imagepeek-feishu-accessibility.md`。

- [x] 构建 Release：已验证无签名 Release 构建通过。
- [x] 用户在真实飞书表格中确认图片预览可用；辅助功能诊断曾定位并修复地址与 URL 配对问题。
- [x] 更新 README 平台范围并推送；发布签名仍受 Apple Developer 注册状态限制。
