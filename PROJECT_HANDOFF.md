# PROJECT_HANDOFF.md

## 0. 文档目的

本文档用于把当前“图片 URL / 本地图片地址 → 表格内浮窗预览”项目，从 ChatGPT 对话阶段完整移交到 Codex 桌面端继续开发。

**Codex 在开始任何实现前，应先完整阅读本文档。不要从 0 重新设计，不要重新发明已经验证过的交互，不要重复踩本文记录的稳定性问题。**

目标本地项目目录：

`/Users/jerry/Documents/AI/Agent/图片浮窗APP设计`

建议后续目录：

```text
图片浮窗APP设计/
├── ImagePeek.xcodeproj
├── ImagePeek/
├── docs/
│   └── PROJECT_HANDOFF.md
├── Prototype/
│   └── wps_url_image_preview_v7_3_safe_performance.lua
└── README.md
```

---

# 1. 项目定位

项目暂名：**ImagePeek**

一句话定位：

> **Instant image preview for spreadsheets.**

核心价值：

用户在表格中选中包含图片 URL 或本地图片路径的单元格时，不打开浏览器、不下载到可见目录、不修改表格内容，直接在表格附近显示图片浮窗，并支持快速浏览、复制图片、全屏查看、固定图片等操作。

目标用户并不局限于 WPS：

- 电商商品图片审核
- AI 数据集检查
- 图片爬虫结果检查
- 商品 SKU 审核
- 服装/面料图片数据检查
- 内容审核
- 图片标注/清洗
- 任何大量图片 URL 存储在表格中的场景

---

# 2. 当前已验证原型

当前原型基于：

- macOS
- Hammerspoon
- Lua
- WPS 表格

原型已经验证了产品需求和交互可行性。

当前最后一个稳定基线：

**V7.3 Safe Performance**

这个版本应被视为“交互基线”和“稳定性基线”。

后续独立 App 的功能迁移，应优先保持 V7.3 的已验证行为，不要随意改变。

---

# 3. 已验证的核心功能

## 3.1 图片来源

支持：

- `http://...`
- `https://...`
- `/Users/.../image.jpg`
- `~/Pictures/image.png`
- `file:///Users/.../image.jpg`

远程图片和本地图片统一进入预览引擎。

## 3.2 自动预览

在 WPS 中：

- 鼠标点击包含图片地址的单元格 → 自动预览
- 使用 `↑ ↓ ← →` → 切换到其他单元格后自动刷新
- `Tab`
- `Enter`
- `PageUp`
- `PageDown`
- `Home`
- `End`

移动到非图片地址单元格时，预览自动隐藏。

离开 WPS 时，预览自动隐藏。

## 3.3 预览位置

当前原型支持：

- 单元格附近
- 屏幕右上角

默认推荐：

**单元格附近**

定位逻辑：

1. 优先尝试通过 Accessibility 获取当前单元格坐标
2. 如果能拿到可信的小尺寸 `AXFrame`，放在单元格右侧
3. 右侧空间不足时自动放左侧
4. 如果拿不到准确单元格坐标，则退回最近一次鼠标点击位置附近
5. 自动避免预览框超出屏幕边界

独立 App 应保留这一逻辑，但使用原生 `NSPanel` 实现。

---

# 4. 已验证快捷键与交互

## 4.1 Esc

`Esc`

行为：

> 只隐藏“当前这一次”预览窗口，不关闭自动预览功能。

之后只要：

- 点击其他单元格
- 使用方向键移动
- Tab / Enter 切换单元格

如果新单元格是图片地址，预览会再次出现。

重要：

**Esc 不能变成“关闭插件”或“暂停自动预览”。**

## 4.2 Space

`Space`

行为：

- 小窗 → 大图
- 大图 → 小窗

V7.1 曾修复一个关键 bug：

如果只在 `keyUp` 处理 Space，那么 `keyDown` 已经传给 WPS，会导致单元格被空格修改甚至看起来像内容被清空。

因此独立 App 必须：

- 只在“当前确实有图片预览上下文”时接管 Space
- 在接管时完整阻止 Space 传给表格应用
- 没有图片预览时，不拦截 Space

