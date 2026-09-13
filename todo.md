# todo — zishu_flutter

> 状态标记:[x] 完成 / [ ] 待办 / [~] 进行中。每轮任务完成后追加结论与工作项。

## 2026-09-12 data-server 登录 / 关注云同步接入(完成)

**结论**:本机为瘦客户端(不部署 data-server 服务端),仅「接收(GET /api/me/follows)+ 提交(POST 整表替换)」;账号 xoyofan 默认缓存登录,启动自动登录链 + 手动登录框齐备,关注云同步双向打通。

### 本轮完成项
- [x] `lib/src/shared/application/auth_provider.dart`
  - 默认账号常量 `kDefaultAuthUsername/Password`(dart-define `ZISHU_AUTH_USER/PASS` 可覆盖,置空即关闭),无缓存凭据时静默登录并缓存 → 打开即登录。
  - 修复:存储读取收进 try(测试环境无平台实例直接匿名,零网络);离线宽限 catch 修正(checkToken 网络异常原为死分支)。
- [x] `lib/src/features/follow/application/follow_provider.dart`
  - 删除 300ms×30 登录等待轮询(pending timer 根源),`_restore` 尾部直接 `pullRemote()`。
  - 新增 `_authToken`(`ref.exists` 惰性守卫):播放页/非壳场景不强制构建 authProvider。
- [x] `lib/src/app/app_shell.dart`
  - `_UserAvatar` 三态:恢复中占位 / 登录态(头像+用户名+退出菜单)/ 匿名(登录框)。
  - 新增 `_LoginDialog`(用户名预填默认账号、记住密码、错误提示);登录跃迁监听 → `pullRemote()`。
- [x] `test/ui/workflows/settings_test.dart`:注入 `_AnonymousAuthController` 替身(唯一「内存存储+桌面壳」套件,防 fake_async 内真实 HTTP)。
- [x] 验证:`flutter analyze` 零问题;三文件测试 14/14;全量套件 230 例唯一失败为 `latency_test` 斗鱼网络基准抖动(单跑通过);`flutter build windows --debug` 成功(18s,产物 `build\windows\x64\runner\Debug\zishu_flutter.exe`)。

### 已完成(2026-09-12 01:10)
- [x] 提交推送本轮改动:9045fd2(应用轨 sync)+ 702da15(UI 轨 hover),远端 master=702da15。

## 2026-09-12 分类路由修复 + 我的分类(完成)

**结论**:顶栏「分类」/平台 hover 分类项报错系 `_categoryRoute` 拼 `/all/category` 缺 cid 无路由可匹配;已补落地路由 + 带_cid 跳转,并补齐 SFVideoLive 的「我的分类」(hover 浮层 + 管理弹窗,收藏落本机)。

### 本轮完成项
- [x] `app_router.dart`:新增 `/all/category`、`/:site/category` 落地路由。
- [x] `app_shell.dart`:`_categoryRoute(site,{cid})` 带 cid;hover 分类 chip 带 `flyout-category-*` 锚点;`nav-my-category` 接 hover 浮层(收藏 chips + 管理分类)+ 管理弹窗(收藏/移除/上限 12);`_NavAction` 支持带 centerX 的 onTap。
- [x] 新建 `my_category_provider.dart`:收藏 (site,cid,name) 集合,`zishu.myCategories` 本机持久化,上限 12。
- [x] `category_view.dart`:`/all/category/:key` 的 key 同时匹配分类名与 cid(跳转后正确高亮)。
- [x] 测试:`my_category_nav_test.dart` 3 用例 + hover_my_category golden;全量套件 235 全过;analyze 零问题;debug 重建并已拉起真机。

