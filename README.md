# ImagePeek

<p align="center">
  <img src="ImagePeek/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="144" alt="ImagePeek icon">
</p>

**在表格单元格附近，快速预览图片 URL 或本地图片地址。**

ImagePeek 是一款原生 macOS 菜单栏工具。它读取当前选中的图片地址，在不打断表格操作的前提下显示浮窗预览。

> 当前为公开测试版。适用于 macOS 13（Ventura）及以上版本，提供 Apple Silicon 与 Intel 通用二进制。

## 已验证支持

| 场景 | 状态 | 说明 |
|---|---|---|
| WPS 表格桌面版 | 已验证 | 鼠标选择及键盘移动单元格均可触发预览。 |
| Microsoft Excel 桌面版 | 已验证 | 支持选中单元格预览。 |
| 飞书多维表格 / Sheets（Google Chrome） | 已验证 | 仅支持 `*.feishu.cn/sheets/` 页面。 |
| 任意应用中的框选 URL | 尽力支持 | 已验证 Chrome、TraeCode、飞书聊天；取决于应用是否通过 macOS 辅助功能公开选中文本。VS Code、Sublime Text、微信当前版本不支持。 |

其他网页表格暂未支持。

## 主要功能

- 从远程图片 URL 或本地图片路径加载预览。
- 靠近选中单元格显示非激活浮窗，不抢走表格焦点。
- 放大、滚动及鼠标拖拽查看图片局部；显示图片像素尺寸和加载来源。
- 内存与磁盘缓存，设置中可查看并清除缓存。
- `Space` 展开/收起预览，`Esc` 临时隐藏；`⌥C` 复制图片，`⌥O` 打开来源，`⌥R` 在 Finder 中显示本地图片，`⌥P` 固定/取消固定预览。
- 可设置图片所在列、开机自启、缓存上限和缓存保留时间。

## 下载与安装

1. 在 [Releases](https://github.com/yangjian1218/url_image_peek/releases) 下载最新的 `ImagePeek-x.y.z-unsigned.zip`。
2. 解压后，将 `ImagePeek.app` 拖入“应用程序”文件夹。
3. 首次运行时，按住 Control 点击 `ImagePeek.app`，选择“打开”，再确认“打开”。这是未签名测试版的正常 macOS 安全提示。
4. ImagePeek 是菜单栏应用，不会出现在 Dock 中。请在菜单栏寻找它的蓝色“图片 + 放大镜”图标。

> 不要关闭 macOS 的 Gatekeeper，也不要从不可信来源下载同名 App。当前发布包会附带 SHA-256 校验文件，下载后可用 `shasum -a 256 ImagePeek-*.zip` 比对。

## 首次设置

1. 点击菜单栏 ImagePeek 图标，打开 Settings。
2. 在“隐私与安全性 → 辅助功能”中允许 ImagePeek。它需要此权限读取当前表格单元格或应用公开的选中文本。
3. 如要使用 `Space`、`Esc` 和 `⌥` 快捷键，还需在“输入监控”中允许 ImagePeek。
4. 在 WPS、Excel 或支持的飞书 Sheets 页面中选择包含完整图片 URL 的单元格。

WPS 在本机未公开选中单元格文本时，会临时复制单元格内容并立即恢复剪贴板；可在 Settings 中关闭该兜底方案。

## 隐私与权限

ImagePeek 不使用屏幕录制、OCR、广告分析或开发者服务器。它只会在所需时读取前台支持应用中的选中内容，并向图片 URL 对应的服务器请求图片；图片缓存保存在本机，用户可随时清除。

详细说明见 [隐私说明](docs/PRIVACY.md)。

## 反馈与需求

欢迎通过 GitHub 提交：

- [报告问题](https://github.com/yangjian1218/url_image_peek/issues/new?template=bug_report.md)
- [提出功能建议](https://github.com/yangjian1218/url_image_peek/issues/new?template=feature_request.md)

提交问题时请勿粘贴真实图片 URL、表格内容、Cookie、密钥、账号或其他敏感信息。

## 支持开发

ImagePeek 目前免费提供。若它对你的工作有帮助，欢迎自愿赞助以支持持续维护；赞助不对应任何商品、服务或功能承诺。

<p align="center">
  <img src="docs/assets/wechat-pay.png" width="280" alt="微信支付赞助二维码">
</p>

## 开发与发布

开发环境：Xcode 16.1、macOS 13+。

```zsh
xcodebuild -project ImagePeek.xcodeproj \
  -scheme ImagePeek \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test

./scripts/package-release.sh
```

发布流程、校验和、未签名测试版限制及未来 Developer ID 公证步骤见 [发布说明](docs/RELEASE.md)。

## 许可

本项目采用 [MIT License](LICENSE)。