独立 App 建议不使用全局裸键监听，改用“目标表格应用激活 + 当前预览存在”条件化快捷键处理。

## 4.3 Option + C

`⌥C`

行为：

> 将当前实际图片写入系统剪贴板。

复制的是图片像素数据，不是 URL 文本。

用户之后可以：

- `⌘V` 粘贴到微信
- 飞书
- PPT
- Photoshop
- 任何支持图片剪贴板的应用

这是核心功能之一。

## 4.4 Option + O

`⌥O`

行为：

- 当前为远程图片 → 打开原始 URL
- 当前为本地图片 → 用系统默认应用打开文件

## 4.5 Option + R

`⌥R`

行为：

仅对本地图片有效：

> 在 Finder 中显示当前图片文件。

## 4.6 Option + P

`⌥P`

当前 Safe 版本建议行为：

> 固定 / 取消固定当前图片。

固定图：

- 独立显示第二个预览窗口
- 继续移动表格时，固定图不变化
- 用于和下一行/下一张图对比

**现阶段不要实现鼠标拖动固定窗口。**

原型中“拖动固定窗口”导致严重系统级输入问题，详见后文。

独立 App 后续如果要支持拖动，应使用原生 `NSWindow` / `NSPanel` 自带窗口移动能力，例如标题栏或 `isMovableByWindowBackground`，绝不能通过全局鼠标 eventtap 模拟拖动。

---

# 5. 图片缩放

V7.3 Safe Performance 的安全方向：

- 鼠标位于预览窗口内部时滚轮缩放
- 最小：50%
- 最大：500%

独立 App 中不要使用系统级 `scrollWheel eventtap`。

建议直接让预览窗口内部的：

- `NSScrollView`
- `NSView`
- 或自定义图片容器

处理滚轮缩放。

要求：

- 鼠标不在预览窗口时，不影响系统滚轮
- 不拦截全局鼠标点击
- 不拦截全局拖动

---

# 6. 图片底部信息

V7.3 已支持显示像素尺寸和加载来源。

推荐正常 UI：

`900×1200 · OSS缩略图 · 183ms`

或：

`1340×1785 · 网络 · 205ms`

调试模式可显示详细性能：

`取值 30ms · 网络 170ms · 解码 5ms · 总计 205ms`

性能实测：

- 当前单元格取值：约 30ms
- 网络：约 170ms
- 解码：个位数 ms
- 总体：约 200ms

结论：

**当前真正瓶颈通常是网络，不是单元格读取，也不是图片解码。**

因此不要为了把 30ms 降到 20ms 做激进、危险的 Accessibility 或输入事件优化。

---

# 7. 图片加载与性能

## 7.1 当前加载链路

远程图片：

```text
当前单元格
→ 读取文本
→ 判断远程 URL
→ 缓存查询
→ 网络请求
→ 图片解码
→ 显示
→ 下一事件循环补尺寸信息
```

本地图片：

```text
当前单元格
→ 读取路径
→ 文件存在性检查
→ 本地解码
→ 显示
```

## 7.2 当前缓存策略

原型：

- 内存缓存：最近 200 张
- 磁盘缓存：7 天
- 缓存目录：
  `~/Library/Caches/WPSURLImagePreview`

独立 App 建议升级为：

- 内存 LRU：约 200 张
- 磁盘缓存：
  - 最大约 1GB
  - 最长 30 天
  - 双条件淘汰
- 缓存 Key：
  `原始 URL + 优化规则版本`

这样 CDN 优化逻辑升级时不会误用旧缓存。

---

# 8. CDN 优化

当前已验证阿里云 OSS 规则。

对满足以下条件的公开 OSS URL：

- host 包含 `.aliyuncs.com`
- 没有已有 `x-oss-process`
- 没有签名相关参数

优先请求：

`?x-oss-process=image/resize,l_900`

目的：

让 OSS 服务端返回最长边约 900px 的预览图，而不是原图。

如果失败：

> 自动回退原 URL。

如果 URL 带常见签名参数，例如：