### 待办(下轮候选)
- [x] 真机验证:打开即登录 xoyofan → 凭据缓存与云端关注拉取均已确认(shared_preferences.json 含 JWT + 云端 follow.list)。
- [x] 顶栏 hover 浮层:平台 tab hover 出分类、我的关注 hover 出主播头像网格(对齐 SFVideoLive 源码规格,截图 tool/screenshots/zishu/hover_*.png)。
- [x] hover 分类点击跳转:已带 cid 跳转,分类页正确高亮(路由修复 + key 匹配)。
- [ ] 我的分类:在分类页/hover 浮层内加「收藏当前分类」快捷星标(当前需进管理弹窗勾选)。
- [ ] 手机端(<768)无顶栏头像:后续在设置页补登录入口,并把登录跃迁监听同步过去。
- [x] 关注页三视图与播放页侧栏(关注/推荐)样式对齐 SFVideoLive(封面网格/四列行表/三段式 tile/离线态/角标)。
- [ ] 桌面 1920x1080 布局对齐(logged 基线);播放页右侧抽屉+折叠、底部工具栏、全屏右侧抽屉。
- [x] 提交推送本轮改动(分类路由 + 我的分类,单轨道一次提交即可)。
- [ ] 遗留:其他会话的播放器 stop()/live_parser SOOP 半成品改动,不触碰、待其会话稳定。

## 2026-09-12 关注页三视图 + 播放页侧栏样式对齐 SFVideoLive(完成)

**结论**:关注页「卡片/紧凑/单行」三档密度与播放页侧栏(关注/推荐)全部改为封面网格/表格化行,对齐 SFVideoLive 参考;单测 golden 5 张 + 真机 exe 已验证,analyze 零问题。

### 本轮完成项
- [x] `follow_entry_row.dart`(重写):四列表格——分类条纹 chip / 主播(★ 前缀)/ 标题 / 在线数(人形图标,离线显示时钟 + 「—」);宽屏按 `_rowColumnExtent=380` 自动分多列。
- [x] `follow_view.dart`:行密度改用 `GridView` 按 380px/列 折行,`_cardMaxExtent=240` 统一卡片上限。
- [x] `follow_entry_card.dart`(重写):封面四角标——分类(左下品牌底色)/ 平台(右上)/ ★(左上)/ 在线(右下);离线整体灰度 + 「未开播」条;封下为主播名 → 标题 → 统计行。
- [x] `follow_entry_tile.dart`(重写):pageTile 三段式——左(分类 tag/封面/平台 tag)+ 右(主播名/在线/操作)+ 底部标题。
- [x] 新建 `play_room_grid.dart`:`PlayRoomGrid` / `PlayRoomCard` / `PlayRoomList`,带 `keyPrefix`(保留 `play-recommend-room-` / `play-follow-room-` 测试锚点)与 `superKeys`(★ 收藏)。
- [x] `play_side_panel.dart`:`_FollowPanel` / `_RecommendPanel` 换用 `PlayRoomGrid`(2 列);关注 tab 补视图切换 + 平台筛选 chips;`_panelTitle` → `_PanelTitle`。
- [x] `follow_style_shot_test.dart`(新建,5 golden):follow_style_card / tile / row、play_style_recommend / follow。
- [x] 清理:golden 测试里 path_provider mock 改用非废弃 API(`TestDefaultBinaryMessengerBinding`),`flutter analyze` 从 1 info 归零。

### 验证
- [x] `flutter analyze`:No issues found。
- [x] `test/ui/my_category_nav_test.dart` + `follow_style_shot_test.dart`:8/8 通过。
- [x] 截图落盘 `tool/screenshots/zishu/`(6 张新图)。

## 2026-09-12 平台色主播名 + 角标贴角直角统一(完成)

**结论**:主播名全站统一取平台品牌色(离线压暗),我的关注 hover 每格底色/名字/ hover 高亮都用平台色;房间卡四角 chip/tag 全部紧贴所在角(0 偏移)且直角无圆角,统一收敛到共用组件 `FollowCoverTag`。

### 本轮完成项
- [x] `follow_common.dart`:
  - `FollowCoverTag` 去圆角(直角),注释明确「贴角由调用方 Positioned 0 偏移负责」。
  - 新增 `FollowAnchorName`:主播名统一平台色(离线 alpha 0.6),未收录平台回退文字 token。
