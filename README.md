# ImagePeek

<p align="center">
  <img src="ImagePeek/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="144" alt="ImagePeek 图标">
</p>

<p align="center"><strong>在表格中选中图片地址，立即查看图片。</strong></p>

ImagePeek 是一款轻量的 macOS 菜单栏工具，帮助你在处理商品、素材、数据集或内容审核表格时，快速预览图片 URL 和本地图片路径，无需反复打开浏览器。

## 功能

- 在单元格附近显示图片预览，不打断当前工作。
- 支持远程图片 URL、本地路径和 `file://` 地址。
- 支持图片放大、缩小、滚动和鼠标拖拽查看细节。
- 显示图片像素尺寸与加载来源。
- 提供内存与磁盘缓存，可在设置中查看、清理和调整缓存。
- 支持固定图片，便于对照浏览。
- 支持快捷键：`Space` 展开/收起、`Esc` 临时隐藏、`⌥C` 复制图片、`⌥O` 打开来源、`⌥R` 在 Finder 中显示本地图片、`⌥P` 固定/取消固定。
- 可选开启全局框选 URL 预览：选中文字后短暂停留即可预览。

## 支持的平台

| 应用 | 支持情况 |
| --- | --- |
| WPS 表格（macOS） | 支持鼠标选择和键盘移动单元格 |
| Microsoft Excel（macOS） | 支持选中单元格预览 |
| 飞书 Sheets（Chrome） | 支持 `*.feishu.cn/sheets/` 页面 |
| Chrome、TraeCode、飞书聊天 | 支持框选 URL 预览 |

其他应用的框选能力取决于其是否向 macOS 辅助功能公开选中文本。

> ImagePeek 当前仅支持 macOS。如果你希望使用 Windows 版本，欢迎通过 [功能建议 Issue](https://github.com/yangjian1218/url_image_peek/issues/new?template=feature_request.md) 说明你的应用、审核场景和最需要的功能。Star 和来自真实工作流的 Issue 会作为后续评估 Windows 版本的重要参考，但不代表已经承诺开发时间。

## 下载与安装

请前往 [Releases](https://github.com/yangjian1218/url_image_peek/releases) 下载最新版本。

1. 下载并解压 `ImagePeek-x.y.z-development-signed.zip`。
2. 将 `ImagePeek.app` 拖入“应用程序”文件夹。
3. 首次运行时按住 Control 点击 App，选择“打开”。
4. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许 ImagePeek。

ImagePeek 是菜单栏应用，不会显示在 Dock 中。当前公开版本为开发签名测试版，支持 Apple Silicon 与 Intel。

## 隐私

ImagePeek 不使用屏幕录制、OCR、广告分析或开发者服务器。它只在需要时读取当前应用公开的选中文本，并从对应图片地址加载图片；缓存保存在本机。详见[隐私说明](docs/PRIVACY.md)。

## 反馈与建议

欢迎通过 GitHub 提交 [问题反馈](https://github.com/yangjian1218/url_image_peek/issues/new?template=bug_report.md) 或 [功能建议](https://github.com/yangjian1218/url_image_peek/issues/new?template=feature_request.md)。如果你希望支持 Windows，请在功能建议中说明所用表格应用和真实工作流；Star 与 Issue 会帮助作者评估后续优先级。请勿提交真实图片 URL、表格内容、Cookie、密钥或其他敏感信息。

## 支持开发

ImagePeek 免费提供。如果它对你的工作有帮助，欢迎自愿赞助支持持续维护。赞助不对应任何商品、服务或功能承诺。

<p align="center">
  <img src="docs/assets/wechat-pay.png" width="280" alt="微信支付赞助二维码">
</p>

## 许可

本项目采用 [MIT License](LICENSE)。
