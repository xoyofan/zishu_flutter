# todo — zishu_flutter

> 状态标记:[x] 完成 / [ ] 待办 / [~] 进行中。每轮任务完成后追加结论与工作项。

## 2026-09-24 平台显示补齐收口 + IPTV/CC 移除(完成)

**结论**:2026-09-24 显示补齐计划 Task 1-7 此前已合入,本轮完成 Task 8 收口;按用户口径移除 IPTV/CC 两平台全部代码,Twitch/虎牙上游代理为正常功能保留;虎牙确认直连(测试钉住)。本机 VS 基础设施被清理工具逐层破坏,经 COM/实例存储/channel manifest/MSI 四层手工修复后以新路径重装 D:\VS2022 恢复构建链。

### 本轮完成项
- [x] 拉取 master 56 提交;laya 调用约定写入全局 `~/.pi/agent/AGENTS.md`(score=数组/choice=对象/noul=对象,低置信度不作排序)。
- [x] 移除 IPTV 平台全部代码(解析轨 85b0471,-1088 行)与 CC 残留(parity 映射/legacy 能力表/品牌注释)。
- [x] UI 轨清理应用侧引用并刷新 golden(deb5096,diff 逐张核对仅位移无崩坏)。
- [x] Task 8:新建 `docs/ui-parity/platform-display-matrix.md`(9站能力/展示契约/startedAt 来源/空值语义/non-fixes);`docs/testing/windows-public-function-matrix.md` 去 iptv;看板回写。
- [x] VS 环境修复:真实 CLSID {177F0C4A-...} regsvr32、ProgramData 实例 state.json 重建、channel manifest updateUri 根级、vs_communitymsi 重注册;最终 `vs_community.exe --install --installPath D:\VS2022 --add NativeDesktop`(443 包/5.4G/exit 0),flutter doctor VS ✓。

### 验证
- parser: `dart analyze` 0 / `dart test` 420 过 + 9 skip。
- 根: `flutter analyze` 0;`dart run tool/check_design_tokens.dart` OK(28→28);`flutter test` 754 全过。
- `flutter build windows --debug -t lib/main.dart` ✓(`Built build\windows\x64\runner\Debug\zishu_flutter.exe`,135.5s)。

### 待办(下轮候选,缺口优先级见 laya 分析)
- [ ] A11 导航能力过滤:按注册表能力裁剪 navPlatforms,防未实现平台点击抛 StateError。
- [x] YY 弹幕 connector(纯增量,fixture 可测)——**已完成**:`YyDanmakuConnector` 移植现行 trident 协议(parser 434 测试全绿,详见 tasks 已验证记录)。
- [ ] 快手搜索能力(纯增量)。
- [ ] YY 弹幕真实在线 smoke(协议 fixture 已过,连通性未验)。
- [ ] 协议级另立任务:虎牙零消息、Twitch 弹幕连接、快手表情图片 URL、YouTube 个别频道源、飘屏重叠。
- [ ] 环境清理:旧残破实例 `D:\Microsoft Visual Studio\2022\Community`、ghost 副本 `D:\Program Files\Microsoft Visual Studio\2022\Community`、`%TEMP%\vs_community.exe`。

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

## 2026-09-13 播放器对齐 pure_live:多线路自动切换 + RTMP 协议放行(完成,已提交推送)

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
- [x] 真机重建运行:已 `flutter build windows --release --dart-define=ZISHU_REAL_PARSER=true` 重建(产物 `data/app.so` mtime 16:34:37,`zishu_flutter.exe` 14:56:47);schtasks 拉起运行(PID 13612,Console 会话 1,用户可见 GUI)。可手动验证:斗鱼 RTMP 主线路(此前无 `protocol_whitelist` 打不开 → 现在应直连)、各平台断流时 mpv 播放列表内部自动跳下一条线路。
- [x] 提交推送:`9d6afa9`(播放器修复)+ `8f216fd`(benchmark)已上 `origin/master`。

## 2026-09-13 真实解析 benchmark(多平台耗时,已提交推送)

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
- [x] 已提交推送:benchmark 脚本(`tool/bench_real_parse.dart`)+ 结果(`bench_real_parse.md`)随 `8f216fd` 上 `origin/master`;真实解析 exe 已重建并拉起运行(见上节验证)。

## 2026-09-13 播放页全屏重构:三态呈现模型 + 统一入口(已提交 943fd5f)

**结论**:全屏"坏"的根因不是实现不完整,而是**同一功能被两套互不通信的实现各管一半** —— `PlayView._immersive`(UI 本地 bool)与 `MediaKitLivePlayer.toggleFullscreen()`(window_manager 窗口全屏)互不读取,控制条又自复刻一份 F 键绑定 → 3 个入口、2 个状态源。已按 pure_live 的「单一真源 + 单一入口」重构为三态(`normal / widescreen / fullscreen`)+ 画中画,并补齐 4 个真 bug。

### 本轮完成项
- [x] 新增 `lib/src/platforms/common/playback/play_screen_mode.dart`:`PlayScreenMode { normal, widescreen, fullscreen }` + `hidesChrome / wantsSystemFullscreen / isWidescreen / isFullscreen / label`。
- [x] 新增 `lib/src/platforms/common/playback/window_presentation.dart`:`WindowPresentation` 单例(全屏 + PiP 的唯一去处)。`setFullscreen(bool)` **幂等**(目标态 == 当前窗口态即不调原生)+ `_fullscreenTransitioning` 防重入(桌面重复 `setFullScreen` 会让 Windows 侧边任务栏 work-area 抖动);`enterPip/exitPip` 记忆并恢复窗口 bounds / 置顶 / 最小尺寸,按视频宽高比缩到屏幕右下角。非桌面平台静默空操作 + 全部原生调用 try/catch 吞错。
- [x] 新增 `lib/src/features/play/application/play_screen_provider.dart`:**单一真源** `playScreenProvider`(autoDispose Notifier)持三态 + PiP;`apply(mode)` 先落 UI 态再驱动窗口;`resolveEscapePresentationAction` 纯函数分派 `pip > fullscreen > widescreen > popRoute`;`ref.onDispose` 复位窗口(用捕获的播放器实例 + 状态镜像,**onDispose 期不读 ref**)。
- [x] 新增 `lib/src/features/play/widgets/pip_surface.dart`:`PipResizeSurface` 转发 `LivePlayer.wrapPipSurface`(放 feature 层,避免 platforms→features 反向依赖)。
- [x] `live_player.dart`:`PlayerSnapshot` 不动;接口增 `setFullscreen(bool)` / `enterPictureInPicture` / `exitPictureInPicture` / `wrapPipSurface(Widget)`(后者默认透传;Windows 实现返回 `DragToResizeArea`)。
- [x] `media_kit_live_player.dart`:窗口相关全部委托 `WindowPresentation`;`wrapPipSurface` 仅 Windows 套原生交互壳(该依赖传递性引入 `dart:io`,只能落平台层,否则 Web 端编译失败)。
- [x] `main.dart`:补 `windowManager.ensureInitialized()`(原先只有 `MediaKit.ensureInitialized()`,`isFullScreen()` 的边界与状态同步缺保障)。
- [x] `player_controls.dart`:① 删除内层 `CallbackShortcuts`(快捷键唯一宿主 = 播放页);② 增 `screenMode` + `onToggleFullscreen / onToggleWidescreen / onTogglePip` 三个对称回调;③ 全屏图标/tooltip/激活色随态切 `fullscreen ⇄ fullscreen_exit`;④ 新增「网页全屏」按钮;⑤ 画中画由占位改实装。
- [x] `play_view.dart`:① 布局按 `hidesChrome` 切(沉浸/网页全屏 = 铺满 + 隐藏房间头与侧栏;PiP = 套 `PipResizeSurface` 且不渲染控制条);② 控制条包 `AbsorbPointer(absorbing: !_controlsVisible)` —— **淡出后不再误触**(旧 `AnimatedOpacity` 淡出后子级仍参与命中测试,不可见按钮可被点中、底部条带持续吞掉「点视频切播放」);③ hover 拆「舞台」「控制条」两处,鼠标停在控制条上时不进入隐藏倒计时;④ Esc 改 `HardwareKeyboard.addHandler` 全局处理,不受焦点影响。
- [x] **关键坑**:`CallbackShortcuts` 只在「焦点链」上生效;页面内无人持焦时 Flutter 把 primaryFocus 停在 `ModalScope` 根,按键根本不流经播放页节点。实测**点击音量 Slider 并不会把焦点移进控制条**(Slider 不请求焦点)→ F 静默失效。修法对齐 pure_live:舞台焦点 `autofocus: true`,让焦点链始终覆盖播放页。
- [x] 快捷键分工(**必须互不重叠**):`Space/M/F/W` → 页面级 `CallbackShortcuts`(尊重输入框焦点,且与按钮自身 Space 处理不重复——内层命中即停);`Esc` → 全局 handler。依据:`_dispatchKeyMessage`(焦点树)在 `handleRawKeyMessage` 里是**无条件调用**,与全局 handler 返回值无关,两边同绑会让一次按键被处理两遍。
- [x] 测试适配:21 个测试替身用 `implements LivePlayer`(默认实现不生效)→ 批量补 `wrapPipSurface`;`fullscreen_test.dart` 重写为三态 + 回归用例(点按钮进沉浸、焦点在滑杆上按 F、淡出后不误触、网页全屏不动系统窗口、PiP 隐藏控制条、Esc 优先级纯函数)。
- [x] golden 重生成:`play_style_follow.png` / `play_style_recommend.png`(控制条新增按钮导致像素变化,0.20%/2567px)。

### 验证
- [x] `flutter analyze`:**0 issue**。
- [x] `test/ui` 全量:**120/120 通过**。
- [x] `flutter build windows --debug -t lib/main.dart`:**成功**(18s,产物 `build\windows\x64\runner\Debug\zishu_flutter.exe`)。

### 待办(后续)
- [x] 提交推送:UI 轨已随 `943fd5f` 提交推送;`packages/live_parser/tool/bench_real_parse.dart` 属解析轨,已排除未混入。
- [ ] 真机验证:控制条「网页全屏 / 全屏 / 画中画」三按钮 + F/W/M/Space/Esc 快捷键 + 淡出唤醒 + 进出全屏聚焦复位。
- [ ] 可选增强:双击视频进全屏、进房默认全屏设置项、PiP 多显示器 work-area 适配(当前单显示器优先,按主屏逻辑尺寸算右下角)。

## 2026-09-13 UI 分支:关注页视图/列表布局 + 推荐卡片高度修正(feat/ui-follow-layout)

**结论**:新建 UI 专用分支 `feat/ui-follow-layout`(基于 `86b1417`)。针对「关注页列表/视图模式不对齐 + 卡片高度过高底部留白」三处修正:(1) 卡片密度元信息区高度预算 106→76,消除底部约 30dp 空白;(2) 单行密度由四列表格改为**纯文字流式 Wrap** —— 只留主播名(平台色)+ 在线人数,宽度按内容自适应、横向排满换行(对齐用户诉求:不要缩略图/分类/标题);(3) 播放页侧栏推荐/关注卡片由固定 `childAspectRatio=0.86` 改为按实际列宽推导,窄侧栏下不再把卡片拉高留白。参考基准:SFVideoLive `web/src/components/follow/`(FollowRoomPreviewView/RowView/TileView/Views)。

### 本轮完成项
- [x] `features/follow/views/follow_view.dart`:`_cardMetaHeight` 106→76(**合并后回归修复已改为 88,见本文档最后一节**);`FollowDensity.row` 分支 GridView 多列表格 → `SingleChildScrollView + Wrap`;删 `_rowColumnExtent`。
- [x] `features/follow/widgets/follow_entry_row.dart`(重写):纯文字 chip —— 主播名(FollowAnchorName 平台色)+ 人形图标/时钟 + 人数(离线「未开播」)+ 特别关注 ★;批量模式前置复选框;保留 `follow-entry-{site}-{roomId}` 锚点与组件签名(21 处调用/测试兼容)。
- [x] `features/play/widgets/play_room_grid.dart`:`PlayRoomGrid` 改 `LayoutBuilder` 按列宽推导纵横比(封面 16:9 + 元信息 36dp),替换固定 0.86。
- [x] `test/ui/follow_view_test.dart`:「特别关注星标」用例由单行模式改为卡片模式(单行已无行内操作按钮,操作仅卡片密度提供)。
- [x] golden 重生成 5 张(follow_style_card/tile/row + play_style_recommend/follow)。

### 验证
- [x] `dart analyze lib/src/features/follow lib/src/features/play`:No issues found。
- [x] `flutter test test/ui/follow_view_test.dart`:4/4 通过;`follow_style_shot_test.dart`:5/5(golden 更新)。
- [x] 已合入 master(merge commit,分支保留);后续可重建 exe 做真机视觉验证。

### 待确认/后续 UI 项
- [ ] 「横向按长度顺序往下排列」当前实现为**宽度按内容自适应 + 保留开播优先排序**;若需按主播名长度重排,可再调。
- [ ] 单行密度已无行内操作(特别关注/提醒/删除),增删改走「批量管理」;若需单行快捷操作需另议。


## 2026-09-13 主分支合并 UI 分支并推送 + 关注页卡片溢出回归修复

**结论**:master 已合入 `feat/ui-follow-layout` 并推送;合并后跑全量用例时暴露一处**分支引入的回归**,已定位修掉。

### 提交链
| commit | 内容 |
|---|---|
| `943fd5f` | `feat(play)`: 播放页三态全屏 + 画中画 + 控制条交互修复(UI 轨 34 文件) |
| `81bcbef` | `feat(ui)`: 关注页视图/列表布局 + 推荐卡片高度修正(来自分支) |
| `5f1b9d3` | `merge(ui)`: 合并提交(含冲突解决与回归修复) |