- [x] 主播名平台色落地:follow_entry_row / follow_entry_card / follow_entry_tile / play_room_grid(PlayRoomCard+PlayRoomRow)/ browse room_card。
- [x] `app_shell.dart` `_FollowAvatarTile`:每格底色 = 平台色 16% 透明度,hover 加深到 30%,名字用平台色(Ink+InkWell,水波纹可见)。
- [x] 角标贴角 + 直角:follow_entry_card 四角(分类左下/平台右上/★左上/在线右下)、play_room_grid 三角、browse room_card 四象限(分类/平台/促销/热度)Positioned 全部 0 偏移;room_card 四枚角标改用 FollowCoverTag(原 pill 圆角、sm 圆角全去除);tile 的分类/平台 tag 去圆角。
- [x] golden 重生成 8 张(follow_style ×5 + hover ×3),同步 `tool/screenshots/zishu/`。

### 验证
- [x] `flutter analyze`:No issues found;全量套件 242/242 通过。
- [x] debug 重建成功,已 schtasks 拉起真机(hover 关注浮层/关注页三视图/首页房间卡可验)。

## 2026-09-12 对齐差距盘点(对照 `docs/ui-reference/README.md` + SFVideoLive 源码)

**结论**:主体骨架(顶导航/底栏/抽屉/网格断点/侧栏分档/分类图标页/hover 浮层)已对齐;剩余差距集中在**房卡徽章象限、收起态抽屉导轨、关注头像堆叠、时间线入口、播放页底部栏与全屏抽屉**五处,均为局部改动。

### 已对齐(本轮复核确认,不再列待办)
| 项 | 参考 | zishu 现状 |
|---|---|---|
| 顶导航 | 44px sticky,左品牌+三项、中平台 tab 居中、右工具组 | `AppSpacing.topNavHeight=44`;nav-home/category/my-category/follow/search/theme/settings/user 齐备 |
| 手机端 | <768 底部 56px 图标栏 + 顶部平台条 | `bottomNavHeight` 56 + `_PlatformStrip` 两行 |
| DirectoryDrawer | 展开 220px,主内容 margin 同步 | `AppDirectoryDrawer.width=220` |
| 房卡网格 | 列数 2/3/4/5/6/6/7,gap 16/13.6 | `AppRoomGrid.columnsFor` + gridCrossAxis/MainSpacing |
| 播放页侧栏 | 268/328/392/425 分档 | `playSidePanelWidthFor` |
| 侧栏 tabs | 聊天/关注/推荐 | 多一枚「设置」,聊天走 danmakuSession 且与舞台弹幕共用会话 |
| 分类图标页 | 方形图标网格 | `_CategoryTile` 56×56 方形 + 分组 tabs |
| hover 浮层 | 平台分类 800ms 延迟关;关注 7 列头像网格;我的分类 chips | 全部落地(golden 3 张) |

