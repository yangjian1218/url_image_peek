# ImagePeek 发布流程

## 公开测试版：开发签名 ZIP

在未使用 Developer ID 公证前，ImagePeek 以 GitHub Release 的开发签名 ZIP 形式分发。辅助功能授权要求应用具有稳定签名身份；此包使用构建机本地的开发证书签名，但仍不是 Developer ID 公证包，因此适合公开测试和小范围试用。

```zsh
./scripts/package-release.sh
```

脚本会：

1. 执行开发签名的 Release 构建，并验证 App 签名。
2. 读取 App 的版本号并生成 `artifacts/ImagePeek-x.y.z-development-signed.zip`。
3. 生成同目录的 SHA-256 校验文件 `ImagePeek-x.y.z-development-signed.zip.sha256`。
4. 验证 ZIP 可完整读取，且只包含 `ImagePeek.app`。

发布前应在终端执行：

```zsh
shasum -a 256 artifacts/ImagePeek-x.y.z-development-signed.zip
cat artifacts/ImagePeek-x.y.z-development-signed.zip.sha256
```

两行哈希必须相同。上传 ZIP 与对应 `.sha256` 文件至同一个 GitHub Release。

### 用户安装说明

用户下载并解压 ZIP 后，将 `ImagePeek.app` 拖入“应用程序”。因为当前版本没有 Developer ID 公证，首次运行应按住 Control 点击 App，选择“打开”，再确认“打开”。不要建议用户关闭 Gatekeeper 或执行来源不明的终端命令。

默认使用构建机上的 `NotchBar Development` 证书。其他构建机应显式设置自己的证书名，例如：

```zsh
IMAGEPEEK_CODESIGN_IDENTITY="Apple Development: Your Name" ./scripts/package-release.sh
```

## 发布前人工验收

必须在非 Xcode 运行环境中完成：

1. 从刚生成的 ZIP 解压并启动 `ImagePeek.app`。
2. 确认显示应用图标、菜单栏图标及 Settings 窗口。
3. 重新授予辅助功能；不需要输入监控权限。
4. 使用 WPS、Excel、飞书 Sheets 各测试一条远程图片 URL。
5. 测试图片缩放、滚动、拖拽以及 `Space`、`Esc`、`⌥C`、`⌥O`、`⌥P`；仅本地图片测试 `⌥R`。随后切换到其他应用连续输入，确认没有卡顿，且快捷键不再被接管。
6. 测试设置保存、清除缓存和开机自启。

每次公开发布前均应重新运行完整 XCTest、Release 构建、敏感信息扫描以及上述人工验收。

## 将来的正式直发版本：Developer ID + 公证

加入 Apple Developer Program 后，再使用 Developer ID 证书和本机 Keychain 中的 notarization profile：

```zsh
xcrun notarytool store-credentials "ImagePeekNotary"

./scripts/sign-and-notarize-release.sh \
  "Developer ID Application: Your Name (TEAMID)" \
  "ImagePeekNotary" \
  "./artifacts"
```

证书、Apple ID、app-specific password 和 API Key 都只能存在本机 Keychain；不得写入仓库、Release、Issue 或 CI 日志。
