# ImagePeek 飞书在线表格 Accessibility 适配设计

## 目标

在 Chrome 中为飞书在线表格提供当前单元格图片 URL 预览，并复用既有的 ImagePeek 图片加载、缓存、浮窗和快捷键功能。

## 已验证事实

在实际飞书在线表格中，Chrome Accessibility 树公开了当前选区地址（例如 `E4`）和完整单元格文本。按方向键切换到 `E5` 后，两个值同步更新；返回上一个单元格也正确恢复。因此首版不需要浏览器扩展、JS Bridge 或剪贴板读取。

## 范围

- 支持前台 Chrome 中 `*.feishu.cn/sheets/` 页面。
- 读取当前单元格地址与文本，输出现有 `CellContext`。
- 鼠标点击和方向键释放后刷新当前选择。
- 无可靠单元格 frame 时以当前鼠标位置作为浮窗定位回退。

不支持 Safari、Edge、飞书文档、浏览器扩展、网页脚本注入、剪贴板 fallback、网页数据写入和其他在线表格平台。

## 架构

新增 `WebSheetAdapter`，其可用性由前台应用 bundle ID `com.google.Chrome` 和窗口 URL 同时限制。它从 Chrome 的 Accessibility 元素树中寻找当前单元格地址文本字段和其相邻的可编辑文本区域。地址使用 `A1` 格式解析为行/列；文本必须通过现有 `ImageSourceResolver` 验证为 HTTP/HTTPS URL 或本地路径后才输出。

`ActiveAppDetector` 扩展为可识别 `SpreadsheetApp.feishuChrome`。`PreviewRuntimeController` 仅在该 app 前台时调用 `WebSheetAdapter`。既有 WPS 与 Excel Adapter 不依赖 WebSheetAdapter，也不共享网页特定读取逻辑。

## 安全与错误处理

- 只在 Chrome 前台并且当前页面 URL 匹配飞书表格域名/路径时读取 Accessibility；其他标签、网站和浏览器均安全返回 nil。
- 搜索不到地址、文本、URL 或可信 frame 时不尝试模拟复制，不修改飞书内容，不显示系统 Alert。
- 无 cell frame 时用鼠标位置定位；不会从屏幕截图、OCR 或网页 DOM 猜测单元格坐标。
- 既有条件快捷键只在有效图片预览上下文工作；新增平台不会放宽全局输入拦截。

## 测试

- 纯函数测试：Chrome/飞书 URL 分类、A1 地址解析、受支持域名限制和非图片文本拒绝。
- Adapter 单元测试：模拟 Accessibility 值，验证只在前台飞书 Chrome 且可信文本存在时返回 `CellContext`。
- 回归测试：WPS 与 Excel 分类/选择策略保持不变。
- 人工回归：Chrome 飞书中鼠标点击与方向键选择图片 URL，确认预览、Esc、Space 和 Option 快捷键；离开飞书标签或 Chrome 后确认浮窗消失。