- `OSSAccessKeyId`
- `Signature`
- `x-oss-signature`
- `x-oss-credential`
- `x-oss-security-token`
- `x-oss-expires`

不要擅自修改 URL。

当前也遇到过：

`img.kwcdn.com`

但没有可靠公开资料确认其动态缩放 URL 规则。

原则：

> **不知道 CDN 的合法缩略图参数时，不要猜。**

独立 App 设计：

```text
CDNOptimizer
├── AliyunOSSRule
├── GenericRule
└── FutureRules
```

以后增加某个 CDN，只新增 Rule，不改 ImageLoader。

---

# 9. V7.3 Safe Performance 脚本逻辑摘要

## 9.1 当前单元格读取

WPS 原型读取策略：

1. 监听用户在 WPS 内：
   - 点击
   - 方向键
   - Tab / Enter 等导航
2. 触发轻量延迟
3. 保存系统剪贴板
4. 模拟 `Cmd+C`
5. 轮询 `pasteboard.changeCount`
6. 最多等待约 350ms
7. 获取当前单元格文本
8. 恢复原剪贴板
9. 判断是否为图片地址
10. 加载图片

注意：

Clipboard fallback 必须：

- 保存用户剪贴板
- 恢复用户剪贴板
- 有严格超时
- 超时后直接放弃本次，不无限重试

## 9.2 性能诊断

V7.3 把耗时拆成：

- `cellMs`
- `networkMs`
- `decodeMs`
- `totalMs`

远程首次加载：

`900×1200 · OSS缩略图 · 取值 24ms · 网络 138ms · 解码 12ms · 总计 174ms`

缓存：

`900×1200 · 内存缓存 · 取值 22ms · 内存缓存 1ms · 总计 23ms`

本地：

`1600×2400 · 本地 · 取值 21ms · 本地解码 15ms · 总计 36ms`

## 9.3 图片优先显示

V7.3 的一个性能优化：

> 先把图片交给 Canvas 显示，再在下一个 event-loop tick 补像素尺寸和性能文本。

因此：

像素尺寸等元数据不能阻塞首次出图。

独立 App 也应沿用：

- 主线程尽快更新图片
- metadata / diagnostics 可延迟更新

---

# 10. 已踩过的严重坑：必须避免

这是整个项目最重要的稳定性记录。

## 10.1 V8.x 系列问题

曾经尝试给“固定图片窗口”增加鼠标拖动。

实现方式涉及：

- 全局 `leftMouseDown`
- 全局 `leftMouseUp`
- 全局 `leftMouseDragged`
- eventtap 返回 `true`
- 吞掉鼠标事件
- Canvas 鼠标事件
- 鼠标穿透处理

结果出现严重问题：

> 软件运行一段时间后，macOS 鼠标仍然能移动，但所有窗口按钮都无法点击，整台电脑像“卡死”一样。

原因高度疑似：

某个全局鼠标 eventtap 进入异常状态，持续吞掉点击事件。

恢复方式：

`killall Hammerspoon`

后系统点击恢复。

## 10.2 强制安全原则

独立 App **绝对禁止**采用类似逻辑：

- 不要全局吞 `mouseDown`
- 不要全局吞 `mouseUp`
- 不要全局吞 `mouseDragged`
- 不要自己模拟一个系统级可拖动 Canvas
- 不要通过全局裸字母键做快捷键
- 不要让单独 `P` 键成为全局快捷键
- 不要用 `Space keyUp` 才阻断 Space

独立 App 如果需要拖动窗口：

> 只能使用原生 `NSWindow / NSPanel` 的窗口移动能力。

---

# 11. 独立 App 产品范围

## 11.1 平台顺序

产品总范围按 A 方案：

首版设计支持：

1. WPS
2. Microsoft Excel
3. 飞书在线表格

但实现顺序：

### Phase 1
先把：

- WPS
- Microsoft Excel

做好。

### Phase 2
再做：

- 飞书在线表格

### Phase 3
未来可增加：

- 钉钉在线表格
- Google Sheets
- Apple Numbers
- 其他网页表格

---

# 12. macOS 版本

最低支持：

