# SFVideoLive Web UI 基准（用于 zishu_flutter 一比一复刻）

> 抓取时间：2026-09-09 ｜ 源：`F:\project\SFVideoLive`（streaming-server :8766 + vite web :9000）
> 抓取方式：playwright-cli run-code，登录相关 UI 已注入 CSS 隐藏（`button[title="登录"]` / `.auth-dialog` / `.el-overlay`）

## 文件

- `shots/` — 40 张截图，命名 `{页面}_{视口宽}x{高}[_状态].png`
  - 页面：home-all / home-douyu / category-index / category-rooms / follow / time / play
  - 视口：390×844（手机）、800×600（紧凑 768–1080 档）、1366×768、1920×1080、2560×1440（宽屏）
  - 附加状态：`home-all_desktop_1920x1080_drawer-open/closed.png`、`category-index_desktop_..._drawer-open/closed.png`、`home-all_desktop_1920x1080_light.png`（浅色主题）
- `measurements.json` — 每张截图对应的 DOM 测量（导航/抽屉/网格/卡片几何与颜色）

## 启动方式（复现抓取环境）

```bash
# streaming-server
cd F:/project/SFVideoLive/streaming-server && npm run dev     # :8766
# web（注意：清空 NODE_OPTIONS，避免 WorkBuddy safe-delete shim 拦截 vite 依赖预构建导致崩溃）
cd F:/project/SFVideoLive/web && NODE_OPTIONS= npm run dev    # :9000
```

路由：`/all` 全平台首页 ｜ `/:site` 单平台首页 ｜ `/:site/category` 分类图标页 ｜ `/:site/category/:cid` 分类房间页 ｜ `/follow` 关注 ｜ `/time` 时间线 ｜ `/:site/play/:id` 播放页（样例房间 `/douyu/play/63136`）

## 关键测量（dark 默认主题）

### 全局
| 项 | 值 |
|---|---|
| body 背景 | `rgb(24,24,24)` #181818 |
| 正文色 | `rgba(255,255,255,0.87)`，字号 16px 基准（rem 体系） |
| 强调色 accent | 琥珀 `rgb(243,208,78)` **#F3D04E**（`.nav-item.active` 文本色） |
| 面板/卡片 | nav `rgb(31,31,31)`，card `rgb(36,36,36)`，边框 `rgb(58,58,58)` |
| 圆角 | 卡片 4px（--fluent-radius-sm 体系） |

### 桌面顶导航（≥768，sticky top）
- 高度 **44px**（--nav-chrome-height），背景 #1f1f1f + 底边框 #3a3a3a + mica 模糊
- 左组：品牌 logo 30×30 + 「紫薯直播」1.02rem + 首页/分类/我的分类（icon+文字，间距 0.62rem padding）
- 中组：**绝对居中**平台图标 tab，34×34px，gap 3.2px，active = 平台色描边 + `--sidebar-chip-active-bg` + 琥珀 glow；768–1080 收缩为 28px
- 右组：我的关注（含开播头像堆叠 1.48rem，重叠 32%）/ 搜索 / 主题切换（月/日）/ 登录·用户

### 手机（<768）
- 顶导航不渲染，主导航为 **fixed bottom 56px** 图标栏（首页/分类/我的分类/关注/搜索/主题）
- 顶部 `NavPlatformStrip`：平台图标网格（带下拉箭头，active 琥珀高亮），两行换行
- 内容区 2 列房卡网格

### DirectoryDrawer（首页/分类页专用，播放页无）
- 展开态 **220px**（--directory-drawer-width），主内容 `margin-left: 220px`
- 收起态：细图标导轨（--directory-rail-width ≈28px），主内容 margin-left 同步
- 内容：平台图标行 + 分区目录列表；顶部有关注头像区

### 房间网格（.room-grid）
- 列数：CSS 变量 `--room-grid-cols-wide`，1920 抽屉开 = **5 列**，关 = 6 列，≥2560 = 7 列
- gap `13.6px 16px`（0.85rem 1rem）
- 卡片（.room-card）：1920 抽屉开时 314×232；封面比例 **1.78（16:9）**；radius 4px；bg #242424
- 徽章：分类 tag 左上、平台 badge + 热度右下；标题 14.4px 单行，副行灰

### 播放页（无抽屉，顶导航保留）
- 桌面：播放器左 flex（1920 时 1495×1004）+ 右侧栏 **425px**（主播信息卡 + 聊天 tabs + 弹幕/聊天输入）
- 窄屏（<~1000）：`play-layout--stack`，播放器全宽 16:9（390×219），侧栏在下（390 时 617px 高）
- 弹幕为播放器上层 overlay

### 分类图标页
- 平台 tabs 行（全平台/斗鱼/虎牙/…/IPTV）+ 分组 chips 行（active 琥珀）+ 方形图标网格（1920 约 10 列，图标+名称）

## 复刻注意（对应 zishu_flutter 现状差距）

1. zishu_flutter 现为自创顶部导航+色点文字 tabs；需改为：44px 吸顶条（左品牌+三项、中平台图标 tab 绝对居中、右工具组）、<768 底部 56px 图标栏 + 顶部平台图标条。
2. 首页/分类页缺左侧 DirectoryDrawer（220px 展开 / 28px 导轨，主内容 margin 同步）。
3. 主题令牌需全量换成上表（#181818/#F3D04E/#1f1f1f/#242424/#3a3a3a，4px 卡片圆角，0.85/1rem 网格间距）。
4. 播放页需保留顶导航、去抽屉，桌面左右分栏（右栏 425px）、窄屏 stack。
5. 房卡结构按徽章/标题/副行三段复刻，网格列数按断点 5/6/7。
