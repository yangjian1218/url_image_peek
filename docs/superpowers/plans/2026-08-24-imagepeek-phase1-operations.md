# ImagePeek Phase 1 运营能力实施计划

> **供自动化执行者使用：** 必须使用 `superpowers:executing-plans` 按任务逐项执行；步骤使用复选框追踪。

**目标：** 为已验证的 WPS/Excel 图片预览增加隐私保护的会话诊断、可管理的 ImagePeek 缓存和相关设置，而不改变读取、权限和快捷键行为。

**架构：** 设置模型提供缓存和标题配置；`RemoteImageLoader` 与 `DiskImageCache` 输出缓存/加载信息；运行时将匿名结果聚合到主线程状态，供设置窗口读取。预览面板根据设置组合像素尺寸与加载来源标题。

**技术栈：** Swift 5、AppKit、SwiftUI、Foundation、XCTest、Swift actor。

**设计依据：** `docs/superpowers/specs/2026-08-24-imagepeek-phase1-operations-design.md`

## 全局约束

- macOS 13 Ventura+；仅前台 WPS 或 Excel 可触发读取。
- 不修改表格内容；不新增裸字母快捷键；不吞无关鼠标或键盘输入。
- 诊断不保存 URL、本地路径、单元格文本、剪贴板文本、图片数据或跨会话历史。
- 缓存清理只能操作 ImagePeek 自己的缓存目录，不弹系统 Alert。
- 旧版设置缺少新字段时必须采用安全默认值。
- 不暂存 `ImagePeek.xcodeproj/project.xcworkspace/xcuserdata/`。

## 文件结构

| 文件 | 修改目的 |
| --- | --- |
| `ImagePeek/AppShell/AppSettings.swift` | 设置、缓存策略、诊断模型与共享状态。 |
| `ImagePeek/ImageEngine/DiskImageCache.swift` | 缓存摘要和严格限定目录的清理。 |
| `ImagePeek/ImageEngine/RemoteImageLoader.swift` | 缓存策略和清理入口。 |
| `ImagePeek/AppShell/ImagePeekApp.swift` | 聚合加载结果并注入状态。 |
| `ImagePeek/PreviewEngine/PreviewEngine.swift` | 可配置预览标题。 |
| `ImagePeek/AppShell/SettingsView.swift` | Preview、Cache、Diagnostics 区域。 |
| `ImagePeekTests/ImageEngineTests.swift` | 缓存测试。 |
| `ImagePeekTests/PreviewEngineTests.swift` | 设置、诊断、标题测试。 |

## 任务 1：设置策略和诊断纯逻辑

**文件：** 修改 `ImagePeek/AppShell/AppSettings.swift`、`ImagePeekTests/PreviewEngineTests.swift`。

**产生接口：** `CachePolicy(byteLimit:maximumAge:)`、`RuntimeDiagnosticResult`、`RuntimeDiagnosticsSnapshot`、`RuntimeDiagnostics.record(_:)`、`ImagePeekSettings.cachePolicy`。

- [ ] **步骤 1：写失败测试。**

```swift
func testSettingsDecodeMissingOperationsFieldsWithSafeDefaults() throws {
    let data = Data(#"{"automaticPreview":true,"launchAtLogin":false,"wpsClipboardFallback":true}"#.utf8)
    let settings = try JSONDecoder().decode(ImagePeekSettings.self, from: data)
    XCTAssertTrue(settings.showsPixelDimensions)
    XCTAssertFalse(settings.showsLoadSource)
    XCTAssertEqual(settings.cachePolicy.byteLimit, 1_073_741_824)
}

func testDiagnosticsDoesNotCountCancellationAsFailure() {
    var diagnostics = RuntimeDiagnostics()
    diagnostics.record(.success(source: .memoryCache, elapsed: 0.012))
    diagnostics.record(.cancelled)
    XCTAssertEqual(diagnostics.snapshot.memoryCacheHitCount, 1)
    XCTAssertEqual(diagnostics.snapshot.failureCount, 0)
}
```

- [ ] **步骤 2：确认测试失败。**

运行：`xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ImagePeekTests/PreviewEngineTests`

预期：因新增字段和类型尚不存在而编译失败。

- [ ] **步骤 3：最小实现。** 新增 `showsPixelDimensions = true`、`showsLoadSource = false`、`cacheSizeGiB = 1`、`cacheRetentionDays = 30`。`cachePolicy` 将容量限制为 1...10 GiB、保留期限制为 1...365 天；无效值回退默认值。诊断只保留 network/disk/memory/local 成功数、失败数和最近结果，禁止加入 URL 或图片字段。

```swift
struct CachePolicy: Equatable, Sendable {
    static let defaultByteLimit = 1_073_741_824
    let byteLimit: Int
    let maximumAge: TimeInterval
}
```

- [ ] **步骤 4：确认通过并提交。**

运行与步骤 2 相同的命令，预期通过；然后执行：