**macOS 13 Ventura+**

---

# 13. App 形态

确认采用：

> **菜单栏常驻 App**

特点：

- 不常驻 Dock
- 顶部菜单栏一个图片图标
- 设置页需要时打开
- 可选“登录时自动启动”
- WPS / Excel 打开并激活时自动工作
- 离开表格软件后自动进入空闲状态
- 不需要用户手动开启插件

---

# 14. 技术栈

推荐：

- Swift
- AppKit 为主
- SwiftUI 用于设置页
- `NSPanel` 用于浮动预览窗
- `URLSession` 用于网络图片加载
- `NSCache` / 自定义 LRU 用于内存缓存
- 文件系统用于磁盘缓存
- macOS Accessibility API 用于跨应用读取
- Clipboard 作为 fallback

不要继续依赖：

- Hammerspoon
- Lua
- Homebrew
- 外部脚本运行环境

最终用户只安装：

`ImagePeek.app`

---

# 15. 总体架构

```text
ImagePeek.app
│
├── AppShell
│   ├── MenuBarController
│   ├── SettingsWindow
│   ├── LaunchAtLogin
│   └── PermissionManager
│
├── SpreadsheetEngine
│   ├── ActiveAppDetector
│   ├── SpreadsheetAdapter protocol
│   ├── WPSAdapter
│   ├── ExcelAdapter
│   └── WebSheetAdapter        // Phase 2
│
├── PreviewEngine
│   ├── FloatingPreviewWindow
│   ├── FullscreenPreview
│   ├── PinPreview
│   └── HotkeyManager
│
├── ImageEngine
│   ├── ImageSourceResolver
│   ├── RemoteImageLoader
│   ├── LocalImageLoader
│   ├── CDNOptimizer
│   ├── MemoryCache
│   └── DiskCache
│
└── Diagnostics
    ├── PerformanceMetrics
    └── ErrorLog
```

---

# 16. Adapter 统一接口

核心思想：

> “读取单元格”和“显示图片”彻底分离。

建议统一模型：

```swift
struct CellContext {
    let text: String
    let frame: CGRect?
    let app: SpreadsheetApp
    let row: Int?
    let column: Int?
}
```

建议 Adapter 协议：

```swift
protocol SpreadsheetAdapter {
    var app: SpreadsheetApp { get }

    func isAvailable() -> Bool
    func currentCell() async -> CellContext?
}
```

能力模型：

```swift
struct AdapterCapability {
    let canReadTextDirectly: Bool
    let canReadCellFrame: Bool
    let canReadRowColumn: Bool
    let needsClipboardFallback: Bool
}
```

Core 不应该猜每个平台能做什么。

---

# 17. WPSAdapter 设计

优先级：

1. Accessibility 读取当前焦点元素
2. 尝试：
   - AXValue
   - AXTitle
   - AXDescription
   - AXFrame
3. 如果能直接拿文本，则不使用剪贴板
4. 如果拿不到文本：
   - 保留 AXFrame
   - 使用一次 Clipboard fallback
5. Clipboard fallback：
   - 保存原剪贴板
   - 模拟 Cmd+C
   - 最大等待 150–300ms
   - 获取后恢复剪贴板
   - 失败就放弃本次，不重试风暴

---

# 18. ExcelAdapter 设计

Microsoft Excel 必须独立适配，不允许假设和 WPS 行为一致。

优先：

1. Accessibility
2. 如果 Excel 暴露更稳定单元格对象：
   - 直接读取 value
   - frame
   - row/column
3. 如果 Accessibility 不够：
   - 研究 Excel AppleScript / Office Automation
   - 作为 Adapter 内部 fallback
4. 最后才考虑剪贴板 fallback

对用户：

仍然只有一个 App，不要求安装 Excel Add-in。

---

# 19. WebSheetAdapter 设计

Phase 2。

目标：

飞书在线表格。

浏览器环境：

- Chrome
- Safari
- Edge

读取策略：

1. 尝试浏览器 Accessibility
2. 如果网页内部单元格可暴露：
   - 直接读取当前单元格