- 推送:`86b1417..5f1b9d3 master -> master`(fast-forward,远端原在 `86b1417`;本地 `refs/remotes/origin/master` 之前的 `a9d560b` 是过期引用,已按新 sha 直接写文件纠正)。
- `packages/live_parser/tool/bench_real_parse.dart`(解析轨,其他会话改动)**未纳入**本次提交。

### 合并冲突与解决
- `todo.md`:两侧小节都保留,全屏小节状态改为「已提交 943fd5f」。
- `test/ui/play_style_follow.png` / `play_style_recommend.png`:两侧都基于同一基线改过 → 二进制冲突。**不取任一侧**,在合并后代码上 `--update-goldens` 重生成。
- `test/ui/follow_view_test.dart`:自动合并成功(分支的「星标用例改卡片密度」与本次 21 处 `wrapPipSurface` 替身补丁共存,无冲突)。

### 分支引入的回归(已修)
- **现象**:合并后 `test/ui` 从 120/120 掉到 118/120 —— `mobile_phones_test` 的溢出矩阵在 5 个手机宽度(360/375/393/412/430)全挂 `follow` 页;`mobile_accessibility_test` 的 `textScaleNoOverflow` 也挂。
- **报错**:`follow_entry_card.dart:83` 的元信息 `Column` 纵向溢出 **9~11dp**(constraints `h=66.0`、内容 75.0)。
- **诡异点**:`[textScale] follow@1.0x: FAIL`,但 `1.15x`/`1.3x` **OK** —— 大字体反而没事。
- **根因**:分支把 `_cardMetaHeight` 定为 **76**,那是**内容净高**而非含 padding 的总高。内层 `Padding(6,4)` 占 10dp → 可用高只有 66,而内容实测 75 → 溢出 9。大字体不溢出的原因是 `metaHeightFor` 的放大量(系数 0.8)大于文字实际增长量,唯独 `scale=1.0` 时预算恰好不足。分支作者只跑了 2 个桌面尺寸用例(1900+ 宽),漏了移动端矩阵与字体档。
- **修法**:`_cardMetaHeight` **76→88**(内容 75 + padding 10 + 3dp 浮动)。保留分支「去掉底部空白」的意图(原 106 留约 21dp 空白),同时留足余量;`metaHeightFor` 继续负责大字体放大。
- 连带:卡片变高 → `follow_style_card.png` 按新高度重生成。

### 验证
- [x] `flutter analyze`:**No issues found**。
- [x] `test/ui` 全量:**120/120 通过**(含此前失败的移动端溢出矩阵与三档大字体)。
- [x] 远端核验:`git ls-remote origin master` = `5f1b9d3`;`git status -sb` 显示 `## master...origin/master` 无 ahead/behind。

### 未纳入本次提交(待用户决定)
- `docs/ui-compare/`、`docs/ui-reference/`(未跟踪,SFVideoLive 基准截图与 DOM 测量,抓取于 2026-09-09);
- `.flutter_tool_state`、`build_realparser_log.txt`(未跟踪的本机产物);
- `packages/live_parser/tool/bench_real_parse.dart`(解析轨)。

### 后续
- [ ] 真机验证:控制条三按钮 + F/W/M/Space/Esc + 淡出唤醒 + 进出全屏聚焦复位;关注页卡片高度真机观感复核。
- [ ] 本地分支 `feat/ui-follow-layout` 已合入且保留(远端无此分支);如不需要可删。

## 2026-09-13 关注页卡片亚像素溢出修复(`_cardMetaHeight` 88 → 92)

**背景**:上一轮把 106 → 76 修「底部留白」时把内容净高当成了总高;合并后又发现手机宽度溢出 9~11dp,改为 88。本轮发现 **88 在 1024 宽下仍差 0.194dp**。

