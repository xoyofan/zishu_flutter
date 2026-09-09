# zishu_flutter（紫薯直播 Flutter 客户端）

目标平台为 Web、Windows、Android，客户端技术核心是 **Flutter + media-kit**。

- Web：Flutter UI 通过 Dart `streaming-server` HTTP/SSE/WebSocket 使用解析能力。
- Windows / Android：直接 import 独立纯 Dart `live_parser` package；当前优先完成 Windows。
- 三端共享业务模型、解析接口和用例；解析 package 不依赖 Flutter Widget、media-kit 或具体平台。
- 旧实现已统一归档到 `lib/legacy/`，新功能只在 `lib/src/` 开发。

详细目录和依赖规则见 [`docs/architecture.md`](docs/architecture.md)，完整实施路线见 [`docs/implementation-plan.md`](docs/implementation-plan.md)。

## 运行

```powershell
# 新 Windows 客户端
flutter run -d windows -t lib/main.dart

# 旧 Web 回归
flutter run -d chrome -t lib/legacy/main_web.dart
flutter build web -t lib/legacy/main_web.dart
```

## 验证

```powershell
flutter analyze
flutter test
.\tool\build-web.ps1
```

## 许可

按需复制自 pure_live（AGPL-3.0）的代码随之传染 AGPL；本仓库私有自用，对外分发前需整体 AGPL-3.0。