3. 如果飞书使用 Canvas / 虚拟化表格，Accessibility 无法读取：
   - 再考虑浏览器扩展 / 注入桥接
4. WebSheetAdapter 只负责输出 `CellContext`
5. 后续：
   - 钉钉
   - Google Sheets
   都应复用 WebSheetAdapter 基础设施

---

# 20. 自动识别与指定图片列

确认产品行为：

默认：

> 任何合法图片 URL / 本地图片路径都自动预览。

高级设置：

> 可以指定哪些列是图片列。

例如：

- 仅 G 列
- G + K
- 多列

目的：

- 减少无关监听
- 大表性能更好
- 未来有利于安全预取

---

# 21. PreviewEngine

推荐：

`NSPanel`

特点：

- 浮动
- 不抢表格应用焦点
- 可置于当前 Space
- 不需要全局鼠标 eventtap

功能：

- 小窗
- 大图
- 固定图
- 缩放
- 底部信息
- 错误状态

---

# 22. 快捷键安全模型

只在以下条件同时满足时启用：

- 当前激活应用是受支持表格应用
- 当前有有效图片上下文
- 当前不是普通文本编辑状态，或快捷键不会影响输入

建议：

- `Esc`
- `Space`
- `⌥C`
- `⌥O`
- `⌥R`
- `⌥P`

禁止：

- 单独 P
- 单独普通字母键
- 永久吞系统键盘事件

---

# 23. 权限模型

首版尽量只申请：

### 必须
Accessibility

用于：

- 读取当前焦点
- 单元格位置
- 必要时触发复制

### 不需要
屏幕录制

项目不是通过截图 OCR 识别单元格。

### 剪贴板
只作为 fallback。

原则：

- 保存
- 使用
- 恢复
- 严格超时
- 不污染用户剪贴板

---

# 24. ImageEngine

```text
ImageEngine
├── ImageSourceResolver
├── RemoteImageLoader
├── LocalImageLoader
├── CDNOptimizer
└── ImageCache
```

---

# 25. ImageSourceResolver

识别：

- HTTP
- HTTPS
- file://
- ~/
- /
- 无效文本

Adapter 不负责判断图片地址是否合法。

---

# 26. RemoteImageLoader

使用：

`URLSession`

要求：

- async
- 不阻塞主线程
- 当前图请求优先
- 快速换单元格时取消旧请求
- 旧请求完成后不得覆盖当前图片

---

# 27. LocalImageLoader

直接读取本地文件。

常见格式：

- JPEG
- PNG
- WebP
- HEIC
- TIFF

失败时：

预览框内显示错误，不弹系统 Alert。

---

# 28. 错误处理

例如：

`图片加载失败 · HTTP 403`

`图片不存在`

`无法解码`

`URL 已失效`

连续浏览过程中：

**禁止弹系统 Alert 打断用户。**

---

# 29. 设置页

建议设置项：

## General
- 自动预览
- 登录时启动
- 预览位置
  - 单元格附近
  - 屏幕右上角

## Spreadsheet
- 自动识别图片地址
- 指定图片列
- WPS 开关
- Excel 开关
- Web Sheet 开关（Phase 2）

## Preview
- 默认窗口尺寸
- 最小缩放 50%
- 最大缩放 500%
- 是否显示像素尺寸
- 是否显示加载来源
- 性能诊断

## Cache
- 最大磁盘缓存
- 最长保留时间
- 清理缓存

## Shortcuts
- Esc
- Space
- ⌥C
- ⌥O
- ⌥R
- ⌥P

---

# 30. 分发路线

不建议第一版直接冲 Mac App Store。

推荐：

1. Developer ID 签名
2. Apple Notarization
3. DMG / ZIP
4. 官网 / 第三方 Mac 工具平台销售

原因：

项目依赖跨应用 Accessibility，外部分发更适合首版。

未来稳定后再评估 Mac App Store Sandbox。

---

# 31. 商业模式建议

更适合：

**一次性买断**

而不是订阅。

例如：

- Free
- Pro $9.99 / $14.99 / $19.99

未来可根据功能调整。

---

# 32. Phase 1 实施目标

