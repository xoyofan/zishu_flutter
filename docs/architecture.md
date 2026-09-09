# 项目目录架构

客户端技术栈为 **Flutter + media-kit**，目标平台为 Web、Windows、Android。
直播站点解析与 UI/播放器分离：解析核心规划为独立纯 Dart package；Web 经 Dart `streaming-server` 调用该 package；Windows、Android 直接 import 同一 package。

## 技术栈（2026-09-09 确认，详见 implementation-plan 7.0）

- UI：Flutter Material 3；视觉系统 ThemeData + ThemeExtension（`ZishuTokens`）
- 状态：Riverpod；路由：go_router；图片：cached_network_image
- 播放：media-kit（`LivePlayer` 抽象）；HTTP：dio（客户端侧）
- 解析 package（`live_parser`）：纯 Dart，仅 `http` + `crypto`，手写模型，无 codegen
- 后置引入：Drift / shared_preferences / window_manager / file_picker（按里程碑）

## 新代码目录

```text
lib/
├─ main.dart                         # 当前默认入口：Windows
├─ src/
│  ├─ shared/
│  │  ├─ domain/                     # 三端共享实体、值对象、解析接口
│  │  ├─ application/                # 三端共享用例
│  │  └─ parsing/                    # 解析 package 的客户端接口/过渡代码，不存第二套站点解析
│  ├─ features/                      # 按业务功能组织的 presentation/application
│  ├─ platforms/
│  │  ├─ web/                        # Web API adapter + media-kit Web 播放适配
│  │  ├─ windows/                    # 直调 Dart parser + media-kit Windows
│  │  └─ android/                    # 直调 Dart parser + media-kit Android
│  └─ apps/
│     ├─ web/                        # 新 Web Flutter app root
│     ├─ windows/                    # 新 Windows Flutter app root
│     └─ android/                    # 新 Android Flutter app root
└─ legacy/                           # 旧实现整体归档，不作为新架构依赖
   ├─ main_web.dart                  # 旧 Web E2E 入口
   ├─ app/                           # 旧启动装配
   ├─ core/                          # 旧 remote contracts/sites 实现
   ├─ danmaku/                       # 旧弹幕通道
   ├─ web_platform/                  # 旧 JS Web 播放实现
   └─ web_app/                       # 旧 Web UI
```

## 解析接口方向

```text
shared/domain  <- shared/application
                       ^
                       |
       +---------------+----------------+
       |                                |
platforms/web                     platforms/windows|android
StreamingServerParserAdapter      DirectDartParserAdapter
HTTP -> Dart streaming-server     直接 import packages/live_parser
```

Web、Windows、Android 对 application 暴露同一个解析 gateway；差异只发生在 adapter。
站点解析源码统一位于 `packages/live_parser/`，禁止在 `lib/src/`、Dart server 或三端 adapter 中复制第二套实现。

## 播放器方向

```text
Flutter UI -> player abstraction -> media-kit -> platform libs
```

`media-kit` 是客户端播放核心，但不得进入纯 Dart 解析层。各平台初始化和能力差异放在 `src/platforms/<platform>/`。

## 强制边界

1. 新代码禁止 import `package:zishu_flutter/legacy/...`。
2. `src/shared/domain`、`src/shared/application`、`src/shared/parsing` 禁止依赖 Flutter Widget、`media-kit`、JS 和具体平台 API。
3. Web 解析 adapter 只消费 Dart `streaming-server` HTTP API，不在 Flutter Web 内运行站点解析源码。
4. Windows/Android adapter 直接 import `packages/live_parser/`，不绕行 `streaming-server`。
5. UI 放在 `src/apps`/`src/features`；播放器、HTTP、文件系统等实现放在 `src/platforms`。
6. `legacy/` 只允许修复旧 Web 回归链路，不向其中添加新产品功能。

## 入口命令

```powershell
# 新 Windows 客户端
flutter run -d windows -t lib/main.dart

# 旧 Web E2E 回归
flutter run -d chrome -t lib/legacy/main_web.dart
flutter build web -t lib/legacy/main_web.dart
```
