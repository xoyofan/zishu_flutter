# zishu_flutter 项目约定

## 语言
- 始终使用简体中文回复，包括解释、说明和总结。
- 代码、命令、文件路径、报错信息和专有技术名词保持英文原文。

## 三端架构
- 客户端技术核心是 Flutter + `media-kit`；Windows、Android 与新 Web UI 均以 Flutter 构建，播放器优先通过 `media-kit` 及对应平台 libs 适配。
- 当前开发优先级为 **Windows > Web > Android**；先完成 Windows 产品闭环，再复用到 Web 与 Android。
- “解析核心”特指直播站点解析、业务模型和用例，采用独立纯 Dart package；保持无 Flutter Widget、无 `media-kit` 和具体 UI/平台依赖。
- Web 端不在浏览器客户端直接运行解析核心；目标为 Dart `streaming-server` 直接 import 同一个纯 Dart 解析 package，再向 Flutter Web 提供 HTTP/SSE/WebSocket API。旧 Node `streaming-server` 仅作为迁移期参考和兼容实现。
- Windows 直接 import 纯 Dart 解析 package；Android 后续采用相同方式。三端不得分别维护多套站点解析源码。
- 三端共享业务契约、解析接口与用例；平台差异通过 adapters/platforms 层实现，禁止播放器、Widget 或平台 API 反向进入解析核心。

## 目录与依赖边界
- 旧实现统一归档在 `lib/legacy/`；新产品代码位于 `lib/src/`，解析 package 规划在 `packages/live_parser/`。
- 新代码禁止 import `package:zishu_flutter/legacy/...` 或相对引用 `lib/legacy/`。
- Web 专属 `dart:js_interop`、`dart:ui_web`、`package:web`、`HtmlElementView` 只能位于 legacy 或新 `src/platforms/web/`。
- 解析 package 禁止依赖 Flutter、Widget、`media-kit`、`dart:ui`、`package:web` 和 `dart:js_interop`。
- 播放器属于 platforms/adapters 层，不进入解析核心。
- UI 最终参考 `SFVideoLive/web` 的布局、样式、平台范围和主要功能，但使用 Flutter Widget 重新实现，不复用旧 Vue UI。

## 计划与验收
- 总体实施基线见 `docs/implementation-plan.md`，架构概要见 `docs/architecture.md`。
- UI 与解析双轨通过稳定 Dart models/interfaces 和 JSON fixtures 解耦，禁止 UI 直接消费松散 `Map<String, dynamic>`。
- 每次结构性修改至少运行 `flutter analyze` 和相关测试；Windows 主链路修改还需运行 `flutter build windows --debug -t lib/main.dart`。
