# macOS 构建与验收

macOS 构建使用 Flutter 3.47.2 stable / Dart 3.13.2，部署目标为 macOS 12。先安装并完成 Xcode 许可及 macOS 平台组件配置。本地已使用 Xcode 27 在 Apple Silicon 上构建；Intel 和最低支持系统的运行验证仍需补充。

## 构建与检查

在仓库根目录执行：

```sh
flutter pub get
dart run tool/gates.dart analyze
dart run tool/gates.dart test --concurrency=2 --dart-define=HARNESS_AUTO_IMPORT_CREDENTIALS=false
flutter build macos --release
codesign --verify --deep --strict build/macos/Build/Products/Release/novelai_harness.app
```

如需指定 Xcode，可在单次构建前设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。构建保留正常 pub 准备阶段：测试阶段生成的 SwiftPM 清单可能不包含原生插件，直接跳过 pub 阶段会导致模块解析失败。

现有 Windows / Android 发布工作流使用另一 Flutter 版本。本变更保留其工具链与仓库锁文件；macOS 的 `flutter pub get` 会按固定的 Flutter SDK 解析 SDK 所绑定的依赖。本地生成的锁文件变化不应误混入其他功能 PR。Flutter 3.47 也会自动迁移分析配置以排除生成的平台目录；该本地工具链变化不属于应用功能补丁。SwiftPM 的 `Package.resolved` 则用于本原生构建。

`.github/workflows/macos-test.yml` 在指向 master 的 PR、master 或 `codex/pr-macos-*` 分支推送、手动触发时执行分析、测试、release 构建及签名/沙盒权限检查。产物名从 `pubspec.yaml` 读取版本，保留七天。此流程上传 Actions artifact，不创建 GitHub Release；远端执行结果需在实际运行后报告。

ZIP 可用 `ditto -c -k --sequesterRsrc --keepParent` 打包 `.app`，解压后再次运行签名检查。本地 ad-hoc 签名不等于 Developer ID 签名或 Apple 公证。

## 桌面行为

- 原生窗口按钮保留，标题栏避让按钮，且独立于应用内容缩放；宽窄布局都不重复绘制窗口控制按钮。
- 设置保存等待对话框完全退出后再应用语言、主题和缩放。取消不应用草稿。
- macOS 使用 Command+V 粘贴；组合输入候选阶段 Enter 不提交；Shift+Enter 插入换行。
- App Sandbox 保留；启用网络客户端和用户所选文件的读写权限。

## 验证边界

当前 Flutter 辅助功能桥接崩溃规避使用 `ExcludeSemantics`，应用内容不能由 VoiceOver 读取，原生窗口按钮仍可用。该规避是明确的功能限制，需要继续缩小或消除；构建成功不代表无障碍支持完成。

键盘回归使用 Flutter 平台通道和模拟事件，覆盖组合区间、换行、Unicode 及选区替换。实体拼音输入法、Command+V 和 Shift+Enter 仍须在原生应用中检查，不能用自动化工具注入失败或模拟测试通过代替结论。原生验收还应覆盖语言保存/取消、100%/125% 缩放、文件选择器导入导出及退出重开。

`HARNESS_AUTO_IMPORT_CREDENTIALS=false` 是编译期验证选项，关闭 Pi 配置及环境变量的凭据发现，默认正式行为不变。它不会隔离已保存配置或禁用所有网络。原生 QA 必须使用独立 bundle ID、空凭据和独立存储，并关闭词库自动更新；不应启动用户的日常应用进行测试。

真实账号、模型/绘图调用、费用、Intel 与旧 macOS、VoiceOver，以及正式签名/公证均需单独验证。

参考：[对话框退出完成时机](https://api.flutter.dev/flutter/widgets/TransitionRoute/completed.html)、[Flutter SwiftPM 构建说明](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)、[macOS 工具链配置](https://docs.flutter.dev/platform-integration/macos/setup)。