### 未对齐(下轮候选,按优先级)
| # | 差距 | 参考值 | 现状 | 建议 |
|---|---|---|---|---|
| 1 | 首页房卡徽章象限 | 分类**左上**;平台 badge + 热度**同在右下** | 分类左上、平台**左下**、促销右上、热度右下(四角方案) | 二选一:改回参考的「左下留空、平台+热度并列右下」,或保留四角方案待用户裁决 |
| 2 | 抽屉收起态导轨 | `--directory-rail-width ≈ 28px` | `railWidth = 52`(含图标点击热区) | 视觉导轨压到 28,热区用 padding 外扩 |
| 3 | 右组「我的关注」静态态 | 开播头像堆叠,1.48rem、重叠 32% | 仅文字 + hover 网格,静态无堆叠头像 | 补 `_FollowAvatarStack`(最多 3 枚,重叠 32%) |
| 4 | 时间线 /time 入口 | 顶栏/底栏有入口 | 路由 `/time` 在,但顶栏占位已被「我的分类」取代,**无入口可达** | 底栏或「我的」里补时间线入口 |
| 5 | 播放页底部工具栏 + 全屏右侧抽屉折叠 | 桌面底部工具条;全屏可收侧栏 | 控制条在舞台上,无底部工具条/全屏抽屉 | 与既有「桌面 1920 布局对齐」合并做 |
- **更新(2026-09-13)**:#3 右组关注头像堆叠、#4 时间线 `/time` 入口、以及下方「手机端登录入口」待办,已随远端分支 `feat/a11-nav-capability`(提交 `e8e3715`)合并进 master 落地;该分支另含导航能力过滤 + golden 更新。
- [ ] 我的分类:在分类页/hover 浮层内加「收藏当前分类」快捷星标(当前需进管理弹窗勾选)。
- [x] 手机端(<768)无顶栏头像:已由 a11 分支(e8e3715)补设置页登录入口 + 登录跃迁监听,随 a11 合入 master。
- [ ] 桌面 1920x1080 布局对齐(含 #5 播放页底部工具栏/全屏抽屉):仍待办。

## 2026-09-13 合并远端特性分支到 master

**结论**:`git fetch --all` 发现 3 个远端特性分支;经 ahead/behind 分析,仅 `feat/a11-nav-capability` 真正领先 master(基于最新 `61e2fe7` + 1 提交),已 fast-forward 合入;`feat/A1-search`、`feat/A2-danmaku` 内容均已被 master 吸收/超越,判定无需合并(避免无意义冲突)。

### 合并明细
- [x] `feat/a11-nav-capability` → master:`git merge --ff-only` 到 `e8e3715`(导航能力过滤 / 时间线入口 / 手机端登录 / 关注头像堆叠 / golden 更新);`flutter analyze` 零问题。
- [x] `feat/A1-search`:ahead=0、落后 master 26,全部提交已被 master 包含,合并零变化 → 跳过。
- [x] `feat/A2-danmaku`:仅 `a568579` 领先(弹幕纯逻辑早期草稿);master 已有更完整 danmaku 模块(`e6f1513`/`f1397e4` 引入 settings_provider / tail_forwarder / style / track / overlay / settings_panel 等),`danmaku_settings.dart` 触发 add/add 冲突且无净新增 → `git merge --abort` 中止,不合并。
- [x] 验证:`flutter analyze` No issues found(master=`e8e3715`,领先 origin/master 1)。
- [x] 推送:将 `e8e3715`(+ 本进度更新 commit)push 到 origin/master,同步远端主线(fs-only,安全)。

## 2026-09-13 播放器对齐 pure_live:多线路自动切换 + RTMP 协议放行(完成,未提交)

**结论**:跨平台播放参考 pure_live 落两处关键改进——(1) 选中画质的全部线路拼成 mpv `Playlist` 一次打开,某条断流 mpv 内部自动跳下一条,Flutter 侧不再逐条轮询;(2) mpv `protocol_whitelist` 放开 rtmp/rtmps/rtsp/srt,**斗鱼主线路(`rtmp://…`,`flvFromApiData` 拼 `rtmpUrl/rtmpLive`)此前无此白名单会整条打不开**。顺手修回看门狗计数被 `open` 重置导致「放弃重试」分支永远走不到的隐患,并按错误类型给出更精准的兜底提示。

### 本轮完成项
- [x] `platforms/common/playback/live_player.dart`:`open(StreamLine line, [List<StreamLine> fallbacks = const [], bool resetRetries = true])` —— fallbacks 即同画质回退线路。
- [x] `platforms/common/playback/media_kit_live_player.dart`:
  - `open` 把 `[line, ...fallbacks]` 拼成 `Playlist` 一次 `_player.open(playlist, play:true)`;mpv 自动线路切换。
  - `_applyLiveTuning` 增补 `protocol_whitelist`(含 rtmp/rtmps/rtsp/srt)+ `volume-max=100`,并 `setPlaylistMode(PlaylistMode.none)`。
  - 断流恢复策略收敛:单条死亡交给 mpv 播放列表内部跳转;仅「全组耗尽」(`events.completed`)或冻结卡顿(缓冲看门狗)才整组轮转(`_reopenIfStalled`);新增 `_onCompleted`。
  - 修正:`open` 仅在用户切换(`resetRetries=true`)时清零计数,看门狗重连传 `false`,否则 `_kMaxStallRetries=6` 放弃分支不可达;`_onPlaying` 出帧即清残留 error 文案。
  - 错误分类 `_classifyError`/`_retryGiveUpMessage`:network/codec/source/other 四类精准提示。
- [x] `features/play/application/play_provider.dart`:`build`/`switchQuality`/`switchLine`/`_openSelected` 全部传 `quality.lines` 中除首选外的线路作回退(`_fallbackLines` 辅助)。
- [x] 21 个 `test/ui` FakeLivePlayer 的 `open` 签名同步追加可选参数(`analyze` 全绿,未改调用语义)。

### 受益平台(均返回多线路,自动切换生效)
- 斗鱼:多档多 CDN + HLS 回退,且 FLV 主线路为 `rtmp://`(协议白名单直接解阻塞)。
- 虎牙(`线路1 FLV`/`线路1 HLS`)、B 站(多档 tier 线路)、快手、Twitch、抖音(HLS/FLV)等。
- iptv 等单线路平台:退化为单线,但「全组耗尽」仍走 completed→轮转恢复。

### 验证
- [x] `flutter analyze` 全仓库 No issues found(含 21 个测试替身)。
- [ ] 真机未重建运行;建议 `flutter build windows --release` 后带 `ZISHU_REAL_PARSER=true` 拉起,测斗鱼 RTMP 线路与各平台断流自动切线下一条。
- [ ] 未提交/未推送(用户本轮未要求);待验收后可提交。

## 2026-09-13 真实解析 benchmark(多平台耗时,未提交)

**结论**:直连 live_parser 重跑真实解析,各平台列表/房间解析耗时见下表(冷=首次,热=重复解析中位);多线路数据充分,断流 mpv 播放列表内部跳线下一条有料。benchmark 脚本:`packages/live_parser/tool/bench_real_parse.dart`(结果写同目录 `bench_real_parse.md`)。

| 平台 | browse 列表 | resolve(冷/热,中位) | 线路数 | 画质档 | 状态 |
|---|---|---|---|---|---|
| 斗鱼 | 225ms / 10间 | 795 / 76ms / 79 | 4 | 2 | live |
| 虎牙 | 229ms / 120间 | 190 / 118ms / 125 | 36 | 6 | live |
| B站 | 323ms / 22间 | 285 / 104ms / 285 | 32 | 4 | live |
| iptv | 0ms / 0间 | — | — | — | 占位无源,跳过 |
| Twitch | 504ms / 10间 | FAIL(播放令牌) | — | — | GQL 令牌偶发失败 |
| YY | 139ms / 10间 | 421 / 132ms / 164 | 3 | 3 | live |
| SOOP | 728ms / 10间 | 1770 / 0ms / 0 | 1 | 4 | live(仅 1 线) |
| 快手 | 659ms / 10间 | 617 / 364ms / 434 | 4 | 4 | live |
| 抖音 | 1344ms / 10间 | 401 / 188ms / 205 | 4 | 2 | live |
| YouTube | 1587ms / 10间 | 8096 / 0ms / 0 | 6 | 6 | live(冷受 yt-dlp 拉起开销 ≈8s,热命中缓存≈0ms) |

### 汇总
- 总耗时 25.6s(顺序串行全平台);resolve 成功 8 / 失败 1(Twitch 令牌)。
- 国内平台解析普遍 <1s,热解析 <200ms,体感即时。
- 多线路印证(断流自动切换数据基础):虎牙 36 / B站 32 / YouTube 6 / Twitch 5 / 斗鱼 4 / 快手 4 / 抖音 4 / YY 3 均 >1 线;**SOOP 仅 1 线**(退化为单线,断流只能走 completed→整组轮转)。
- 海外站:Twitch 偶发「未获取到播放令牌」(GQL 令牌接口抖动,需重试或 Cookie);YouTube 冷解析受 yt-dlp 子进程拉起开销(≈8s),热解析命中内部缓存近 0ms。
- [ ] 未提交/未推送;可选:`flutter build windows --release --dart-define=ZISHU_REAL_PARSER=true` 重建真实解析 exe 做真机播放验证(尤其斗鱼 RTMP + 各平台断流切线下一条)。
