# dsh助手（iOS）

把 DeepSeek Harness（dsh）打包成 iOS App：内嵌 Node + `@deepseek-ai/dsh`，
SwiftUI/WKWebView 原生外壳，点图标即进入 dsh 操作界面（与桌面 Web UI 一致）。

## 构建
GitHub Actions（macos-15 + Xcode）：交叉编译 Node-for-iOS → npm 装 dsh →
XcodeGen + xcodebuild → 无签名 IPA（AltStore/全能签侧载）。

## 产物
`dsh助手_V1.ipa`，发布在 GitHub Release `V1`。