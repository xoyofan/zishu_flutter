# zishu_flutter（紫薯直播 Flutter 客户端）

全新 Flutter 工程（Web 平台优先），对齐 `D:\SFVideoLive\web`（Vue3 + Element Plus）的样式与交互；
解析能力复用 SFVideoLive 的 streaming-server（HTTP API，CORS 已开）。

## 结构约定（双 package）

```
lib/
├─ engine/        # 第一部分：解析 + 播放 + 弹幕数据面（不 import ui）
│  ├─ contracts/  # streaming-server 契约模型（对齐 SFVideoLive/contracts/*.schema.json）
│  ├─ remote/     # HTTP 客户端（Dio）+ 弹幕通道
│  ├─ sites/      # LiveSite/LiveDanmaku 契约（M1 自 pure_live 移植）
│  ├─ playback/   # 播放器抽象 + Web 适配器（M2）
│  ├─ danmaku/    # SSE/WS 通道 + 渲染调度（M2/M3）
│  └─ engine.dart # barrel：ui 只许 import 这个
└─ ui/            # 第二部分：复刻 web 视觉与交互（只 import engine.dart）
   ├─ theme/      # design_tokens（#f3d04e 主色、暗色默认、断点 640/768/1024/1366/1920）
   ├─ views/  widgets/  controllers/
   └─ ui.dart
```

## 运行

```bash
# 需 Flutter 3.47.0（本机 D:\flutter-sdk\flutter-3.47.0\flutter）
flutter pub get
flutter run -d chrome            # 开发
flutter build web                # 发布产物 build/web

# 指定解析服务（可选，默认读 assets/config/config.json）
flutter run --dart-define=STREAM_API_URL=http://127.0.0.1:8766
```

## 契约来源

- `SFVideoLive/contracts/room.schema.json`、`browse.schema.json`、`search.schema.json`
- 端点参数对齐 `SFVideoLive/web/src/api/{room,browse,search}.ts`
- 设计 token 对齐 `SFVideoLive/web/src/styles/{theme,main}.css`

## 许可

按需复制自 pure_live（AGPL-3.0）的代码随之传染 AGPL；本仓库私有自用，对外分发前需整体 AGPL-3.0。
