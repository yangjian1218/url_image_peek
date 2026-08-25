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

- [ ] 写失败测试：飞书 Chrome URL 被接受、非飞书 Chrome URL 被拒绝、`E4` 解析为 row 4/column 5、非图片文本被拒绝。
- [ ] 运行 `xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ImagePeekTests/SpreadsheetCoreTests`，确认类型缺失导致失败。
- [ ] 最小实现 `SpreadsheetApp.feishuChrome`、`WebSheetURLPolicy.isSupported(_:)`、`A1CellReference.parse(_:)` 和 `WebSheetAdapter` 的 Accessibility 值提取接口；输出现有 `CellContext`。
- [ ] 重跑目标测试，确认通过；提交 `feat: add Feishu web sheet adapter`。

## 任务 2：运行时接入和安全选择策略

**文件：** 修改 `ImagePeek/AppShell/ImagePeekApp.swift`、`ImagePeek/SpreadsheetEngine/ActiveAppDetector.swift`、`ImagePeekTests/SpreadsheetCoreTests.swift`。

- [ ] 写失败测试：前台飞书 Chrome 的鼠标释放和方向键释放触发读取；离开 Chrome 或 URL 不匹配时隐藏预览。
- [ ] 运行 SpreadsheetCoreTests，确认失败。
- [ ] 注入 `WebSheetAdapter` 到 `PreviewRuntimeController`；仅 `.feishuChrome` 调用它；保留 WPS/Excel 原有分支。无 frame 时传既有鼠标回退点。
- [ ] 重跑目标测试和完整 XCTest；提交 `feat: preview Feishu sheet image cells`。

## 任务 3：真实 Chrome 回归与交付

**文件：** 修改 `README.md`、`docs/superpowers/plans/2026-08-25-imagepeek-feishu-accessibility.md`。

- [ ] 构建 Release：`xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -configuration Release CODE_SIGNING_ALLOWED=NO build`。
- [ ] 在用户真实飞书表格中验证鼠标点击/方向键、退出飞书隐藏预览、Esc/Space/⌥C/⌥O/⌥P；不通过则停止并进行系统化调试。
- [ ] 记录人工验证结论、更新 README 平台范围、提交并推送。