```zsh
git add ImagePeek/AppShell/AppSettings.swift ImagePeekTests/PreviewEngineTests.swift
git commit -m "feat: add operations settings and diagnostics model"
```

## 任务 2：磁盘缓存摘要、清理与策略应用

**文件：** 修改 `ImagePeek/ImageEngine/DiskImageCache.swift`、`ImagePeek/ImageEngine/RemoteImageLoader.swift`、`ImagePeekTests/ImageEngineTests.swift`。

**产生接口：** `DiskCacheSummary(entryCount:byteCount:)`、`DiskImageCache.summary()`、`DiskImageCache.clear()`、`RemoteImageLoader.cacheSummary()`、`RemoteImageLoader.clearCache()`。

- [ ] **步骤 1：写失败测试。**

```swift
func testDiskCacheSummaryReportsStoredEntriesAndBytes() async {
    let cache = DiskImageCache(directory: makeTemporaryCacheDirectory())
    let key = ImageCacheKey(originalURL: URL(string: "https://example.com/a.jpg")!, optimizationRuleVersion: "v1")
    await cache.insert(Data(repeating: 1, count: 12), for: key)
    XCTAssertEqual(await cache.summary(), DiskCacheSummary(entryCount: 1, byteCount: 12))
}

func testDiskCacheClearRemovesEntries() async {
    let cache = DiskImageCache(directory: makeTemporaryCacheDirectory())
    let key = ImageCacheKey(originalURL: URL(string: "https://example.com/a.jpg")!, optimizationRuleVersion: "v1")
    await cache.insert(Data([1]), for: key)
    XCTAssertTrue(await cache.clear())
    XCTAssertEqual(await cache.summary(), DiskCacheSummary(entryCount: 0, byteCount: 0))
}
```

- [ ] **步骤 2：确认测试失败。**

运行：`xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ImagePeekTests/ImageEngineTests`

预期：`summary`、`clear` 和 `DiskCacheSummary` 尚不存在。

- [ ] **步骤 3：最小实现。** `summary()` 加载 manifest、删除过期项并计算条目数/字节数；目录不可用时返回 `nil`。`clear()` 只能删除实例 `directory` 下 manifest 记录和对应 `*.image` 文件，随后写入空 manifest；目录不可用时返回 `false`。`RemoteImageLoader` 以任务 1 的 `CachePolicy` 创建默认 `DiskImageCache` 并转发两个操作。

```swift
struct DiskCacheSummary: Equatable, Sendable {
    let entryCount: Int
    let byteCount: Int
}
```

- [ ] **步骤 4：确认通过并提交。**

运行与步骤 2 相同的命令，预期通过；然后执行：

```zsh
git add ImagePeek/ImageEngine/DiskImageCache.swift ImagePeek/ImageEngine/RemoteImageLoader.swift ImagePeekTests/ImageEngineTests.swift
git commit -m "feat: add cache summary and clear controls"
```

## 任务 3：运行时诊断状态

**文件：** 修改 `ImagePeek/AppShell/AppSettings.swift`、`ImagePeek/AppShell/ImagePeekApp.swift`、`ImagePeekTests/PreviewEngineTests.swift`。

**产生接口：** 主线程 `OperationsStatusStore`，向设置窗口发布 `diagnostics` 和 `cacheSummary`。

- [ ] **步骤 1：写失败测试。**

```swift
func testOperationsStatusStorePublishesLatestDiagnosticsSnapshot() {
    let store = OperationsStatusStore()
    store.updateDiagnostics(RuntimeDiagnosticsSnapshot(networkLoadCount: 1))
    XCTAssertEqual(store.diagnostics.networkLoadCount, 1)
}
```

- [ ] **步骤 2：确认测试失败。** 运行 `xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ImagePeekTests/PreviewEngineTests`；预期 `OperationsStatusStore` 尚不存在。

- [ ] **步骤 3：最小实现。**

```swift
@MainActor
final class OperationsStatusStore: ObservableObject {
    @Published private(set) var diagnostics = RuntimeDiagnosticsSnapshot()
    @Published private(set) var cacheSummary: DiskCacheSummary?
    func updateDiagnostics(_ value: RuntimeDiagnosticsSnapshot) { diagnostics = value }
    func updateCacheSummary(_ value: DiskCacheSummary?) { cacheSummary = value }
}
```

应用启动时创建状态存储并注入菜单栏和运行时。运行时以 `ContinuousClock` 记录远程加载耗时：成功记录来源与耗时；抛错或 `NSImage(data:) == nil` 记录失败；`nil` 结果记录取消；本地文件成功记录本地成功。每次记录后更新状态存储；设置窗口出现和缓存清理完成后刷新摘要。取消永不算失败。

- [ ] **步骤 4：确认通过并提交。** 运行步骤 2 的命令，预期通过；执行 `git add ImagePeek/AppShell/AppSettings.swift ImagePeek/AppShell/ImagePeekApp.swift ImagePeekTests/PreviewEngineTests.swift && git commit -m "feat: expose runtime diagnostics status"`。