**发现过程(排查链)**:
1. `follow_style_card.png` 每张卡片底部有一条深红横带(`#900000`,约 8dp 高)。像素扫描确认它**只在卡片密度 golden 出现**(tile / row / play_style_* / hover_* 均无)。
2. 逐一排除:overflow 传统黄黑指示器(全图搜 YELLOW=0)、颜色 token(无 #900000)、组件代码(无条纹绘制)、角标/封面元素(位置与宽度不符)。
3. 最终用**渲染树探针**(临时测试遍历 Element 树 + 打印 RenderBox 位置)定位:`FollowEntryCard` 元信息 Column 报 **`A RenderFlex overflowed by 0.194 pixels on the bottom` ×6**(正好 6 张卡片)。那条带就是 Flutter 的溢出警戒带 —— 新版 Flutter 在深色卡片上呈现为半透明红,不是传统黄黑。

**根因**:`_cardMetaHeight = 88` 时可用高 = 88 − 10(padding) = 78,而内容实测 **78.2** —— 差 0.194dp。溢出按字体 metrics 浮点累积,所以「整数估算卡临界值」必踩。

**为什么测试没抓到**:`suppressRenderFlexOverflow`(仓库 8 处测试共有的截图防噪约定)**吞掉了** `RenderFlex overflowed` 异常,金测试仍全绿;而真正做溢出断言的 `test/ui/workflows/`(layout_harness / mobile_phones / mobile_tablets / mobile_accessibility)只跑手机与平板宽度 —— **1024 桌面宽只存在于 suppress 的 golden 用例里**,构成尺寸矩阵盲区。

**修复**:`_cardMetaHeight` 88 → 92(= 内容 78.2 + padding 10 + 3.8dp 余量),保留「去底部空白」意图(原 106 留约 21dp 空白,现约 15dp)。

**验证**:
- 探针溢出事件 **0**;`test/ui` **120/120**;`analyze` 0 issue。
- `follow_style_card.png` 重生成,**22856 → 21988 B**(警戒带消失,图更简单故体积变小)。

**后续建议**:溢出矩阵应补一档桌面宽度(如 1024/1280),否则同类亚像素溢出只会继续被 suppress 掩盖。

## 2026-09-13 关注三处口径修正(排序 / 播放页只列在播 / 列表视图去缩略图)

用户口径:「关注里应该按超关、关注、没直播的来排列。播放页不用显示不直播的。列表模式前面不用房间缩略图。」

**1. 排序改三档(超关 → 开播 → 未开播)**
- 新旧口径对比:旧 = 开播优先,同状态内超关置前 →「超关但未开播」会被沉到**普通开播关注之后**。新 = 超关一律置顶(即便未开播),其余按是否开播分档,未开播沉底;档内按关注时间倒序。
- 抽为单一来源 `lib/src/features/follow/application/follow_sort.dart`(`FollowSort` / `followSortRank` / `sortFollowEntries` / `visibleFollowEntries`):**关注页与播放页侧栏原本各写一份 sort,极易漂移**,本次合并为一处。`FollowSort` 枚举从 follow_view.dart 迁出。
- 注:fixture 6 条里两条超关恰好都开播、唯一离线是非超关,故新旧口径**在该数据下顺序相同** —— 关注页 3 张 golden 未变,但有 11 例纯单测覆盖「超关未开播置顶」这条规则。

**2. 播放页侧栏只列在播**
- `_FollowPanel._visible` 改走 `visibleFollowEntries(..., liveOnly: true)`。理由:正在看直播时,侧栏列一串没开播的房间既占位置又点不进去。
- 影响 golden `play_style_follow.png`:6 张卡 → 5 张(离线那张被过滤)。

**3. 列表视图去行首缩略图**
- `PlayRoomRow` 删掉行首 44dp 封面 + 前导 `initial` 变量,改为纯文字两行(主播名 + ★ + 标题)。行高 52 → 约 40,一屏多看几条;想看封面切回网格视图。
- 注意:`PlayRoomGrid` 的「网格」视图不改,仍保留 16:9 封面。

**验证**:`analyze` 0 issue;全量测试 **306 passed**(原 294 + 新增 11 + 1);golden 已重生成。

## 2026-09-13 虎牙「流反复中断」根因修复:恢复重解析链路 + 上游对齐工具

用户症状:看虎牙直播一段时间后,直播流反复中断、每次都在自动重试却起不来。

**根因(两个,都已修)**:
1. **wsTime 租约被砍 60%**(live_parser anti_code.dart):自造 `wsTime=(now+110624ms)/1000` ≈ now+110s,而服务端 anti_code 自带 wsTime ≈ now+284s。CDN 按「wsTime 是否已过」判有效性(过期一律 403、未来值放行)→ 我们生成的地址天生短命。修:取两者中更晚者(服务端值已过期则退回自造值,避免开场即 403)。
2. **恢复路径复用已过期地址**(play_provider.dart):所有重开路径(retry/_openSelected/看门狗轮转)都用开流时那批地址,只有首次 build 才 resolveRoom。虎牙是签名平台,地址时效 < 观看会话 → 播放器反复重开失效源。这正是 pure_live `LivePlayRecoveryResolver` 契约注释警告的情形。

**修复链路(三层对齐)**:
- live_parser:`RoomRecoveryResolver` 契约(继承 RoomResolver,使 is 探测可类型提升)+ `CachedRoomResolver` 实现之(recoverRoom 先失效键再委托内层)+ 虎牙实现(无状态,恢复即重新签名取流)。
- 播放层:`LineRecoveryAware` 可选能力接口(不动 LivePlayer 本体,20+ 测试替身零改动)+ `PlaybackRecoveryPolicy` 恢复节流(最小间隔 40s,必须 < 一轮重试总时长 108s,否则恢复来不及兜底);重试耗尽先恢复、拿不到新地址才交终局错误卡片;stop() 重置节流。
- 编排层:play_provider `_open` 统一装恢复回调(首次进房也要有);`_recoverLines` 走 `RoomRecoverer` 绕开 60s 短缓存重新解析,并把新地址落回状态(否则手动切线/切档又退回过期地址)。

**踩坑**:
- Dart 的 `is` 探测对「非子类型接口」不产生类型提升:`RoomResolver` 变量 `is RoomRecoveryResolver` 通过后仍调不到 `recoverRoom`(三处连环报错)。解:能力接口继承基础接口(RoomRecoveryResolver→RoomResolver、RoomRecoverer→RoomSource);LivePlayer/LineRecoveryAware 无继承关系,用 `if (player case LineRecoveryAware aware)` 对象模式探测+绑定。
- Dart `Process.runSync` 跑 git 按系统 GBK 解码,中文 commit 标题乱码 → 须显式 `stdoutEncoding: utf8`。

**验证**:live_parser `dart analyze` 0 issue、`dart test` 260 passed(+9 新);App `flutter analyze` 0 issue、全量 **312 passed**(+6 恢复节流)。

**上游对齐工具**(「解析直接用 pure_live 代码」讨论的落地):不抽它的库(解析层被 UI 层 GetX 反向绑死 + AGPL-3.0 传染 + 对上游做手术后反而更难合并),改为「抄契约不抄代码」:新增 `packages/live_parser/tool/upstream_parity.dart`,`dart run tool/upstream_parity.dart --since 60` 产出平台对照矩阵(上游独有=cc、我方独有=youtube)+ 上游近期变更映射 + 待人工审阅清单。

遗留:真机验证虎牙长看(>10 分钟)不再反复中断。

## 2026-09-13 播放事件文件日志:让真机验证可被外部观测(「执行测试验证,但是你能检测到Log吗」)

**问题**:用户问「你能检测到 Log 吗」。实测答案分两半:
- 测试 runner 的输出能全量捕获(这是"测试验证"的部分);
- **运行中 exe 的日志此前完全看不到**:release 的 Windows GUI 进程无控制台,
  `print` 输出被丢弃;schtasks 拉起时连 stdout 管道都没有。`lib/src` 里原有
  日志设施为**零**(grep 证实)。真机验证虎牙断流修复时,外部只能看画面,内部
  发生了什么(reopen 几次?恢复拿到新地址没?)全靠猜。

**方案**:新增 `lib/src/platforms/common/playback/playback_log.dart`——
低频播放事件落文件 `%APPDATA%\zishu_flutter\logs\playback.log`:
- 只记生命周期事件:open(进房/换新地址) / reopen(看门狗重连,含 attempt/limit/host) /
  recover_request|ok|fail|skip(恢复重解析) / resolve_ok|fail|skip(编排层重新解析,
  含站点与主机名) / mpv_diag(mpv 原始诊断,**去重后**落盘,截断 160 字) /
  playing_ok(出帧,含 afterRetries,可量出中断→恢复耗时) / give_up / stop;
- 同步追加、>2MB 轮转 playback.old.log、任何 IO 异常熔断静默——日志器绝不弄崩播放;
- `Uri.tryParse(url).host` 记入每条线路事件:验证「恢复是否真的换了源」的关键线索。

**接线点**:`media_kit_live_player.dart`(mpv 事件归一层)+ `play_provider.dart`
的 `_recoverLines`(解析层)。测试替身走 FakeLivePlayer,不触日志,零影响。

**回答用户**:现在能检测到了——读那个文件即可。验证姿势:看虎牙 2-3 分钟
(或等到断流),说一声,读日志就能判断:断流时走了 reopen 还是 recover、
恢复拿到的 host 是否变化、give_up 是否出现。

**验证**:`flutter analyze` 0 issue;test/features/playback 56 passed(+3);
live_parser 260 passed;App 全量 312 passed(改动前基线)。Release 已带日志重建。

## 2026-09-16 拉取最新代码 + 健康基线盘点(现状记录,无代码改动)

**结论**:`master` = `origin/master` = `a29ec00`,ahead/behind **0/0**;fetch 走仓库内 `http.version=HTTP/1.1` + `http.sslBackend=schannel` 直接成功(未走 REST 兜底)。四道门禁全绿,工作区只剩 2 个已知排除的本地产物。**发现一处需裁决的产物问题**:`docs/ui-compare/baseline/` 24 张截图全是 404 错误页。

### 仓库与分支
- [x] `git fetch origin --prune` 正常;master 与远端零偏差,无待合并内容。
- [x] `feat/ui-follow-layout`(81bcbef,本地+远端,已全量合入 master)。
- [x] `origin/feat/A2-danmaku`(a568579)仅 1 个早期草稿领先,内容已被 master 超越 → 维持 09-13 的「不合并」判定。
- [x] 09-15 两次提交此前未记入 memory,已补记(`e94c207` mpv `ao=wasapi`+`video-sync=audio` 修无声/周期性回退;`a29ec00` 收录 UI 参考与比对产物)。

### 健康基线(实跑)
| 门 | 结果 |
|---|---|
| `flutter analyze` | No issues found(6.7s) |
| `flutter test` 全量 | **315 passed / 0 failed**(56s) |
| `packages/live_parser` `dart analyze` | No issues found |
| `packages/live_parser` `dart test` | **260 passed / 10 skipped** |

无 generated_* 幻影 diff。

### 待裁决:`docs/ui-compare/baseline/` 是 24 张 404 错误页
- 同一视口下不同页面 **md5 完全相同**(1920 档 4 张 = `31c90f021d67`);打开内容是 `Error response / 404 - Nothing matches the given URI`。
- 抓取 URL 打偏产生的空壳,却已随 `a29ec00` 入 master → **按它做像素比对只会得到全错结论**;应替换为 `docs/ui-reference/shots/`(40 张真图)或直接删掉。
- [ ] 处置 baseline 404;`docs/ui-compare/replica/`(Flutter 侧)当前为空目录,需抓真机/离屏截图填上。

### 看板状态与现实不符(需回写)
- [ ] `tasks.md` 的 A3/A5/A6/A8/A9/A10/A11 表格仍写 `[ ]`,但已落地:实测 **A11 导航能力过滤确已落地**(`platform_brands.dart` 按 `capabilities.browse/roomSearch/anchorSearch` 过滤,随 `e8e3715` 合入);G1/G2 同理(`parser_sources.dart` + `useRealParser` 已实装且真机流过真实播放)。
- [x] 核实 **A14 确未落地**:`features/danmaku/domain/` 只有 settings/style/track,无 `danmaku_track_allocator.dart`(A2 版调度器仍在 `a568579`)。

### 下一步候选(按优先级,待用户裁决)
1. [ ] **UI 对齐复刻主线**:处置 baseline 404 → 抓 Flutter replica → 做 `tasks-ui-refine.md` T1-T5(error 色 `#E55050`/动效 150/250ms、抽屉 rail 28px、房卡平台 badge 左下→右下、底栏 6 项、golden 更新),文件级隔离可并行。
2. [ ] **`docs/ui-parity/visual-confirm.md` 5 项待办**:底栏 4 vs 6 项复核、四象限徽章模板入 spec-layout、PlayMetaBar 规格、顶栏分断点高度实测、mobile 顶栏拆两行。
3. [ ] **真机验收遗留**(09-13 挂至今):控制条三按钮 + F/W/M/Space/Esc + 淡出唤醒 + 进出全屏聚焦复位;可配合 `%APPDATA%\zishu_flutter\logs\playback.log` 复核。
4. [ ] **A14 弹幕轨道调度对齐 SFVideo**:取回 `a568579` 的 `danmaku_track_allocator.dart`,保留主线 `widthRatio` 安全间隙 + `allocateReusingEarliest`。
5. [ ] **看板状态对齐** + **P8 Dart streaming-server**(唯一未开始的 P 卡)。


## 2026-09-18 播放页套壳 + 返回可用 + 全局返回快捷键 + 斗鱼黑屏闪断根治(完成)

**结论**:三处真机问题在同轮闭环——(1) 点推荐房切房后左上角「返回」失效(go 重置整栈 → `GoError: There is nothing to pop`);(2) 播放页缺应用顶栏,与参考实现 `AppLayout` 包裹 `PlayView` 的结构不一致;(3) 斗鱼**每几秒黑屏闪一下再恢复**,根因是解析侧把 `hlsH5Preview` 预览流插在每档线路**表头**,而 `StreamQuality.preferredLine` 是「有 hls 就选 hls」,于是首选恒为秒级 token 的预览切片。

### UI 轨
- [x] `app_router.dart`:播放页路由改由 `_PlayRoute` 承载 —— 套 `AppShell`(顶栏常在),`watch(playScreenProvider).hidesChrome` 驱动 `chromeHidden`。
- [x] `app_shell.dart`:新增 `chromeHidden`;沉浸态不渲染顶栏/底栏与 hover 浮层(对齐 `html.play-webscreen .nav-sidebar{display:none}`)。关注浮层点主播格改 `push` + 先收浮层(`_openRoom`),不再用 `go` 把壳层页换掉。
- [x] `windows_app.dart` + 新增 `app_back_shortcuts.dart`:全局返回快捷键 —— **鼠标侧键(kBackMouseButton/0x08)** 与 **Alt+←**;`canPop()` 为假时静默,绝不抛 GoError(Alt+→ 未接:go_router 无 forward)。
- [x] `play_side_panel.dart`:关注/推荐切房由 `go` 改 **`pushReplacement`** —— 旧播放页被卸载(media-kit 会话随 autoDispose 收干净),下层浏览页保留为返回目标。
- [x] `play_view.dart`:`_goBack()` 取代裸 `context.pop()`(栈底退化为该平台首页);返回回调由 `_RoomHeader` 显式注入。
- [x] 测试:新增 `test/ui/workflows/back_shortcuts_test.dart` 5 例(Alt+← / 侧键 / 栈底静默 / 左上角返回 / **切房后仍能返回**)。
- [x] 既有用例按新契约更新:`layout_test` 改「套壳 + 新增沉浸态收 chrome」2 例、`navigation_test` 播放页期望改为有壳、`danmaku_test` 「我的关注」限定侧栏子树、`mobile_*`/`platform_workflow` 注释口径。
- [x] golden 重生成(`play_style_card/follow/recommend/row` 中两张播放页)并同步 `tool/screenshots/zishu/`。

### 解析轨(斗鱼)
- [x] `douyu/lines.dart`:`appendHlsLine`(表头插入)→ **`appendHlsFallbackLine`**(仅 FLV 全灭时兜底);新增 `douyuPlaybackHeaders(roomId)`(Referer/Origin/UA/`dy_did` Cookie,与 pure_live `DouyuUtils.playbackHeaders` 同源)。
- [x] `douyu/douyu_site.dart`:两处 `StreamLine` 注入播放请求头。
- [x] 对照 pure_live 认定差异:pure_live **从不使用** `hlsH5Preview`,只用 getH5PlayV1 的 FLV/混合地址;且对每个平台都注入播放头(本仓此前斗鱼 line headers 为空)。
- [x] 实网探针验证:改后各档 `preferred=线路7 FLV`,`headers` 非空;实机日志此前为 `host=hlshw3a.douyucdn2.cn`(HLS)+ 每 5s 一次 `reopen`/`Failed to open …m3u8`。
- [x] 测试:`lines_test` 改 HLS 兜底 3 例 + 播放头 2 例;`room_resolver_test` 期望改「FLV 优先 + 带头」。

### 验证
- `flutter analyze` 0 issue;App 全量 **320 passed / 1 failed**(唯一失败为 `latency_test` 斗鱼墙钟基准,单跑 151ms 通过 → 已知网络抖动)。
- `packages/live_parser`:`dart analyze` 0 issue;**263 passed / 10 skipped**。
- Release 重建(`--dart-define=ZISHU_REAL_PARSER=true`)并拉起真机验证。

### 待办
- [ ] 真机复核斗鱼长播(≥10min)不再出现周期性闪断;必要时再对比 FLV 各 CDN 的稳定性。
- [ ] Alt+→(前进)未实现:需要宿主自维护前进栈。
- [ ] `latency_test` 墙钟 500ms 阈值在整机跑套件时过紧,建议改「单跑计分 + 套件内只告警」。

## 2026-09-18 设置项 ↔ pure_live 全量对照:三条死设置接线(完成)

**结论**:逐字段比 `lib/src/**` 与 pure_live 同名文件后确认 —— 设置**模型**完全一致(settings_provider/danmaku_settings 逐行相同),差的是**消费点**:本仓有三处设置只存偏好、播放/渲染侧不读,表现为"改了没反应"。

### 死设置清单(改前)
| 设置项 | 本仓(改前) | pure_live | 影响 |
|---|---|---|---|
| 线路格式 auto/HLS/FLV | 仅设置页 + 侧栏下拉;**play_provider 不读**(内联 `_pickQuality` + `quality.preferredLine`) | `play_selection.dart` 的 `pickStreamLine` | 切档后总走 HLS;斗鱼 HLS 预览线即黑屏闪断源 |
| 平台默认画质 | 内联 `_pickQuality` **只做精确同名**,真实档名带后缀(斗鱼「原画2K60」)必失配 → 回落首档 | `pickPlayQuality` 精确 → 双向包含 → 首档 | 「按平台默认画质」形同虚设 |
| 弹幕样式(透明度/字号/速度/显示区域) | provider/面板齐备,但 `_DanmakuLayer` **只传 messages/enabled**;侧栏是同名**死滑杆**(`onChanged: (_) {}`),`DanmakuSettingsPanel` 无挂载点 | overlay 注入四项 + 设置页/侧栏共用 `showDanmakuSettingsDialog` | 细粒度设置完全进不去 |
| 主题模式 | 仅持久化,`WindowsApp` 恒 `ZishuTheme.dark()` | `ZishuTheme.modeOf` + theme/darkTheme/themeMode | 浅色不可用 |

### 本轮落地
- [x] 新增 `features/play/application/play_selection.dart`(`pickPlayQuality`/`pickStreamLine`,与 pure_live 同源)并接入 `play_provider`:**进房解析与恢复重解析两条路径都按线路格式偏好选线**。
- [x] 新增 `danmaku_settings_dialog.dart`;`_DanmakuLayer` 注入 opacity/fontSize/speedFactor/displayAreaRatio(接线前是死控件);侧栏设置 tab 的死滑杆 → 「弹幕样式」按钮(`play-side-setting-danmaku-style`);设置页补回「弹幕样式」行(`settings-danmaku-style`)。
- [x] 主题接线:`ZishuTheme.modeOf` + `WindowsApp` 浅/深/跟随系统;**默认改深色**(docs/implementation-plan「默认深色 #181818」「Windows 第一轮以深色高还原为验收基线」)—— 若随系统,浅色 Windows 上会整体翻白,偏离已验收基线。
- [x] 测试:新增 `test/features/playback/play_selection_test.dart`(11 例,含「指定 flv 时优先 flv」);`side_panel_features_test` 加 A9b(入口开对话框 + provider→overlay 接线);`settings_test` 默认主题改深色断言。

### 结论:其他平台播放**不需要**按斗鱼那样修
- 斗鱼的问题是**接口选择**(选了 `preview=1` 的预览切片)+ 缺播放头;其余平台的播放地址来源与 pure_live 一致(huya/bilibili/douyin/youtube/yy/soop 的播放头已由 `9b8ec04` 补齐)。
- 播放韧性内核(d09a701)、房间音量/睡眠定时(9fcc414)、窗口几何(d0a6106)均已由同仓另一轨补齐,与 pure_live 同源。

### 遗留(未做,待裁决)
- [ ] **弹幕屏蔽词/屏蔽用户**:pure_live 有 `danmaku_block_provider.dart` + `domain/danmaku_block.dart` + `domain/danmaku_message_gate.dart`(共 202 行)+ 面板「屏蔽」段 + session 两处调用;本仓三文件皆缺。
- [ ] 顶栏 `nav-theme` 仍是死按钮(两个项目都一样):主题设置生效后建议接成 深色⇄浅色 切换,并按目标态改 label。
- [ ] 设置页「streaming-server 地址」在 Windows 产品链路上无消费者(Web 端才用)。

### 验证
- `flutter analyze` 0 issue;App 全量 **341 passed / 0 failed**(此前抖动的 latency 本轮亦通过)。

## 2026-09-18 并行三轨:关注 tab 修复对齐 / 推荐跨平台重做 / nav-theme 与设置收敛(完成)

**结论**:三轨 worktree 隔离并行,patches 全部干净落地;父代理完成推荐面板接线与一处**并行引入的回归**修复(`didUpdateWidget` 在构建期改 provider);App 全量 **357 passed / 0 failed**,analyze 0 issue。

### 轨 1:播放页侧栏「关注」(用户报"关注没显示")
- [x] 根因:`_FollowPanel` 用 `visibleFollowEntries(..., liveOnly: true)` 丢掉**所有离线房间**;web 的 `isPlayFollowVisible`(`followDisplay.ts:235`)是「在播/replay ∨ 离线超关」。
- [x] `follow_sort.dart` 新增 `isPlayFollowVisible` + `playSidebarFollowEntries`(平台筛选 + web 可见性 + 超关→开播→未开播排序);旧 `visibleFollowEntries` 保留不动(他人测试依赖)。
- [x] `_FollowPanel`:新谓词 + web 空态文案「暂无在播关注;离线超关主播会保留在此列表」+ **分页 48**(滚到距底 ≤96px 追加,底部「向下滚动加载更多…」)+ 新锚点 `play-side-follow-site-{id}`(原按文本定位与卡面角标撞车)。
- [x] 新增 `play_follow_panel_test.dart` 6 例。

### 轨 2:播放页侧栏「推荐」(用户报"推荐方法不对")
- [x] 根因:旧实现 `browseRoomsProvider(site, cid)` = 同平台同分类一页;web `usePlayRecommend.ts` 是**跨平台相关推荐**。
- [x] 新增 `play_recommend_provider.dart`(564 行)+ `play_recommend_panel.dart`(333 行)+ 测试 8 例:站点顺序 douyu/huya/bilibili/douyin、每站 3 条**交错合并**、分类映射(按分类名匹配目标平台分类索引)→ 否则/兜底该站热门、`site:roomId` 去重、剔除当前房间、只留在播、滚动分页、骨架占位、「当前分类暂无推荐,已为你展示热门直播」提示。
- [x] 父代理接线:`_RecommendPanel` 退化成薄壳(传 site/roomId/cid/category + `pushReplacement`),锚点 `play-side-recommend-panel` 与 `play-recommend-room-{site}-{roomId}` 保持不变。
- [x] **并行回归修复**:`PlayRecommendPanel.didUpdateWidget` 在父层构建期同步 `loadFirst()` → Riverpod 抛「Tried to modify a provider while the widget tree was building」(真实播放页 payload 后到,必走这条路径;A10 用例捕获)→ 改 microtask 延迟,与 `initState` 同口径。

### 轨 3:nav-theme 切换 + 设置页收敛
- [x] `_TopNav` 的 `nav-theme` 死按钮 → `_NavThemeAction`:深色⇄浅色切换写 `setThemeMode`,label/icon 反映**点击后目标**(深色时显示「浅色」,与 web `NavSidebar.vue` 一致);`system` 用 `platformBrightnessOf` 解析当前主题。
- [x] 设置页删除「服务器 / streaming-server 地址」组及配套状态(`serverUrl` 字段与持久化保留给 Web 端)。
- [x] 新增 `nav_theme_test.dart` 2 例;`settings_test` 改为断言该文案与 TextField 均不出现。
- [x] golden:`play_style_recommend.png` 重生成(推荐面板渲染变化),同步 `tool/screenshots/zishu/`。

### 已知未做(待裁决/后续轨)
- [ ] **侧栏预览卡缺「左下分类 chip」**:web 四象限模板为 左上分类/左下平台/右上直播中/右下热度,本仓 `PlayRoomCard` 是 左上★/右上平台/右下在线 → 归类到下一波 R3(会动 golden)。
- [ ] 关注状态刷新链路(web `useFollowStatus` 60s + focusCategory + 实时轮询)本仓缺,离线卡只能显示「未开播」而非「上次 MM:DD HH:mm」(`FollowEntry` 无 `lastLiveAt`,数据层缺口)。
- [ ] 移动端底栏 `nav-theme`(label「主题」)仍是空 onTap —— 与顶栏同一个坑,归入下一波壳层轨(B2)。

## 2026-09-18 日夜主题:背景/前景真正随主题切换(部分完成,壳层待并行轨)

**结论**:旧实现切主题只切了 `MaterialApp.themeMode`,页面背景/侧栏 chip/文字色大量写死深色常量。本轮把 `AppTypography` 去色、补齐主题化语义 tokens、并把播放页整块主题化;新增 `light_theme_test`(含静态守则)钉住「切了确实生效」与「不准再写死」。

### 完成
- [x] `AppTypography` 去色(原 TextStyle 写死 `AppColors.textPrimary/secondary` → 浅色下白底白字),新增 `context.textTitle/textBody/textSecondary/textCaption` 与 `fallbackPrimary/Secondary`(方案与 pure_live 同源)。
- [x] `ZishuTokens` 合并 pure_live superset:`statAudience/statVip/statSvip` + `playFollow*`/`playSuper*`(深浅两套) + 角标轨新增的 `coverScrim/coverScrimText/promoBadge`;补齐 copyWith/lerp。
- [x] 播放页主题化:`play_view.dart`、`play_side_panel.dart`、`play_meta_bar.dart` 共 28 处 `AppColors.*` → `context.tokens.*`(深色取值与旧常量逐位同值,深色渲染不变)。
- [x] 新增 `test/ui/light_theme_test.dart` 4 例:默认深色;切浅色后 tokens/scaffold 背景色切换;播放页「关注」chip 底色随主题换(深红→浅色),浅色下不残留深色;静态守则:除 tokens 定义文件外**不得**再出现 `AppColors.*`(当前 allowlist 仅 `app_shell.dart`,附 TODO)。
- [x] golden 未变(深色逐位同值),`follow_style_*`/`hover_*`/`play_style_*` 全绿;全量 395 passed(仅 3 条 latency 网络基准因两个并行 lane 抢 CPU/网络超阈值失败)。

### 待办
- [ ] `app_shell.dart` 74 处写死色(顶栏/底栏/浮层)等 `app-follow-status-refresh` 轨落地后统一替换,并移除静态守则里的 allowlist。
- [ ] `AppTypography.*` → `context.textX` 的机械替换(127 处/36 文件):去色后颜色已随主题,替换属一致性收口。

## 2026-09-18 在播状态刷新链路 + hover 只列在播 + 我的分类收藏星(完成)

**结论**:顶栏「我的关注」hover 此前显示的是**加入关注时的陈旧快照**(整条在播刷新链路根本不存在),且没有在播时还会兜底列出全部条目。本轮并行两轨补齐「解析能力 → 应用链路 → 定时驱动 → hover 语义」,并顺带修掉收藏竞态、补上分类收藏星。

### 解析轨(commit 8bcca90)
- [x] 新增契约 `RoomSummaryRefresher`(只取元信息,不解析播放地址/不签名/不缓存)+ douyu/huya/bilibili/douyin 四站实现;`CachedRoomResolver` 透传且**不走短缓存**。
- [x] 测试:四站 `room_summary_refresh_test` + 注册表透传,逐条断言「刷新不碰取流/签名」;`dart test` 287 passed / 10 skipped。
- [ ] kuaishou/soop/yy 未实现(成本低可补);twitch/youtube 不宜轻量刷新;iptv 无单房间状态概念。

### 应用轨
- [x] `RoomRefresher` 契约 + `roomRefresherProvider`(fixture → null,保持零网络);`ParserRoomSource.refreshRoom` 静态 `is RoomSummaryRefresher` 探测(轨内先 dynamic 桥接,合轨后已改回静态)。
- [x] `FollowController.refreshStatuses({limit})`(移植 pure_live:并发 4 / 单条 10s 超时 / **失败保留原值** / online 以刷新为准但 cid 保留本地 / 最新 state 重建)+ 分批游标轮转 + `ref.mounted` 防御。
- [x] **定时驱动** `FollowStatusPoller`:周期 60s(对齐 web `followStatusHub` 最小间隔)、每 tick 16 条环状轮转、hover 打开时 `wake()` 补跑、无 refresher 时零 timer 零网络、失败静默。
- [x] 关注页刷新按钮由「假 600ms 延迟」改为真调 refreshStatuses。
- [x] hover 浮层:删掉「无在播则列出全部」的兜底(与参考实现相反),空态文案改「暂无开播」。
- [x] 「类似逻辑」逐处核对:`FollowEntry.isLive`(唯一判据)、`follow_sort` 三档、`play_side_panel._FollowPanel`(在播∨离线超关,与 hover 有意不同)、`browse_sidebar` take(3)、`room_card`、`anchor_provider.isLive`(不同源,仅记录)。

### 父代理补的两处
- [x] **收藏竞态修复**:`myCategoriesProvider._restore()` 会在用户已收藏后用存储回放覆盖 state(并发用例实测丢条目)→ 改为「本地已非空则不覆盖」。
- [x] **我的分类收藏星**(web `CategoryGrid.favoritable` + `PlayHeader.categoryFavoritable` 两处入口):分类页子分类 tile 右上角星标 + 播放页头部 `play-category-favorite`;收藏后描边/文字高亮,点击星标不触发 tile 选中(几何断言)。
- [x] 壳层 74 处写死色主题化完毕;`light_theme_test` 静态守则 allowlist 已清空(全仓仅 tokens 定义文件允许出现 `AppColors.`)。

### 验证
- `flutter analyze` 0 issue;`dart test`(parser)287 passed;App 全量 **409 passed / 1 failed**(`latency_test` douyu 墙钟基准,并行 lane 抢资源所致)。
- `play_style_follow/recommend` golden 因新增头部收藏星重生成并同步截图目录。

## 2026-09-18 移动壳层 + 路由语义 + 跨平台分类中文化 + 真机验收(完成)

**结论**:接续中断的 pi 会话(mission bdda5e43 的两条并行轨 `shell-mobile-align` / `category-display-map`),本轮把两条中断轨收口合并,并在**真机 release 验收**中抓到一个单测与 golden 都覆盖不到的映射缺陷(已修完并复验)。

### 轨 1:移动壳层对齐 web(commit 7c31ffc)
- [x] 抢救 pi worktree `pi-worktree-2eb5a6d9` 的散落改动(`app_shell.dart` + 2 个测试),reset 后只取目标文件提交,再取回 master。
- [x] 真机复验(窄窗 462x1078):底栏「首页 / 分类 / 我的分类 / 关注 / 搜索 / 动态 / 浅色 / 我的」与 web 移动端导航项集合一致。

### 轨 2:路由语义对齐 web(commit 8d16e76)
- [x] `/time` 让给 web 的「解析耗时」基准页;时间线改挂 `/timeline`(顶栏与底栏 `nav-time` 均指向 `/timeline`)。
- [x] 设置页新增「工具 → 解析耗时基准」入口(`context.push('/time')`,hint 标注「对齐 web /time」);修正「主题模式」hint。
- [x] 测试:断言改用**渲染结果**(`bench-run` 出现 / 设置页入口消失)而非路径字符串 —— `context.push` 不改 `routeInformationProvider.uri`。
- [x] 真机复验:顶栏「设置」点击进设置页,「工具」组可见「解析耗时基准 / 打开」。

### 轨 3:跨平台分类中文化(merge 90d8697,子代理轨 eb9dae7)
- [x] 映射真源移植:`assets/config/cross-categories.json`(328 条)+ `tool/sync_cross_map.dart` 生成器 + `lib/src/shared/domain/category_display.dart`(352 行纯函数);全站卡片/角标/侧栏/关注卡/时间线/播放页接线。
- [x] `CategoryColors.opaqueFor` 按 web `resolveCategoryThemeBase` 顺序解析(crossKey → alias → 条目 key → 显示名 → 正则 → 哈希兜底)。

### 轨 4:latency 阈值分档(commit 4c7e254)
- [x] 墙钟阈值分档(宽松 3000ms / 严格 500ms `ZISHU_LATENCY_STRICT`),≥500ms 只 `[latency-warn]` 告警;帧数断言不分档始终生效 → 消除整机套件的假失败。

### 真机验收发现的缺陷(commit 4bc473d,已修)
- [x] **现象**:全平台首页侧栏出现**两个「户外」**,且「体育」整项消失。
- [x] **根因**:侧栏分类网格(`browse_sidebar._CategoryTree`)把索引 item 平铺渲染并调 `displayCategoryName(site='all', name, cid)`;但 `all` 索引的 name 已是跨平台 canonical 中文名,web 侧**从不**以 `all` 调用该函数。而「体育」在映射表里被登记为「户外」的别名(`huwai.aliases` 含 `体育/运动/生活/旅游/IRL`)→ 被抢走改名。
- [x] **修复**:`displayCategoryName` 对 `site == 'all'` 恒等返回(回归 web 语义),附 2 条回归测试;真机复验侧栏 15 项唯一、体育/户外各出现一次。

### 门禁与验收
- App 全量 **470 passed / 0 failed**;`flutter analyze` 0 issue;parser `dart test` **287 passed / 10 skipped**;8 张 golden 重生成并同步截图目录。
- 真机 release(`--dart-define=ZISHU_REAL_PARSER=true`)重建:41.6s / 39.6s 两次成功,`data/app.so` mtime 更新(开关生效),真实数据到 UI、分类中文、路由、移动壳层逐项截图复验。

### 待办(下一轮 ready 项)
- [ ] **全平台分类键集与 web 真源不一致(重要)**:web `apps/web/src/config/hotCrossCategories.js` 的 `HOT_CROSS_CATEGORY_KEYS` 是 **25 个 key**(`lol sjz jx3 wzry hpjy cs2 dota2 cf yjwj ys bhxy aqtw tft hs valorant dnf dzpd dwrg hmwk jcc jql wudao huwai xingxiu yanzhi`),而 `packages/live_parser/lib/src/catalog/cross_catalog.dart` 的 `kDefaultCrossCategories` 是 **15 个手写 key**,与 web 仅 **3 个交集**(lol/dota2/valorant)。已验证 25 个 web key 在本地映射表 **25/25** 都能取到名称。
- [ ] **`/all/category/<key>` 的静默降级风险(必须与上条同批修)**:`cross_browse.dart` 用 `catalog.byKey(cid)` 精确匹配,key 不存在时 category=null → **过滤被整体跳过**,退化成全平台混排(比返回空列表更危险:看着有数据但语义错了)。因此「换索引 key」必须同时补齐匹配规则。

### 上述两条已修(commit 3983270)——全平台分类索引键集对齐 web 25 key
- [x] **单一数据源**:`tool/sync_cross_map.dart` 扩展为双产物 —— 除 app 侧 328 条全量表外,新增生成 `packages/live_parser/lib/src/catalog/cross_hot_categories_generated.dart`(25 个 HOT key 的 `{key, name, aliases, siteCids}`,顺序即 web 顺序)。生成脚本带 **fail-fast**:任一 HOT key 在源 JSON 缺失即报错退出(防将来漏 key 静默降级)。
- [x] **匹配规则派生**:`siteCids` 由 JSON 的 `douyu`/`huya` 顶层字段 + `sites.{bilibili,twitch,soop}.cid` 派生;原先只登记 douyu/huya 两站,现在 B站/twitch/SOOP 也走 cid 精确拉取(B站 lol=86 因此从「名称过滤」升级为「cid 拉取」)。
- [x] **精细规则不丢**:`cross_catalog.dart` 新增 `_kCrossHotOverlay` 手工 overlay,按 canonical key 覆盖 `contains`/`excludes`(如 `lol` 仍剔除 云顶/下棋/自走棋),把手写表压缩成一份「易误伤规则清单」便于审查回滚。
- [x] **旧 key 兼容**:`wangzhe→wzry` / `heping→hpjy` / `csgo→cs2` / `genshin→ys` / `crossfire→cf` / `outdoor→huwai` / `chat→xingxiu` 归一,旧 deeplink 与本地缓存不失效;web 无对应物的 `minecraft/sports/food/chess/acg` 移出索引。
- [x] **哨兵测试**:parser 新增「索引键集/顺序/展示名与 web HOT 25 key 完全一致」用例,并逐个断言 `byKey` 命中 + 名称一致(注释写明:漏 key 会让 `/all/category/<key>` 退化成不过滤混排);另加新旧 key 的 cid 命中用例。parser 测试 287 → **290 passed / 10 skipped**。
- [x] **Dart 约束**:`const` 列表不支持 `for` 元素、也不支持 const Map 下标取值 → 默认表改为运行期合成的 `final`,并给 `CrossCatalog` 换成「可空字段 + getter」以保住 `const CrossCatalog()` 零成本默认构造。
- [x] **真机验收**(release + `ZISHU_REAL_PARSER=true`):侧栏分类由 15 项变 **25 项且顺序与 web 完全一致**(英雄联盟/三角洲行动 → 剑网3/王者荣耀 → … → 户外/星秀 → 颜值);点新增 key「三角洲行动」进 `/all/category/sjz`,页头 25 项网格中该项高亮,且**所有房间卡分类角标均为「三角洲行动」**(平台角标横跨斗鱼/虎牙/抖音/快手)→ 过滤真实生效,未退化。
- [ ] **遗留口径不一致(新发现)**:`FixtureBrowseSource.fetchCategories` 忽略 `site`、恒返回写死的 3 组假分类,导致 golden/widget 测试**完全覆盖不到**新索引(改索引后 golden 仍全绿)。真实解析路径走的是 `CrossCatalog`,故该差异不影响线上,但测试保真度有缺口 —— 可考虑让 fixture 对 `site == 'all'` 返回 `CrossCatalog().toCategoryResult()`(会改 golden 与若干断言)。

### 其余 backlog
- [ ] `kuaishou/soop/yy` 轻量状态刷新;`RoomSummary.lastLiveAt/fans/audience` + `FollowEntry` 离线卡「上次开播时间」;侧栏预览卡四象限 chip(R3);移动壳层 `nav-theme` 空 onTap;`AppTypography.* → context.textX` 机械替换(127 处/36 文件);桌面 1920x1080 布局对齐(播放页底部工具栏/全屏抽屉)。

## 2026-09-18 对齐 SFVideoLive web:2 小时长任务(6 项全部落地)

执行计划:`docs/plans/2026-09-18-web-alignment-2h.md`。子代理因上游 429 全部秒挂,按预定兜底转为主代理串行执行(非沙箱直调 flutter/git);每个任务独立 TDD(先红后绿)。

### 落地项与 commit
- [x] **T4 token 对齐真源**(ebd9b88):`AppColors.error` F56C6C→**E55050**(web theme.css `--danger`);动效 120/200→**150/250ms**、curve→`Cubic(0.16,1,0.3,1)`(web main.css:74,84,85);新增 token 契约测试(railWidth=52 防回归断言钉死,作废内部分档 28px 的错误说法)。
- [x] **T5 控制条「飘屏弹幕设置」入口**(859e1a7):弹幕开关旁新增 `play-danmaku-settings`,复用侧栏同一份 `showDanmakuSettingsDialog`;**compact 归档**——实测 360/375/393dp 追加 48px 按钮会溢出(pagesOverflowMatrix 抓到 3 条 FAIL),窄屏仍可从侧栏进。
- [x] **T2 搜索 主播/房间 双档**(821dd59):默认落「房间」档(对齐 web `syncDefaultTab`);占位文案/空态名词随档切换;「进入直播间」(`search-submit-room`)与房间号直达仅在房间档;`PlatformBrandCatalog` 新增 `supportsAnchorSearch/supportsRoomSearch`。**已知残留**:web 双档走服务端 `type=anchors|rooms` 分流,flutter `SearchRequest` 无 type 字段,两档共用混合查询,待契约补参。
- [x] **T1 网格卡离线遮罩**(17bc4cf):共享 `CoverOfflineOverlay`(tokens.coverScrim=0xB8000000 ≈ web rgba(0,0,0,.72));置于角标之前复刻 web z2<z3 层级。**范围收窄**:原计划 LIVE/录播角标经真源核实不适用——web `hideLiveFrame` 默认 true 且 HomeView/CategoryRoomsView 均未开启(LIVE 只在 follow 域),且 flutter `RoomSummary` 无 liveState 字段。
- [x] **T3 离线关注卡「上次开播」链路**(f90ee86):`FollowEntry` 新增 lastLiveAt/liveStartAt(云端契约已在 RemoteFollow 上,此前被丢弃);双向透传 + pullRemote 与本地取 max(防旧值抹新记录)+ 刷新「在播→离线」跃迁记录当下 + 本地落盘不丢;纯函数 `offlineLastLiveLabel` 接入卡片两处文案。7 例测试覆盖五段链路。
- [x] **T6 huya/bilibili 弹幕重推去重**(081be1c):共享 `ChatDedup`(FIFO+cap,huya 800/bilibili 1200 对齐 web);契约暂无 id 字段先用 web 的 fallback 兜底 key(用户+正文),**已知残留**:同用户连发同文案会误滤,待契约补 id。
- [x] **守则修复**(be77358):light_theme_test 静态守则抓到 `AppColors.background` 直引,改 `tokens.background`。
- [x] **golden 重生成**(e161ee7):仅 2 张变,像素级定性 2567px(0.20%)全部集中在控制条窄条 y858-873 = T5 新增按钮,无结构性变化;其余 6 张逐字节不变。

### 门禁实测(15:50)
- App 全量 **491 passed / 0 failed**(基线 472 + 新增 19);`flutter analyze` **0 issue**。
- parser `dart test` **292 passed / 10 skipped**(290→292);parser `dart analyze` **0 issue**。

### 前提纠错(本轮调研价值,防将来照旧账返工)
1. `tasks-ui-refine.md` T3「平台 badge 移右下」依据错误(web 真源左下),已作废;
2. web `/time` 是解析耗时基准页,「时间线」在 web 不存在,`/timeline` 是 flutter 超集;
3. 弹幕屏蔽词/屏蔽用户 web 侧也没有,移出 backlog;
4. `ahead=0` 不能证明 worktree 内容已吸收(12 个遗留 worktree 有 staged 未提交改动),清理需先读 handoff + 逐 hunk 审阅,本轮未动;
5. LIVE 角标在 web 浏览网格默认关闭(hideLiveFrame=true),勿再当成网格卡缺口。

### 剩余 backlog(未纳入本轮 2h 窗口)
- [ ] 沉浸态右缘侧抽屉(web `PlayImmersiveSideSheet` + 22% 热区唤起,中);
- [ ] 搜索取数按 `type=anchors|rooms` 分流(需 SearchRequest 契约加参,parser 轨);
- [ ] `DanmakuMessage` 契约补 id 字段(huya sMessageId/bilibili id_str),消除去重兜底 key 误杀;
- [ ] 侧栏预览卡迁移到共享 `CoverOfflineOverlay`(play_room_grid.dart,本轮避让红线未动);
- [ ] 首页非浏览平台直达表单、关注批量导入、移动端目录抽屉、开播提醒消费 remindOn、房间统计回填、画质 rank 归一、跨平台聚合纳入抖音(详见 `docs/plans/2026-09-18-web-alignment-2h.md` §6)。
- [ ] 真机 release 重建 + 截图复验(需跳出沙箱,待用户授权)。

## 2026-09-18 Wave 4 真机 release 复验(完成,用户授权非沙箱)
- release 重建(ZISHU_REAL_PARSER=true,`app.so` mtime 15:16 验证开关生效),schtasks 拉起(pid 13396)。
- **首帧白屏现象**:schtasks 拉起后内容区白屏(UI 线程活跃、进程正常),**resize 一次即恢复** —— Flutter Windows 首帧 surface 未 present 的环境级现象(无人交互),非 app bug;后续真机验收记得先 resize。
- 复验通过:①首页真实数据渲染(斗鱼/虎牙/B站网格+平台角标+热度,解析器真连);②T2 搜索双档(默认房间档金色下划线/占位「搜索房间名·房间号·直播间链接」/「进入直播间」仅房间档,切主播档按钮消失);③T1 离线遮罩+T3 上次开播(关注页离线卡封面压暗、在线/离线区分明确,「上次开播 01-22 00:54」等文案条正常);④T5 控制条弹幕设置入口(播放页真实拉流「原画2K120·线路7 FLV」,弹幕样式对话框从控制条拉起,与侧栏同源,飘屏实时滚动)。
- T4(token)/T6(huya/bilibili 去重)由单测契约覆盖(292 passed),无独立视觉项;斗鱼弹幕链路运行正常佐证 T6 未误伤。
- 截图存档 `build/shots/w4_*.png`(未入库);进程与 ZishuLaunch 计划任务已清理。

## 2026-09-18 抖音 chip 核查 + 弹幕徽章对齐(2 项落地)
- **抖音「游戏分类」核查定案**(ecca125):实连抖音真数据探针 —— 分类树 7 组解析正确(无 web 端「游戏」错值);游戏房间详情 game_tag_name=具体名(绝地求生/三角洲行动);聊天房间全字段空。真 bug 是**分类页房间 chip 为空**(fetchRooms 不传 partitionName)→ 已修:从分类缓存反查 cid→name(只读不发网络,未命中留空对齐 web 空值口径)。
- **弹幕徽章对齐**(3cb09b3):抖音/B站补齐契约三字段提取 + 聊天行徽章对齐 web 语义。
  - 抖音字段号为**实连 WS dump User protobuf 实测**:userLevel=payGrade(#23).#6;粉丝团等级=#61/#21 badge 项 #8.#3(fansclub URL 判定);无团名 → badgeName 留空(web douyinTextFallback 同款)。
  - bilibili 对齐 web 真源:粉丝牌新协议 info[0][15].user.medal 优先 → info[3] 老结构([0]=level/[1]=name);UL=info[4][0]。
  - UI:粉丝牌「团名 级」/无团名圆盘 + 新增「Lv N」用户等级 pill。
  - backlog:huya TARS 徽章需抓帧分析字段;徽章/等级图片分支待契约补 icon URL 字段。
- 门禁:parser analyze 0、test **297/10skip**(292→297);app analyze 0、test **492/0**(491→492)。

## 2026-09-18 UI 口径两项:chip 去平台名 + 播放页左右布局
- **chip 去平台名**(033e93e):移除单平台网格下「平台名从封面角标挪进 chip」的兜底;平台信息由封面平台角标/单平台页签上下文承载,chip 只留促销/画质标签。测试口径同步更新(room_card_meta_height_test)。
- **播放页左右布局**(9dc1e37):左列=44px 房间头(标题)+播放舞台,右列=侧栏全高(从 body 顶开始);窄屏(<768)堆叠与沉浸/全屏/PiP 态不变。新增 playLeftRightLayout 几何测试;播放页 2 张 golden 重生成(pillow 定性 4.57% 差异=面板上移 44px+舞台变宽,无意外变化)。
- 门禁:app analyze 0、test **493/0**(492→493);parser 未动。latency 用例全量并发下曾抖(真机 exe 抢 CPU),单独复跑 218ms 通过。

## 2026-09-18 收尾上一会话遗留未提交批次 + 继续 backlog(进行中)

**结论**:工作区遗留一批完成态但未提交的改动(注释均标「用户口径 2026-09-18」),门禁验证全绿后按轨分两笔提交;随后继续剩余 backlog。

### 收尾提交(0baa791 解析轨 + ad1e202 UI 轨)
- [x] **解析轨 0baa791**:新增 `catalog/category_name_remap.dart`(web 真源 `category-name-remap.ts` 生成,188 组归一映射);twitch/soop 分类树/分类房间/房间详情分类经表中文化(Just Chatting→聊天 / Rust→失控进化-RUST 等);`DanmakuMessage` 契约补 `badgeColorStart/End/Border`;bilibili 新协议 `v2_medal_color_*`(hex)与老结构十进制色([8]/[9]/[5])双路提取。parser 297 passed / 10 skipped。
- [x] **UI 轨 ad1e202**:聊天行 `_FanBadge`/`_UserLevelBadge` 平台分档着色(斗鱼梯度胶囊/B站协议渐变+描边/抖音红盘/虎牙 7 档条,斗鱼 UL「LV N」兜底,对齐 web ChatFanBadge/ChatUserLevelBadge);平台分类浮层单组封顶 5 列(用户口径:twitch hover 不要这么多列);房间头徽标显示当前分类(用户口径:左上角不是「直播」而是分类);twitch fixture 单组 40 条同构。app 494 passed / 0 failed。
- [x] golden:play_style_follow/recommend 重生成(+177B/+169B,仅徽章着色区域),同步截图目录;`test/ui/failures/` 失败产物已清理(门禁通过后不复存在)。

### 待办(本轮继续)
- [x] 沉浸态右缘侧抽屉(web `PlayImmersiveSideSheet`):已落地(7314805)。
- [ ] backlog 其余项见上节「剩余 backlog」。

## 2026-09-18 沉浸态右缘侧抽屉(对齐 web PlayImmersiveSideSheet,完成,7314805)

**结论**:全屏/网页全屏下舞台右缘热区唤出侧栏,不离开沉浸态即可看聊天/关注/推荐。web 真源逐条对齐,9 例新测试 + 门禁全绿(503 passed / 0 failed),golden 零偏移。

### web 真源规格(逐条落地)
- [x] 热区分流:`PLAY_IMMERSIVE_TAP_ZONE = 2/3`(**此前 backlog 记「22% 热区」是笔误,真源是右缘 1/3**);沉浸态点击舞台不切播放/暂停(onPlayFrameClick 沉浸分支直接 return)。
- [x] 抽屉形态:透明遮罩(点背景关)+ toggle 把手(0.82rem×40px 左圆角 chevron-right)+ 全高面板(左边框 + 投影 -6px 0 28px rgba(0,0,0,.55));动效 250ms fluent curve,translateX(100%)+opacity;关闭后不拦命中(v-show display:none → IgnorePointer)。
- [x] 行为参数:进入沉浸 720ms 防抖锁;打开 3s 无交互自动收;面板内指针/滚动交互重置计时;任何途径关闭都唤醒控制条;退出沉浸随容器卸载。
- [x] 内容复用 `PlaySidePanel`(同组件同弹幕会话),宽度沿用 `playSidePanelWidthFor` 分档(手机 min(268,88vw) ≈ web min(320px,88vw));payload 未就绪不挂载(sideReady)。

### 实现要点(坑)
- **`_VideoStage` 点击从 `onTap` 改 `onTapUp`**:沉浸分流需要舞台内相对坐标;常规态回调为空退化为切播放,既有测试不受影响。
- **防抖锁用 bool+Timer 而非 DateTime 截止值**:widget 测试 pump 推进的是 FakeAsync 时钟,真实 `DateTime.now()` 不走,锁会永远解不开。
- **测试断言口径**:sheet 沉浸期间**常驻挂载**(web v-show 同构),开/关必须断言 `AnimatedOpacity` 目标值,「findsNothing」只适用于退出沉浸卸载后的场景——首轮 6 例失败均源于把挂载当开合。

### 验证
- `flutter analyze` 0 issue;全量 **503 passed / 0 failed**(494+9);parser 297 passed / 10 skipped;golden 重生成零 diff(抽屉仅沉浸态,常规态渲染不变)。

### backlog 剩余(未纳入本轮)
- [ ] 搜索取数按 `type=anchors|rooms` 分流(SearchRequest 契约加参,parser 轨);
- [ ] `DanmakuMessage` 契约补 id 字段(huya sMessageId/bilibili id_str),消除去重兜底 key 误杀;
- [ ] 侧栏预览卡迁移共享 `CoverOfflineOverlay` + 四象限 chip(R3);
- [ ] 关注页批量导入、首页非浏览平台直达表单、移动端目录抽屉、开播提醒消费 remindOn、房间统计回填、画质 rank 归一、跨平台聚合纳入抖音;
- [ ] `AppTypography.* → context.textX` 机械替换(127 处/36 文件);桌面 1920x1080 布局对齐(播放页底部工具栏);
- [ ] kuaishou/soop/yy 轻量状态刷新;真机 release 重建 + 截图复验(沉浸抽屉真机手感)。

## 2026-09-19 并行三轨:徽章顺序 + 虎牙徽章 + 全屏防闪窗(完成,2 子代理并行)

**结论**:用户四条诉求一条工具诉求全落地 —— ①聊天行平台等级前置;②虎牙徽章/等级提取补齐(抖音/B站/斗鱼此前已有);③按 F 全屏闪动露底根因修复;④superpowers 技能集安装进 zcode。两个子代理(parser 轨 / playback 轨)与主代理(UI 轨 + 工具)并行,文件互斥零冲突;门禁 app **503/0** + parser **301/10skip** + analyze 双 0 + golden 零 diff。

### ① 聊天行平台等级前置(f83420b)
- web 真源 `SideChatTab.vue:38-44`:顺序为 ChatUserLevelBadge → ChatFanBadge;flutter `_ChatRow` 原为粉丝牌在前,已交换。同用例补 x 坐标顺序断言(同行断言用 8px 垂直容差——两枚徽章高度不同,严格 top 相等差 0.5px 属过度约束)。

### ② 虎牙徽章提取(0abfad8,子代理轨)
- 真源 `huyaJce.ts` parseMessageNotice(392-435):MessageNotice 顶层 tag **8/9/12/15** 按 `LIST<DecorationInfo>` 累积;appId **10400**→BadgeInfo{sBadgeName@3, iBadgeLevel@4} 写 badgeName/badgeLevel(level<=0 无牌);appId **11200**→iLevel@1 写 userLevel(web 虎牙等级即消费等级,无独立贵族字段);同 appId 后写覆盖。
- 装饰解码 try/catch:只丢徽章不丢正文。**此前 UI 的 HUYA_BAR_GRADIENTS 7 档渐变条已落地但拿不到数据,本次补齐数据源后即生效**。
- 测试 +4;遗留:虎牙字体色 tag 6 vs web tag 5 未经真实抓包验证(既有行为,徽章提取不受影响);`sMessageId@20` 待契约补 id。
- 回答用户「抖音之类的呢」:抖音(红盘+粉丝牌)、B站(协议渐变+描边)、斗鱼(梯度胶囊)此前均已落地;本次补齐虎牙后四主力平台徽章/等级全通。

### ③ 全屏防闪窗(34a4250,子代理轨)
- 根因(window_manager 0.4.3 源码确认):SetFullScreen 多步非原子——进=带边框 SC_MAXIMIZE(触发 DWM 动画、任务栏露出)→去边框铺满,步间完整帧上屏;Dart 侧另有 setSize(+1px) hack;退=PostMessage(SC_RESTORE) 异步 + 满屏尺寸上闪标题栏帧。
- 修复:`platforms/windows/window_flash_guard.dart` —— WM_SETREDRAW(FALSE) 锁重绘 + DWMWA_TRANSITIONS_FORCEDISABLED 禁动画,解锁 RedrawWindow(RDW_UPDATENOW);退出方向 120ms settle 等异步消息。不绕过插件(全屏态唯一真源不变);无 HWND/符号缺失时退化直调。
- ffi 转直接依赖(^2.1.0)。

### ④ superpowers 技能安装(工具)
- obra/superpowers v6.3.0 全部 **14 个技能**已装入用户级 `C:\Users\Administrator\.zcode\skills\`(brainstorming/writing-plans/executing-plans/requesting-code-review/receiving-code-review/test-driven-development/systematic-debugging/verification-before-completion/dispatching-parallel-agents/subagent-driven-development/using-git-worktrees/finishing-a-development-branch/writing-skills/using-superpowers),每个 SKILL.md frontmatter 校验通过;**新会话起生效**(当前会话技能清单启动时已固定)。

### 并行执行记录
- 子代理 B(parser):47 次工具调用 / 15 分钟;子代理 C(playback):41 次 / 22 分钟;主代理同窗口完成轨 A + 白屏修复收尾(f21a18c)+ 技能安装。git 由主代理单写者收尾,子代理只改文件不提交。

### 门禁与真机
- app analyze 0 issue;全量 **503 passed / 0 failed**;parser 301 passed / 10 skipped;golden 重生成零 diff(聊天行无双徽章条目入 golden)。
- 真机 release 重建(`ZISHU_REAL_PARSER=true`)并拉起:F 进/出全屏防闪窗、虎牙直播间聊天行徽章可现场复验。

## 2026-09-19 启动白屏根治(第二层:几何恢复上移到 runApp 之前,df9a6c5)

**结论**:用户实测上一轮修复(f21a18c,WM_SIZE→ForceRedraw)后**仍白屏** —— 那次验证是拉起 10 秒后才截图,后续网络数据帧已把画面救活,掩盖了修复未覆盖的窗口期。本轮找到真竞态并根治。

### 根因链(完整版)
1. runner 官方模板:窗口创建后隐藏,`SetNextFrameCallback` → 首帧就绪才 `Show()`。
2. `restoreMainWindowGeometry()` 原挂在 `WindowsApp.initState`(**runApp 之后**),与首帧回调赛跑:setSize/setPosition 触发 WM_SIZE → surface 重建。
3. `ForceRedraw` 在首帧未完成时是官方注释保证的 no-op —— 冷启动慢(计划任务拉起、磁盘/CPU 竞争)时 WM_SIZE 多落在首帧完成前,兜底失效 → 白屏直到下一帧数据到达。
4. 上一轮 10s 截图验证的教训:**验证「启动瞬间」必须在窗口出现后立即抓帧**,不能等稳定后再看。

### 修复(df9a6c5)
- [x] `restoreMainWindowGeometry()` 上移到 `main()` 的 `runApp` **之前**:runner 窗口从创建到首帧期间始终隐藏,几何变更全部发生在隐藏期,Show 时一次性以最终尺寸呈现首帧 —— 「显示后再 resize」的白屏窗口期从结构上消除;WM_SIZE→ForceRedraw 保留兜底。
- [x] `WindowsApp.initState` 只保留几何采集(落盘)事件转发。
- [x] 门禁:analyze 0 issue;全量 503 passed / 0 failed。
- [x] 真机:计划任务拉起,**PrintWindow 直抓窗口表面**(全屏截图受宿主窗口遮挡影响不可靠,且 TOPMOST 在该环境会被拒;PrintWindow 不受遮挡),窗口出现即完整渲染,几何恢复(1056×807)生效,无白屏。

### 真机截图方法论(沉淀)
- 全屏 GDI 拷贝截的是合成屏幕,宿主窗口遮挡 + SetWindowPos TOPMOST 被环境拒绝时截不到目标 → 用 `PrintWindow(hwnd, PW_RENDERFULLCONTENT)` 直抓目标窗口表面;
- 手写 PNG:BGRA→RGB 用三次 stride 切片(`raw[2::4]` 等),**每行前必须插 filter byte 0** 再 zlib 压缩(漏掉会导致 PNG 无法解码)。

## 2026-09-19 侧栏关注口径更新:只显在播 + 默认列表(1ff2df3)

**结论**:播放页侧栏「关注」tab 按用户最新口径重做 —— ①不显示没开播的;②默认列表视图(每条一行);③超关在播置顶。TDD 全绿(505/0)。

### 口径变更(两处有意偏离 web 真源,已在注释钉住)
- **可见性**:`isPlayFollowVisible` 改为只显在播。web 真源 `followDisplay.ts:235` 是「在播 ∨ 离线超关」,该口径 2026-09-18 曾对齐落地(当时为修「关注没显示」),现被用户口径覆盖。空态文案同步改「暂无在播关注」。
- **默认视图**:封面网格 → 紧凑列表(`PlayRoomList`,每条一行:主播名+★+标题,无缩略图)。web 真源默认 `previewCover=true`(封面预览),同样有意偏离。网格仍可手动切换。
- **排序**:超关在播 → 普通在播(档内关注时间倒序不变,与「我的关注」页共用 follow_sort 单一来源)。用户「按超关 关注排序」自然满足。

### 测试坑(记录)
- 面板 finder 必须按**滚动方向过滤**:面板里平台筛选 chips 是水平 ListView,不过滤会误中关注列表(垂直);
- 分页窗口计数读 `SliverChildBuilderDelegate.childCount` 而非 `estimatedChildCount` —— 后者按可视区**估算**(实测 60 条窗口只报 12),GridView 才是精确值;
- `findsNothing` 断言不能用带 `.first` 的 finder(0 匹配时 `.first` 直接抛 StateError,而非断言失败);
- room_card_badges 四象限用例适配:切网格后测在播卡;离线卡渲染(★ 左下/未开播遮罩)改**直 pump PlayRoomGrid** 钉住契约(侧栏不再触达离线条目,防口径回摆时丢行为)。

### 门禁
- analyze 0 issue;全量 **505 passed / 0 failed**(+2:超关置顶排序、离线卡直 pump);
- golden `play_style_follow` 重生成 43317→36700B(关注 tab 网格→列表,渲染元素减少,定性无意外)。
- 待办:重建 release exe 真机复验。


## 2026-09-19 侧栏关注列表行复刻 web 四列 + 切房保持 tab(c3a65ac)

**结论**:上一轮两处未完成项收口 —— ①列表行重写为 web FollowRoomRowView 四列表格;②切房后右侧不再退回聊天 tab。门禁 507/0 全绿。

- **四列行**:分类条(54px,CategoryColors 底 18% + 中性字)/ 主播名(72px,FollowAnchorName 平台色,省略)/ 标题(弹性省略)/ 人数(人形图标+文本)。行高 24(对齐 web 1.4rem)、底部分隔线、去行内 ★(web 无,超关以置顶排序表达);separated→builder(分隔线移到行上)。
- **切房保持 tab**:新增全局 KeepAlive `playSidePanelPrefsProvider`(tabIndex/followGrid/followSite),TabBar.onTap 与面板变更写回,DefaultTabController.initialIndex 恢复 —— 顶部(壳层常驻)/左侧(舞台随路由)/右侧(active 态全局)三块解耦,右侧点条目 pushReplacement 后不退回聊天。离开播放页后偏好也保留(会话级)。
- 测试 +2(四列内容/单行紧凑、切房后关注面板仍挂载);坑:builder 化后分页计数改 delegate.childCount(separated 时代的 (n+1)/2 换算已废)。
- golden:play_style_follow 36700→37693B(两行文字→四列单行+分类条)。

## 2026-09-19 侧栏筛选图标化 + 去面板标题(bd140be)

**结论**:三条补充口径同轮落地 —— ①平台筛选 chips 改为与顶栏同款平台图标格子(PlatformIcon,30x30,选中态 surfaceRaised 底+品牌色描边+柔光);②Wrap 自动折行不再横向滚动(可 2 行);③关注/推荐面板顶部去掉「我的关注」「相关推荐」标题(_PanelTitle 删除),视图切换按钮挪进筛选行对齐 web follow-tab-toolbar。
- 测试:danmaku_test 标题断言改「面板挂载+标题不存在」;默认列表用例的视图形态断言改按卡面锚点 —— 平台图标 all 的四象限色块内部也有 2x2 GridView,按类型断言会误中。
- golden:play_style_follow 37693->43970B(图标格子+分类色条)、play_style_recommend 40240->39663B(标题行移除)。
- 门禁:analyze 0;全量 507 passed / 0 failed;parser 301/10skip。

## 2026-09-19 播放域深对齐:三路调研 + 四轨并行(6 commit)

**结论**:93 项量化差异(徽章 36/侧栏 19/播放页 38)计划落地约 40 项高价值项,4 轨并行(3 子代理 + 主代理),文件互斥零冲突。门禁 app **508/0** + parser 301/10skip + analyze 双 0 + golden 重生成。

### 计划与调研
- 计划文档:`docs/plans/2026-09-19-play-parity.md`(文件归属矩阵/验收标准/本轮不做清单)。

### 落地项(按轨)
- **095553e parser**:DanmakuMessage 增 badgeTextColor/badgeColorLevel;B站 v2_medal_color_text/level 提取(供粉丝牌分色渲染,此前恒白)。
- **16cfc87 轨1 侧栏**:徽章文字态全量对齐 —— 渐变方向修正(此前全平台左右镜像!)、尺寸对齐 em(虎牙 16/B站 21/抖音 19.6)、斗鱼牌只显团名+去梯度兜底、B站互补缺省+协议分色、默认等级 label 纯数字;侧栏密度 —— 聊天开关 52x32→30x16 自绘(用户主诉)、TabBar 46→32、设置组圆角 8、头像 64 贴边、刷新按钮带文字、聊天 14px/1.48 不截断、新消息按钮居中。
- **c76e120 轨2 控制条**:按钮顺序对齐 web(刷新左移成组)、「弹」字方框徽标(+齿轮角标/amber 打开态)、图标 22/按钮 41、音量白系+compact 不隐藏、画质/线路前置图标+单线路不渲染、菜单暗色皮肤、沉浸把手 18.4/圆角 4。
- **e576df2 轨3 弹幕域**:默认速度 5、区域 4 档(旧值吸附兼容)、面板加标题+显示开关+单行三列滑杆+下拉(文案去 px)、行高公式 1.52+6、顶部留白 0。
- **ffc79af 轨4 房间头**:高度自适应、返回/侧栏钮 32、分类徽标=平台图标+文字+内嵌星标、标题去分类前缀、舞台 12px 圆角;meta_bar 高 44 内容自适应+头像 52 左贴边+列宽 59。
- **5820d7a golden**:play_style_follow/recommend 重生成。

### 并行执行与收尾坑
- 3 子代理(轨1 54 工具调用/轨2 84/轨3 59)并行 + 主代理同窗轨4;git 单写者收尾。
- 轨2 发现轨4 meta_bar 固定 44 高溢出 2-6px(字体 metrics 大于 fontSize*height)→ 改 IntrinsicHeight 内容自适应,溢出矩阵全绿。
- 轨3 面板重写写死 AppColors 被 light_theme 静态守则抓到 → 改 context.tokens/textX;const 构造不能引用 context。
- 溢出像素战争教训:固定高 + 中文字体 metrics 的组合必然溢出,内容自适应才是解。

### 本轮明确不做(记录于计划 §不做)
- 徽章图片态全套(契约缺口)、超粉 V/guard/wealth、≤420 音量浮层、弹幕浮层锚定形态、飘屏速度连续模型、侧栏 pad-x 10.4 全局替换、侧栏头死按钮接通。

## 2026-09-19 分类页直达列表 + 飘屏去昵称 + twitch/soop 中文化根治(7950e56/4d36b0d)

**结论**:三条用户口径落地,其中 twitch/soop 未翻译的根因经 SFVideo 真源核对后**推翻了「表缺条目」的假设** —— 是请求缺本地化参数。

### 口径落地
- **分类页**:带具体分类上下文进入(hover 分类/我的分类/侧栏分类,路由带 cid/key)只渲染房间列表,去掉分组 tabs 与顶部子分类网格;裸 /site/category 保持索引三栏(对齐 web CategoryRoomsView vs CategoryIndexView 双视图语义)。
- **飘屏去昵称**:buildSpan 单段纯正文;侧栏聊天行保留「昵称:正文」(web SideChatTab 语义,两个面不同)。
- **twitch**:GQL 补 Accept-Language: zh-CN(web twitch.ts:76-84)+ 分类/房间查询补 displayName,名称 displayName||name 再 remap —— 上游直出中文,remap 只是归一。
- **soop**:categoryList 补 lang=zh_CN + Accept-Language(缺它上游仍韩文);分类树记录 cid→中文(soop/zh_categories.dart,web soopZhCategoryMap 同构),房间列表按 category_no 反查覆盖韩文。
- **remap bug**:「动物与动物园」别名本身含逗号被生成脚本错拆为 3 条 → 修为单条(完整串此前匹配不上)。

### 方法论升级(用户建议):从 SFVideo 提交历史挖功能演进
- SFVideo 361 commits:近期 ~40 个为桌面原生化(Tauri+Rust crates/live-parser+libmpv),**对齐基准应以 crates/live-parser 为最新真源**(streaming-server 是旧 web 端)。
- 候选对齐清单(记录,待裁决):起播 FLV 优选(斗鱼首帧 2.3s→1.0s)、进房单清晰度档解析、HLS 回放缓冲上限 60s、分类缓存空壳分组校验(虎牙分类不显示根因)、soop opcode 白名单、YY 弹幕禁用标记、twitch emote 解析、房间卡 tags、抖音 Cookie 设置入口、分类面板列数规格表(aff7424 系列)、xhs cursor 翻页。

## 2026-09-20 Windows 公共 smoke Task 4.2

- [x] 建立 `tool/windows_public_smoke.ps1`：生成人工 checklist、build/git/evidence 元数据，支持 dry-run/checklist、可控证据目录和可选 release exe 启动；生成总体状态固定为 `NOT_RUN`，每条记录生成唯一截图文件路径。
- [x] 默认状态和各平台功能条目保持 `NOT_RUN`；脚本不自动点击、不联网、不写凭据、不伪造 PASS/FAIL。
- [ ] 真实 Windows release smoke 尚未执行；后续需要 release build、人工逐平台验证，并用 `tool/win_tool.py shot` 的 `PrintWindow(PW_RENDERFULLCONTENT)` 记录窗口表面证据。


**结论**:用户报告两条数据缺口修复 + 分类预热落地。门禁全量 **540 passed / 0 failed**(533+7)、parser **325/10skip**、analyze 双 0。

### ① 侧栏统计真数据(6d920cf,子代理)
- 契约:RoomSummary 增 followers/vip(格式化文本,空=上游没有);各站 refresher 按真源提取 —— douyu 资料卡 fansNum+贵宾 total(新增 best-effort 接口)、huya activityCount、bilibili attention、douyin follow_info、soop fanCnt+订阅 total;huya/douyin 的 vip 走二进制/签名链路不复刻留空,yy/kuaishou 上游无免登录接口留空(数据诚实性:不伪造)。
- UI:侧栏头「关注 N / 人气 N / VIP N」从当前房间关注条目刷新回填值取数,未关注/未回填回退「—」。

### ② 关注行分类同步
- 根因:refreshStatuses 合并语义未更新 category(主播换分类后关注行留旧值);且 pullRemote 整表替换后要空等一个 60s 轮询周期才有统计/分类。
- 修复:合并口径钉死(category/统计以刷新为准非空更新,cid/身份键/本地标记保留);pullRemote 后立即回填一次刷新。
- 关注行分类条(PlayRoomRow 第一列)随数据链路自动跟随,UI 结构未动。

### ③ 分类预热(4d5b6be)
- 启动 2s 后串行逐站预热全部浏览平台分类索引进 provider/进程缓存(browseWarmupSites = supportsBrowse 集合),hover 平台分类浮层即时命中;失败静默(hover 自然重试);WindowsApp dispose 取消 Timer(测试环境不留 pending timer —— 初版曾致 89 用例「Timer is still pending」连坐,已修)。
- 映射(remap 175 组 + cross-categories 328 条)为编译期内嵌常量,启动即在内存,无需预热。

### 控制条右组贴右根治(2053a54,接上轮)
- 几何测试实测全屏按钮距右缘 230px:根因 Expanded+Spacer+两个 Flexible 四分弹性,loose 孩子未满份额的空白散落。改 Stack 双 Align(左组 centerLeft/右组 centerRight)物理贴边;窄条(compact<560)隐藏 PiP/网页全屏/睡眠/线路名收缩,360 压线可容。
- 几何锚点测试钉住(全屏距右缘<24、左右组间>300)。

### 门禁
- 全量 **540 passed / 0 failed**;parser 325/10skip;analyze 双 0;golden 8 张重生成(侧栏统计渲染变化,定性无意外);latency 单跑 5/5(整批并行抖动已知噪声)。

## 2026-09-20 Windows release 真实 smoke(阶段 4 收尾)+ 阶段 5 收口门禁(完成)

**结论**:release(`ZISHU_REAL_PARSER=true`, 725a1a2)真机 smoke 完成——9 平台 browse+进房+播放全过(iptv 按用户口径跳过);VOL/MUTE/QUALITY/LINE/FULLSCREEN/PIP/FOLLOW/THEME/RETURN 真实通过;DANMAKU 6 平台收流通过但 twitch BLOCKED / huya FAIL;发现 BUG-WIN-VOLUME-002(新房间音量继承)等 10 项登记。阶段 5 全量门禁全绿:goldens 7、app-test **644**、analyze 双 0、parser-test **378/10skip**。矩阵文档 `docs/testing/windows-public-function-matrix.md` 已回填全部「Windows 真实」列;证据 `tool/windows-public-smoke/rel-smoke-20260920/`(gitignore)。

### 本轮完成项
- [x] 真实 smoke 执行:`tool/_smoke.py`(临时驱动,真实鼠标/键盘/拖动 + PrintWindow 存证),schtasks 拉起 release exe。
- [x] douyu 全流程:弹幕(连接+滚动+飘屏)/画质(原画→蓝光4M)/线路(7→13 FLV)/关注 toggle+超关联动/音量 36.8 隔离恢复/返回。
- [x] VOL 链真机证据:A(36.8)→B(twitch 86.8)→回 A 恢复;落盘 `roomVolumes` 三条独立。
- [x] twitch:720p60→480p、单线路 HLS、静音、全屏进出(Esc)、PiP 进出+画质记忆保持。
- [x] bilibili/douyin/kuaishou/soop/youtube:播放+弹幕收流(soop 韩文 24+条+飘屏;youtube 多语言)。
- [x] yy:播放 PASS,弹幕诚实呈现「暂不支持」N/A 态。
- [x] THEME:深↔浅全页即时切换。

### 用户口径(2026-09-20,本轮)
- 「IPTV不用管」——iptv 播放验证跳过,矩阵真实列记 N/A。
- 「很多平台的关注VIP等没解析 还有徽章平台等级等」——PARSER-GAP-001(房间详情字段;侧栏统计 6d920cf 已接部分字段,播放页主播卡未消费,修复时优先接线)。
- 「这种表情没解析」——PARSER-GAP-002(弹幕表情 `[贊]`/`:crossed_flags:` 文本占位,未渲染图片)。
- 「同一个人发言第二行文字应该从最左边开始」——UI-BUG-001(聊天折行顶格)。
- 「没有金色,滑动条按钮等应该改成当前的紫薯 紫色」——UI-BUG-002(删金色循环文案;控件强调色统一紫霄紫)。

### 待修清单(下轮,按用户口径优先)
- [ ] UI-BUG-002 控件强调色→紫色 + 删「金色」文案
- [ ] UI-BUG-001 聊天弹幕折行第二行顶格
- [ ] BUG-WIN-VOLUME-002 无记忆新房间音量应默认 100(先补失败单测再修)
- [ ] PARSER-GAP-001 播放页主播卡接线已解析字段(followers/vip,6d920cf 契约)+补缺口平台
- [ ] PARSER-GAP-002 弹幕表情图片渲染(segments 契约已就绪)
- [ ] BUG-WIN-DANMAKU-002 douyu 切房返回弹幕自动重连
- [ ] BUG-WIN-DANMAKU-003 huya 已连接零消息(注册/心跳/订阅包排查)
- [ ] BUG-WIN-DANMAKU-004 twitch 弹幕连接失败(出口+connector 复验)
- [ ] OBS-WIN-PLAY-001 youtube HOY 频道流拉不动(观察)
- [ ] OBS-WIN-OVERLAY-001 飘屏多轨重叠(低优先)

## 2026-09-20 smoke 待修清单处理(用户口径 6 项,完成)

**结论**:6 项修复全部完成并真机复验。全量门禁全绿:app-test **656**、analyze 双 0、parser **384/10skip**。release 重建后真机确认:控件强调色全紫(slider/开关/激活态)、主题深⇄浅二态无「金色」、全新房间音量默认 100(不再继承上一房 36.8)、douyu 切房返回弹幕自动重连(A→B→A 直接已连接+飘屏,无需手动刷新)。

### 修复明细
- [x] UI-BUG-002 控件强调色→紫霄紫:tokens 新增 accent(深 0xFF7C4DFF/浅 0xFF6A1B9A),app_theme 接 colorScheme.primary/secondary;player_controls(slider/弹幕开关/全屏激活/菜单勾选/睡眠定时)、app_shell(登录 checkbox+按钮/导航与底栏激活/分类 hover 底)、弹幕设置面板标题、主播页关注 CTA 全部改紫;brand 金保留收藏星/徽章/卡片角标等 web 对齐功能色。
- [x] UI-BUG-001 聊天折行顶格:_ChatRow 改单段 Text.rich 内联流(徽章 WidgetSpan 内联,对齐 web SideChatTab display:contents 语义),第二行顶格内容区最左;RenderParagraph 断言第二行 left≈0。
- [x] BUG-WIN-VOLUME-002 根因:MediaKitLivePlayer.setVolume 只写 mpv 不发快照,切房窗口内事件回流被围栏丢弃+幂等去重致快照卡死上一房值(替身同步 emit 遮蔽缺陷)。修复:setVolume/解除静音主动 emit 快照;3 个 fence 用例+2 个回归锚,TDD 红转绿,playback 130/130。
- [x] PARSER-GAP-001 主播卡接线:play_meta_bar 接 followProvider 当前房 RoomSummary(followers/online/vip,6d920cf 链路),无字段显「—」不伪造。
- [x] BUG-WIN-DANMAKU-002 弹幕重连:douyu 对快速重连限流,首连被拒无重试。session provider 加 3 次指数退避(800ms→3.2s)+generation fence,连接成功重置预算,手动刷新为耗尽出口;4 个新用例。
- [x] PARSER-GAP-002(部分):youtube emoji 短代码→Unicode(gemoji 1913 全量+CLDR 手工核定 144 项覆盖层,含 :grinning_face_with_sweat:→😅),_runsToText 接线,文本段不过表防误改;kuaishou 协议无表情 URL([贊] 保持文本,注释说明,不伪造)。

### 剩余(下轮)
- [ ] BUG-WIN-DANMAKU-003 huya 已连接零消息(注册/心跳/订阅包)
- [ ] BUG-WIN-DANMAKU-004 twitch 弹幕连接失败(出口+connector 复验)
- [ ] PARSER-GAP-002 剩余:kuaishou 表情 URL 抓包、twitch emote 图片渲染
- [ ] OBS-WIN-OVERLAY-001 飘屏多轨重叠

## 2026-09-20 紫色强调色全面覆盖(用户口径「找同款黄色」)

**结论**:全局搜索 `tokens.brand`(金色)46 处逐一清点定性——控件/选中/hover/按钮/头像/进度/光标全部改 `tokens.accent`(主题宏,唯一定义 zishu_tokens.dart,深 7C4DFF/浅 6A1B9A);金色仅保留收藏星/超关星/徽章 fallback/平台色回退/replay 金黄等 web 对齐功能色。用户点名三项全改:右上角登录头像圆底、侧栏聊天/关注 tab 选中(TabBar label+indicator)、各处选中态。另清 play_side_panel 弹幕开关轨道硬编码 0xfff3d04e→token,删 design_tokens 死常量 AppColors.brand。真机复验:头像紫底/聊天 tab 紫选中/slider 紫全可见。全量测试+golden 重生成后门禁收口。

### 保留金色清单(功能色,非控件)
- 收藏星:分类收藏(category_view:436)、目录抽屉关注星入口(browse_sidebar:137)、我的分类 hover chip+管理弹窗(app_shell 2358-2624)、封面关注角标(play_room_grid:184)
- 超关星:侧栏行/卡片 isSpecial 星(follow_entry_card:101/273、follow_entry_row:124)
- 徽章/平台回退:badge_chips、timeline_tile、play_view:531、category_view:349
- replay 金黄描边(#f5dc70,web follow-item--replay 对齐)

## 2026-09-20 播放页控制条重排 + 侧栏头细节(用户口径,完成)

**结论**:控制条按 SFVideo 复刻重排+侧栏头 5 项细节+开关滑杆全局统一。全量 **658 全绿**,analyze 0。真机复验:暂停切换(图标+状态行同步「已暂停」)、侧栏文字按钮、关注 605 万格式化、分类徽标增大、折行顶格、弹字方块组全部生效。

### 本轮完成项
- [x] 控制条重排(用户口径):左组=播放/暂停→刷新→睡眠定时→弹幕开关「弹」→飘屏弹幕设置「弹」;右组=音量组靠右(静音+滑杆)→画质→线路→PiP→网页全屏→全屏(两个独立按钮,用户确认不合并不循环)。
- [x] 「弹」字方块双钮复刻 SFVideo ctrl-danmaku-mark(方块+√/齿轮角标),激活色对齐品牌紫(用户口径覆盖 SFVideo amber);飘屏设置 popover 复刻 OverlayDanmakuSettingsPanel(显示/透明度/字号/速度/区域),侧栏设置 tab 的聊天弹幕设置保留不动(互不相干,用户确认)。
- [x] 开关/滑杆全局统一(用户口径):新增 AppControls 控件规格 token(slider 轨道 3/圆点 6/行高 20/switch 缩放/字 11);全局 CompactSwitch(30×16,自 _MiniSwitch 提升)替换设置页/弹幕面板/popover 的 Material 大 Switch;全局 sliderTheme 紧凑规格。
- [x] 侧栏头 5 项:分类徽标字号 11→12.5 且行内居中;关注数 ≥1 万显示「X.X万」(_formatFollowersText);开播提醒/跳转移到第二排分类名后并改文字按钮(「直播提醒/直播提醒中/跳转」);视图切换 icon 换 view_list/grid_view 且 18px 减 padding;列表行文字左 padding 4→1。
- [x] 统计兜底(用户口径「huya 等关注 VIP 没解析」第二层):roomStatsProvider 对当前房间直接调解析侧 refreshRoom(与关注行同一条真源,无需关注状态);主播卡+侧栏头在关注条目缺失时兜底取数。已关注房间上一轮已通(6049418→605万 真机确认)。
- [x] 播放/暂停判断错修复:A7 用例(TDD 先红)+play()/pause() 主动发布 playing 快照(不等 mpv 回流);真机确认暂停后图标与状态行同步「已暂停」。

### 待办(下轮)
- [ ] BUG-WIN-VIDEO-001:进房黑屏(播放中但画面黑,暂停→播放 kick 恢复,多次复现)——排查 VideoController 纹理首帧,候选:videoInfo 缺失时自动 kick 一次。
- [ ] 播放恢复几秒后自动停(用户报告一次,OBS-WIN-PLAY-002 相关,需复现+日志时间点)。
- [ ] BUG-WIN-DANMAKU-003 huya 弹幕零消息;004 twitch 弹幕连接;PARSER-GAP-002 kuaishou 表情抓包/twitch emote;飘屏多轨重叠。

### 2026-09-20 晚追加:popover 开关尺寸修正
- [x] 根因:MenuAnchor 的 child/menuChildren 用反 —— 面板内容写在 child(按钮位,不渲染),menuChildren 挂的是旧版大 Switch 面板。已对调:「显示」行换全局 CompactSwitch(30×16,对齐侧栏聊天弹幕开关),透明度/字号/速度滑杆走 AppControls 紧凑规格,区域勾对齐 accent。真机复验:面板紧凑、小开关生效(verify-compact-switch3.png)。
- [ ] BUG-WIN-VIDEO-001 进房黑屏(暂停→播放 kick 可恢复,多次复现)待排查 VideoController 纹理首帧。
- [ ] 播放恢复几秒后自动停(单次报告)待复现取日志时间点。

### 2026-09-20 晚追加:简化与模块化复用分析
- [x] 全库扫描落盘 `docs/refactor-analysis.md`:巨文件拆分(app_shell 2686/play_side_panel 2684/play_view 1204/player_controls 1004)、重复模式 7 项(统计取数×2/万格式化×2/重试按钮×5/滑杆行×3/SliderTheme×3/下拉×5/pill)、遗留清理(_MiniSwitch 并入 CompactSwitch 含补漏 2 处调用、AppColors.brand 与 AppControls.switchScale 死常量删除)。
- [ ] P1:统计取数与万格式化统一(主播卡/侧栏头行为不一致风险);P2:play_side_panel 拆分;P3:其余提取。

### 2026-09-20 深夜追加:翻译功能排查与修复(用户确认标题翻译已生效)
- [x] 根因一(已修):翻译 fetcher 用独立 Dio 直连公共翻译实例,未走上游代理 → 全部超时回退原文。修复:fetcher 改为代理感知 HttpClient(复用 UpstreamProxy,与解析/弹幕同款)。
- [x] 根因二(已修):内置四个公共实例集体失效实测(garudalinux=CF 盾、lunar.icu=上游错、simplytranslate.org=Not Found、jae.fi=空)。修复:新增 GoogleWebEngine(translate.googleapis.com client=gtx,免 key 走代理,稳定)置为首选引擎,志愿者实例降为后备;单测覆盖响应解析。
- [x] 真机验证:SOOP 分类页标题大量中文化生效;部分未译为批量入队队列丢弃回退原文(设计行为)。
- [ ] 飘屏/聊天弹幕正文翻译未生效(translateBody 已注入但真机韩文未译;聊天行 translatedTextProvider 消费在翻译轨道计划中)——下轮排查 danmaku_overlay 调用链与队列时序。
- [ ] 可选:翻译服务离线部署指引(Lingva/SimplyTranslate/LibreTranslate 均开源可 Docker 自建,设置页 endpoint 填自建地址)。

## 2026-09-26 聊天徽章按平台官网前端重做(虎牙/斗鱼/抖音,完成)

**结论**:聊天行的「平台等级 + 粉丝牌 + 各类身份徽章」全面改为**以各平台官网自己的前端代码与真实弹幕为准**,不再靠截图观感推断。三处根因级错误已修正。UI 轨 `f4e6cdd`/`d1eb0fb`,解析轨 `0025a04`/`a1bd0f5`。

### 本轮完成项
- [x] **虎牙平台等级**:改用官方 CDN 图 `diy-assets.msstatic.com/consumeLevelBadgeV2/{tier}/{light|gray}.png`(tier 由 iLevel 分档 1/10/20/30/40/45/50/60,tone 由 iIsPolished 决定;图 90×40@2x = 45×20)。实测 8 档 ×{light,gray,hide} 共 16 个 URL 全 200。此前误以为「canvas 随机生成」并自绘渐变,完全错判。
- [x] **虎牙身份图标**:改用官方 `fansBadge/3/v2/{identity}.png`(1/2/3/4/11/12/13 全 200)。查明本地 `assets/badges/huya/vip/v2/*` 与 `fans/v2/*` 是**同一套身份图标**(V / 守盾),即官网 `fans-icon-sf`,原代码把它当平台等级底图是根本性误用。
- [x] **虎牙粉丝牌底图**:接房间级 `wupui/getResourceInfo`(复用 `huya_wup.dart` 已验证的 WUP/TUP 通道,未另起基建),`iBizType=14` 解出 `tCommonBadge.sFloorUrl`,由解析侧拼好官方底图 URL 放进 `DanmakuBadge.url`,UI 直接消费。字段号由一次性探针 `tool/_probe_huya_resource_info.dart` **实测探明**,非推断。
- [x] **虎牙 BadgeInfo 补字段**:tag 19 `tSuperFansInfo.iSFFlag`、22 `iCustomBadgeFlag`、25 `tExternal{iFansIdentity,iBadgeSize}`、26 `iExtinguished`;原已读的 3/4/12/13/17 经核对字段号正确。
- [x] **斗鱼徽章补全**:官网实为 4 类组件(`dy-user-level`/`dy-fan-medal`/`dy-noble-level`/`dy-supreme-medal`),此前只做了 2 类。字段映射取自官网 `live-next-player-aside`:`ne`=贵族、`sl`+`sid`=至尊大钻石、`sahf`=超粉、`diaf`/`cdiaf`=钻粉、`diafid`=钻粉图标 id;另接 `fl`(bl 兜底)、`brid`、`hc`。LV 胶囊按逐像素实测改 32×16 全圆角 + 5 档水平渐变(<15 米金/15-29 绿/30-39 蓝/40-49 靛/≥50 紫,18 个样本全部落档)。
- [x] **抖音粉丝牌回归修复**:此前误用 `fansclub_new_advanced_badge_N_xmp`(60×48 紧凑款)并丢弃协议 URL。该款右侧无团名位,且渲染后(~26px)退化为与平台等级 honor(~42px)同款的「彩色圆角块+数字」观感 —— 即用户报障的「粉丝徽章跟平台等级弄一样了」。已恢复协议 URL 优先,合成模版改回官方 `fansclub_level_v6_{lv}.png`(1..20 为 200、21+ 为 404)。
- [x] **清掉两条长期误报的「既有失败」**:`douyinRow`(ChatBadgeImage 加载失败后仍留在树中,应为 2 个不是 1 个;`find.text('10')` 依赖网络时序不可靠,改断言官方 URL)、`danmakuEmojiSegments`(代码已换 CachedNetworkImage、边长系数 1.6→1.15,断言同步)。全量从 +847-3 变 +854-1。
- [x] 查明并作废一条死兜底:官网硬编码粉丝牌底图模版 `fansBadge/3/{size}/{dark}/{level}.{name}` 实测 24 组合**全 404**,不得当兜底(参考工程 `resolveHuyaNamedBadgeBgUrl` 依赖的正是这条死链)。

### 验证
- 解析轨:`dart test` 560 全过(新增 `huya_chat_badges_test` 8 条 + `huya_fans_badge_resource_test`)。
- 根:`flutter analyze` 0;`dart run tool/check_design_tokens.dart` OK(28→28,各规则差值 0);`flutter test` 854 过 1 失败。
- `flutter build windows --debug -t lib/main.dart` ✓。

### 待办(下轮)
- [ ] **虎牙粉丝牌官方底图需实机确认**:`getResourceInfo` 需 `tUserId`,未登录/请求失败时 `url` 为空会走自绘降级。当前只验证了「URL 拼得对、analyze/测试全过」,**未验证真实弹幕里能加载成功**。需在可取到房间资源的环境目视确认;若仍见自绘样式,先查资源请求是否发出/是否被登录态拦住。
- [ ] **斗鱼贵族/至尊/钻粉图标仍是文字/数字占位**:官方 `noble/global/web.json` 的 `{host}`、至尊 `getDiamondIconExt({diafid})` 的 URL 规则均未确证,故只接字段不拼 URL(至尊=28×28 数字方块、贵族=「贵族 N」chip、超粉=金色 V、钻粉=「钻粉」chip)。需取到规则后替换为官方图。
- [ ] **`ne`/`sl`/`sid` 取值域未采到**:斗鱼抓包的 6 条样本里没有贵族/至尊用户,现按字段名直连、未做任何分档假设。需在有贵族/至尊用户的房间补抓样本。
- [ ] **`brid` 跨房粉丝牌显隐闸门未做**:字段已入库,官网是否隐藏跨房粉丝团牌无确证口径,不在无证据下改行为(当前零行为变化)。
- [ ] **`follow_style_shot_test` 关注页 golden 漂移**:来自另一轨 `29afd14 关注列表档内按观看数倒序并移除排序下拉` 改了排序未刷 golden。与聊天徽章无关,需该轨自行目检后 `--update-goldens`。
- [ ] **教训归档**:①拷 worktree 用 `git diff --name-only` 会漏未跟踪文件,应另拷 `git status --porcelain` 的 `??`;②多 worktree 顺序合并时,后一份 diff 是相对「不含前一份改动」的文件算的,直接打上去会**回退**先前的改动(本轮已发生一次,靠标记校验发现);③抖音在途轨把 1.6→1.15、`Image`→`CachedNetworkImage` 改了却没同步断言,长期红。
