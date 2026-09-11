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
