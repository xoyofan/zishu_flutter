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

## GitHub 提交与推送
- GitHub 侧操作**优先使用 github MCP**（统一网关 `http://127.0.0.1:8800/mcp/github`，工具前缀 `mcp__github__`）：查询提交/远程状态、PR、issue，以及小规模文件提交（`push_files` / `create_or_update_file`）。
- 本地大批量提交仍用 `git commit`；若 `git push` 缺少已存凭据，用 MCP 网关 `gateway.env.cmd` 中的 `GITHUB_PERSONAL_ACCESS_TOKEN` 做一次性凭据（临时 remote URL 或一次性 credential helper），**禁止把 token 写入仓库文件、`.git/config` 持久化或任何输出**。
- 不同轨道分开提交：UI 轨（`lib/src/**`、`test/ui/**`、看板）与解析轨（`packages/live_parser/**`）各自独立提交，不混在一个 commit 里。

## 提交说明与发版约定
- **提交说明（commit message）、tag 说明与 Release 更新说明一律使用简体中文**；代码、命令、路径、专有技术名词保持英文。
- 发新包（发版）标准流程，全部验证通过后执行：
  1. `pubspec.yaml` 的 `version` 与本次 tag 对齐（如 `1.0.2-beta`）；
  2. 跑全量门禁：`flutter analyze` + `flutter test` + `packages/live_parser` 测试 + `flutter build windows --release -t lib/main.dart --dart-define=ZISHU_REAL_PARSER=true`；
  3. 推送 `master`；
  4. 打 annotated tag 并推送：`git tag -a v1.0.2-beta -m "<中文更新说明>"` + `git push origin v1.0.2-beta`——tag message 即 GitHub Release body，`v*` tag push 自动触发 `.github/workflows/release-windows.yml` 构建 `zishu_flutter-<tag>-win64.zip` 并挂到 Release（`beta` 自动标 prerelease）；
  5. 用 GitHub API（走 `127.0.0.1:7897` 代理）确认 Actions 构建成功、zip 资产已挂。