优先完成：

## Native Spreadsheet MVP

平台：

- WPS
- Microsoft Excel

功能：

- 菜单栏 App
- Accessibility 权限引导
- 当前应用识别
- 当前单元格读取
- 图片 URL / 本地路径
- 单元格附近预览
- OSS 优化
- 内存 / 磁盘缓存
- Esc
- Space
- ⌥C
- ⌥O
- ⌥R
- ⌥P
- 50%–500% 缩放
- 性能诊断
- 指定图片列
- 登录时启动

---

# 33. Phase 2

飞书在线表格。

目标：

浏览器当前页面 → 当前单元格 → `CellContext`

如果 Accessibility 能做：

优先 Accessibility。

如果不能：

再设计 Web Extension / JS Bridge。

---

# 34. Phase 3

可能加入：

- 钉钉在线表格
- Google Sheets
- Numbers

---

# 35. 给 Codex 的第一阶段执行要求

Codex 开始时：

1. 完整阅读本文档
2. 不要从 0 重新设计
3. 不要立刻实现全部功能
4. 先建立原生 macOS 项目骨架
5. 先跑通菜单栏 App
6. 再做 PermissionManager
7. 再做 ActiveAppDetector
8. 再做 WPSAdapter
9. WPS 稳定后再做 ExcelAdapter
10. 不要提前开发飞书

建议第一轮任务：

> 在 `/Users/jerry/Documents/AI/Agent/图片浮窗APP设计` 中创建 macOS 13+ 的 ImagePeek 原生菜单栏应用。技术栈 Swift + AppKit 为主，SwiftUI 用于设置页。严格按照 PROJECT_HANDOFF.md 的架构建立项目骨架。第一轮只要求：项目可编译运行、菜单栏图标、Settings 窗口、PermissionManager、SpreadsheetAdapter protocol、WPSAdapter/ExcelAdapter 空实现、ImageEngine/PreviewEngine 基础目录和类型。不要一次性实现所有功能。

---

# 36. Codex 必须遵守的禁止事项

## 禁止
- 全局吞 mouseDown
- 全局吞 mouseUp
- 全局吞 mouseDragged
- 用系统级 eventtap 模拟拖动窗口
- 裸字母键作为全局快捷键
- 用 OCR 作为主方案
- 因为一个 Adapter 失败就把逻辑塞进 Core
- 用浏览器打开 URL 作为默认预览
- 修改表格内容来实现预览
- 在用户无操作时不断模拟 Cmd+C
- 无超时的剪贴板轮询
- 主线程网络请求
- 旧网络请求覆盖新单元格图片

## 强制
- Adapter 隔离
- 图片加载与单元格读取隔离
- 网络异步
- 错误不打断连续浏览
- Clipboard fallback 可恢复
- 所有权限明确
- macOS 13+
- 安全优先于极限性能

---

# 37. 当前决策总结

已确认：

- 产品名暂定 ImagePeek
- 做独立 macOS App
- macOS 13+
- 菜单栏常驻
- 不常驻 Dock
- Swift + AppKit
- SwiftUI 设置页
- Phase 1：WPS + Excel
- Phase 2：飞书
- Phase 3：钉钉 / Google Sheets / Numbers
- 默认自动识别图片地址
- 高级支持指定图片列
- Accessibility 优先
- Clipboard fallback
- 不使用 Hammerspoon 作为最终产品
- 保留当前稳定交互
- 不再做危险鼠标全局拦截
- V7.3 Safe Performance 是当前原型稳定基线

---

# 38. 最后的开发原则

这个项目已经证明：

> 功能容易加，稳定性更重要。

尤其是跨应用、键盘、鼠标、Accessibility 这种系统级辅助工具。

因此后续任何新功能都必须问：

1. 会不会影响系统输入？
2. 会不会抢用户焦点？
3. 会不会污染剪贴板？
4. 会不会阻塞主线程？
5. 会不会让某个平台的特殊逻辑污染 Core？
6. 失败时能否安全退回？

原则：

> **宁可某次图片不弹，也不能让用户的 Mac 操作失效。**