## 任务 4：可配置预览标题

**文件：** 修改 `ImagePeek/PreviewEngine/PreviewEngine.swift`、`ImagePeek/AppShell/ImagePeekApp.swift`、`ImagePeekTests/PreviewEngineTests.swift`。

**产生接口：** `PreviewImageInfo.captionText(pixelSize:source:showsPixelDimensions:showsLoadSource:) -> String?`，以及扩展后的 `PreviewPanelController.show`/`showPinned` 参数。

- [ ] **步骤 1：写失败测试。**

```swift
func testPreviewCaptionCombinesPixelSizeAndSource() {
    XCTAssertEqual(
        PreviewImageInfo.captionText(pixelSize: CGSize(width: 900, height: 1200), source: .diskCache, showsPixelDimensions: true, showsLoadSource: true),
        "900 × 1200 px · Disk cache"
    )
}

func testPreviewCaptionIsHiddenWhenBothDetailsAreDisabled() {
    XCTAssertNil(PreviewImageInfo.captionText(pixelSize: .zero, source: .network, showsPixelDimensions: false, showsLoadSource: false))
}
```

- [ ] **步骤 2：确认测试失败。** 运行 `xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ImagePeekTests/PreviewEngineTests`；预期 `captionText` 尚不存在。

- [ ] **步骤 3：最小实现。** 组合非空项目，以 ` · ` 分隔；来源显示名固定为 `Network`、`Disk cache`、`Memory cache`。标题为 `nil` 时隐藏 `imageInfoLabel`，否则显示并保持既有底部布局。普通预览和固定预览使用相同设置；不修改缩放、位置、滚动条或快捷键。

- [ ] **步骤 4：确认通过并提交。** 运行步骤 2 的命令，预期通过；执行 `git add ImagePeek/PreviewEngine/PreviewEngine.swift ImagePeek/AppShell/ImagePeekApp.swift ImagePeekTests/PreviewEngineTests.swift && git commit -m "feat: make preview caption configurable"`。

## 任务 5：设置 UI、完整验证与交付

**文件：** 修改 `ImagePeek/AppShell/SettingsView.swift`、`ImagePeek/AppShell/ImagePeekApp.swift`、`ImagePeekTests/PreviewEngineTests.swift`、`README.md`。

- [ ] **步骤 1：写设置持久化失败测试。**

```swift
func testSettingsStorePersistsOperationsControls() {
    let defaults = UserDefaults(suiteName: "ImagePeekTests-\(UUID().uuidString)")!
    let store = SettingsStore(userDefaults: defaults)
    var settings = ImagePeekSettings()
    settings.showsPixelDimensions = false
    settings.showsLoadSource = true
    settings.cacheSizeGiB = 2
    settings.cacheRetentionDays = 14
    store.save(settings)
    XCTAssertEqual(store.load(), settings)
}
```

- [ ] **步骤 2：确认测试失败。** 运行 `xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ImagePeekTests/PreviewEngineTests`；若任务 1 已先实现而此测试通过，则记录此事实后继续。

- [ ] **步骤 3：实现 UI。** 新增 Preview 区域的两个 Toggle；Cache 区域的容量/天数输入、摘要和 `Clear Cache` 按钮；Diagnostics 区域显示匿名会话计数及最近结果。清理进行时禁用按钮，完成或失败用行内文字反馈；缓存容量与保留期保存后在下次启动时生效，并明确显示该提示。SwiftUI 不可直接删文件，必须通过运行时和 `RemoteImageLoader.clearCache()`。README 说明可配置缓存和会话诊断，且不会收集 URL 或表格数据。

- [ ] **步骤 4：执行完整验证。** 依次运行：`xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`、`xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -configuration Release CODE_SIGNING_ALLOWED=NO build`、`git diff --check`。预期完整 XCTest 和 Release 构建成功，最后命令无输出。

- [ ] **步骤 5：人工回归。** 在 WPS 与 Excel 各选择一张图片 URL：预览正常；切换标题设置；清理缓存后再次预览；Esc、Space、⌥C、⌥O、⌥R、⌥P 和固定窗口位置均不变。若实际行为异常，停止提交并按系统化调试流程处理。

- [ ] **步骤 6：提交并推送。** 执行 `git add ImagePeek/AppShell/SettingsView.swift ImagePeek/AppShell/ImagePeekApp.swift ImagePeekTests/PreviewEngineTests.swift README.md && git commit -m "feat: add preview operations controls" && git push origin feature/wps-accessibility-adapter`。

## 自检

- 设计书的诊断、缓存、标题设置、隐私和安全边界均有对应任务。
- 每个任务均先写测试、确认失败、最小实现、验证并独立提交。
- 本计划没有 TODO、TBD 或未定义的后续工作占位。
