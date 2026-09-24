# Windows 站点统一契约 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 九个真实站点实现统一站点接口，Windows 浏览/刷新/播放使用同一种类型化房间记录；公共字段缺失为空，错误仍为错误，平台额外字段只可用明确类型扩展。

**Architecture:** 在纯 Dart `live_parser` 增加 `RoomRecord`、`LiveSite`，先用现有 `RoomSummary`/`RoomPayload` 和 `SiteRegistration` 过渡；逐站迁移、逐层切换 Windows，最后移除生产路径的双模型和桥接。`DanmakuMessage` 保持独立；缓存恢复和轻量刷新语义不变。

**Tech Stack:** Dart 3.13、Flutter 3.47、Riverpod、media-kit、`package:test`、`flutter_test`。不新增依赖。

**Spec:** `docs/superpowers/specs/2026-09-24-windows-unified-site-contract-design.md`

**执行分工（用户指定）：** 本会话 `chatgoai/gpt-6-sol` 负责关键接口/迁移决策、任务验收与最终源码审阅；具体代码任务由显式指定 `opencode-go/mimo-v2.6-flash` 的 subagent 执行。子任务按不重叠的文件边界委派，一次仅一个 writer 使用同一工作树；模型不可用时停下询问，不自动切换。设计或代码中的未决权衡由 6sol 决策，subagent 不擅自扩大范围。

## Global Constraints

- 只做 Windows 产品链路和共享纯 Dart parser；不实现 Web/Android 产品入口。
- `live_parser` 禁止依赖 Flutter/Widget/media-kit/`dart:ui`/`package:web`/`dart:js_interop`。
- 通用字段取不到用 `null`；数字 `0` 是有效数据；`roomState` 是在播唯一判据；不可把网络/协议错误伪装成空记录。
- 未声明能力是 N/A，声明但字段暂缺是「—」，请求失败是错误态；不让 Widget 直接消费松散 Map。
- 播放恢复绕开短缓存，刷新不取流不签名、不因本次缺字段抹掉旧值；空列表与接口缺失不同。
- Windows 构建真实解析时传 `--dart-define=ZISHU_REAL_PARSER=true`；发布需打包整个 Release 目录。
- 测试和分析前分别在 `packages/live_parser`、`packages/speech2zh` 执行 `dart pub get`；每次结构性修改至少 `flutter analyze` 与相关测试，Windows 主链路修改另跑 debug build。
- 保留独立解析轨/UI 轨提交；commit message 简体中文。前一轮未提交的 `docs/platform-progress-audit.md` 不属于本计划，勿混入提交。

## Review Focus

1. 直播且观众数未知：`roomState == live` 仍在播，展示「—」（Task 1、5）。
2. 轮播且历史观众数仍在缓存：刷新后的 `replay` 不可被统计字段重新判成 live（Task 1、5）。
3. 旧关注持久化 JSON 只有 `online`、`diamondFans`，没有 `roomState`：兼容读取且下一次写出不丢数据（Task 1、5）。
4. 恢复同房同画质：绕开 60s 短缓存拿新线路；轻量刷新不取流（Task 2）。
5. 上游请求抛错或部分站点不支持接口：前者可观察的异常/错误态，后者 N/A；不得吞错变空列表（Task 2、4）。

## 文件责任和迁移顺序

- `packages/live_parser/lib/src/models/room_record.dart`：统一值模型、旧 JSON 兼容读写、增量刷新合并、类型化扩展基类。
- `packages/live_parser/lib/src/contracts/contracts.dart`：统一 `LiveSite` 站点接口；迁移期保留旧端口。
- `packages/live_parser/lib/src/registry/site_registry.dart`：统一站点查找；迁移期桥接现有注册工厂；`cached_room_resolver.dart` 保持缓存职责。
- `packages/live_parser/lib/src/platforms/{douyu,huya,bilibili,douyin,kuaishou,yy,twitch,soop,youtube}/`：只做各站现有字段映射和接口适配；不顺手改变上游协议。
- `packages/live_parser/lib/src/cross/cross_browse.dart`：聚合记录类型，能力过滤/单站故障隔离保持原样。
- `lib/src/shared/application/{browse_source.dart,parser_sources.dart,fixture_sources.dart,search_source.dart}`：Windows 数据源统一类型和测试 fixture。
- `lib/src/features/{browse,follow,play,anchor,search}/`、`lib/src/app/shell/`、`lib/src/shared/presentation/platform_display.dart`：替换原两类房间入参和在线推断；平台扩展仅放专用展示组件。
- 旧 `models.dart` 的 `RoomSummary`/`RoomPayload` 在使用点切完、缓存与 JSON 兼容验证通过后移除；`DanmakuMessage` 不动。

---

### Task 1: 统一房间记录与旧格式兼容

**Files:**
- Create: `packages/live_parser/lib/src/models/room_record.dart`
- Modify: `packages/live_parser/lib/live_parser.dart`
- Test: `packages/live_parser/test/src/models/room_record_test.dart`
- Reference: `packages/live_parser/lib/src/models/models.dart` 中 `RoomState`、`RoomPayload`、`RoomSummary`、`StreamQuality`。

**Interfaces:**
- Produces: `RoomRecord({required String site, required String roomId, required RoomState roomState, String? title, String? anchorName, String? audience, String? followers, String? vip, String? svip, ...})`；`RoomRecord.fromSummary(RoomSummary)`、`RoomRecord.fromPayload(RoomPayload)`、`RoomRecord.toSummary()`、`RoomRecord.toPayload()`；`RoomRecord.mergeRefresh(RoomRecord fresh)`；`RoomRecord.toJson()` / `RoomRecord.fromJson(Map<String, dynamic>)`。
- Produces: `sealed class RoomExtension` 作为类型化扩展上界，`RoomRecord.extension` 为 `RoomExtension?`；只在确定一个当前平台的真实额外字段及 UI 消费点后添加第一个具体子类，不造九个空扩展。扩展的 JSON 必须带站点和版本判别；未知扩展安全保留可读取的公共字段。

- [ ] **Step 1: 写失败的模型契约测试**，固定 live/无观众、有效 0、replay、老 JSON 键与刷新合并（以下为测试核心，补齐构造参数和 import）：

```dart
test('live 房间即使没有 audience 仍为 live', () {
  final room = RoomRecord(site: 'douyu', roomId: '1', roomState: RoomState.live);
  expect(room.isLive, isTrue);
  expect(room.audience, isNull);
  expect(room.toJson().containsKey('audience'), isFalse);
});
test('0 与未知不同，刷新只覆盖有值字段而始终更新状态', () {
  final old = RoomRecord(site: 'huya', roomId: '2', roomState: RoomState.live,
      audience: '123', followers: '9');
  final fresh = RoomRecord(site: 'huya', roomId: '2', roomState: RoomState.replay,
      audience: '0');
  final merged = old.mergeRefresh(fresh);
  expect(merged.roomState, RoomState.replay);
  expect(merged.isLive, isFalse);
  expect(merged.audience, '0');
  expect(merged.followers, '9');
});
test('旧 JSON 统计键能读取', () {
  final room = RoomRecord.fromJson({'site':'huya','roomId':'2',
      'online':'12','diamondFans':'3','roomState':'live'});
  expect(room.audience, '12');
  expect(room.svip, '3');
});
```

- [ ] **Step 2: 跑红灯**：`cd packages/live_parser && dart test test/src/models/room_record_test.dart`；预期 `RoomRecord` 未定义。
- [ ] **Step 3: 最小实现**：模型必填站点/房号/状态；可空公共元信息/统计；播放线路缺省 `const []`；把原 `RoomPayload` 的 `playUrl`/`qualityByName` 逻辑搬为共享只读行为；四个转换函数只处理已有字段；`fromJson` 接受旧键 `online`/`diamondFans`，`toJson` 在迁移期同时输出兼容键；`mergeRefresh` 校验 `site + roomId` 匹配并保持未提供字段，状态强制使用 fresh。缺省 `roomState` 的旧 JSON 按旧 `online` 非空映射 live，否则 offline，仅用于读取历史数据。

```dart
// 核心语义（具体实现须覆盖全部现有公共字段）
bool get isLive => roomState == RoomState.live;
RoomRecord mergeRefresh(RoomRecord fresh) {
  if (site != fresh.site || roomId != fresh.roomId) {
    throw ArgumentError('cannot merge different rooms');
  }
  return copyWith(roomState: fresh.roomState,
    audience: fresh.audience ?? audience,
    followers: fresh.followers ?? followers);
}
```

- [ ] **Step 4: 跑绿灯**：`cd packages/live_parser && dart format lib/src/models/room_record.dart test/src/models/room_record_test.dart && dart test test/src/models/room_record_test.dart && dart analyze`；预期全过。再跑既有 `test/src/models/room_summary_json_test.dart`、`started_at_test.dart`。
- [ ] **Step 5: 解析轨提交**：只暂存本 Task 文件，`git commit -m '解析轨：新增统一房间记录与旧格式兼容'`。

### Task 2: 单一站点接口与缓存/能力契约

**Files:**
- Modify: `packages/live_parser/lib/src/contracts/contracts.dart`
- Modify: `packages/live_parser/lib/src/registry/site_registry.dart`
- Modify: `packages/live_parser/lib/src/registry/cached_room_resolver.dart`（仅在迁移需要时改返回类型，不能放弃绕缓存语义）
- Test: `packages/live_parser/test/registry_test.dart`
- Test: `packages/live_parser/test/src/registry/cached_room_resolver_test.dart`
- Test: `packages/live_parser/test/src/registry/cached_room_resolver_refresh_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `RoomRecord`、转换函数；旧 `RoomResolver` 等接口。
- Produces: `abstract interface class LiveSite`：`id`、`name`、`capabilities`、`display`、`Future<RoomRecord> resolveRoom(RoomRequest)`，可空 `BrowseRepository? browse`、`SearchRepository? search`、`DanmakuConnector? danmaku`、`RoomSummaryRefresher? refresher`、`RoomRecoveryResolver? recovery`。迁移中以薄适配让旧注册工厂可工作，`SiteRegistry` 新增 `LiveSite? site(String id)`，保留 `operator []` 直到 Windows 切换。

- [ ] **Step 1: 失败测试**：九站工厂逐个校验声明的 browse/search/danmaku 与部件是否存在；不存在时可空；部件存在但 `Future` 失败时 `throwsA`（使用现有 `registry_test.dart` 中的 fake 或在测试文件内定义最小 fake）；带偏好画质普通解析第二次走缓存，`recoverRoom` 请求次数增加且 URL 更新；`refreshRoomSummary` 不调用取流接口。

```dart
test('不支持弹幕的站点返回 null，而不是空连接', () {
  final site = buildSiteRegistry().site('yy')!;
  expect(site.danmaku, isNull);
  expect(site.capabilities.danmaku, isFalse);
});
```

- [ ] **Step 2: 跑红灯**：`cd packages/live_parser && dart test test/registry_test.dart test/src/registry/cached_room_resolver_test.dart test/src/registry/cached_room_resolver_refresh_test.dart`；预期新增 `site` 契约缺失。
- [ ] **Step 3: 实现统一外观**：包装 `SiteRegistration` 而不是改九站 HTTP 逻辑；`LiveSite.resolveRoom` 可暂用 `RoomRecord.fromPayload`，刷新可暂用 `RoomRecord.fromSummary`；恢复委托现有 `CachedRoomResolver.recoverRoom`，别改成缓存命中的普通解析。`capabilities` 与可空部件一致性在工厂/测试约束；对于 `CachedRoomResolver` 当前“总实现刷新、内层缺失再抛错”的做法，注册时按**内层真实能力**决定 `refresher` 是否为 null。
- [ ] **Step 4: 跑绿灯**：同 Step 2 测试加 `dart analyze`；针对恢复带不同播放 URL 和轻量刷新不取流检查断言。
- [ ] **Step 5: 解析轨提交**：`git commit -m '解析轨：统一站点接口并保持缓存恢复语义'`（只暂存 Task 2 文件）。

### Task 3: 九站分批输出统一记录

**Files:**
- Modify: `packages/live_parser/lib/src/platforms/{douyu,huya,bilibili,douyin,kuaishou,yy,twitch,soop,youtube}/*_site.dart` 及相应 `browse.dart`（只动结果组装处）
- Modify: `packages/live_parser/lib/src/cross/cross_browse.dart`
- Modify: `packages/live_parser/lib/src/models/models.dart` 中 `RoomListResult` 的泛型
- Test: `packages/live_parser/test/src/platforms/<site>/room_resolver_test.dart` / `browse_test.dart` / `room_summary_refresh_test.dart`（存在的文件才改）
- Test: `packages/live_parser/test/src/cross/cross_browse_test.dart`

**Interfaces:**
- Consumes: `LiveSite.resolveRoom → RoomRecord`、`RoomRecord` 的 JSON/merge 行为。
- Produces: `RoomListResult.rooms` 最终为 `List<RoomRecord>`；九站的 browse/refresh/resolve 最终公开返回统一记录；all 聚合按同一类型处理。**迁移期旧端口类型不变**：每站逐个替换 `LiveSite` 桥接内的转换逻辑，每次只在该站内部改组装，不得提前更改 `RoomListResult` 等全局返回类型。待九站与所有消费者准备好，在 Task 4 的同一编译边界统一切换公开返回类型。

按三批核对，每批以“站点 fixture 中确有值但转换丢失、状态判断错误、或缺失值变 0”等**实际失败断言**驱动修复；如果已有通用适配已满足该批断言，则记录通过、跳过无意义改动/提交。第一批斗鱼/虎牙/B站，第二批抖音/快手/YY，第三批 Twitch/SOOP/YouTube；保持站点原 HTTP 请求、签名、搜索和弹幕实现不变。每站测试覆盖其真实 fixture 中存在的 live/offline/replay、统计映射、URL/线路/headers；上游无某字段保持 `null`。

- [ ] **Step 1: 第一批先补失败断言**：通过 `registry.site(siteId)!.resolveRoom(request)` 验证统一 `RoomRecord` 的类型/状态/线路；原站点 `RoomSummaryRefresher` 的 fixture 值保持既有断言，并加 `RoomRecord.fromSummary(summary)` 对 `followers`/`vip`/`svip`、缺值 `null` 的测试。迁移期**不要**对仍返回旧类型的 `RoomResolver`/`BrowseRepository` 直接断言 `isA<RoomRecord>()`。
- [ ] **Step 2: 检查红灯或确认已覆盖**：`cd packages/live_parser && dart test test/src/platforms/douyu test/src/platforms/huya test/src/platforms/bilibili`；仅当新增断言暴露真实字段丢失/状态错误时继续 Step 3，否则保留测试、跳过冗余映射修改。
- [ ] **Step 3: 只迁移第一批组装点与注册工厂的统一映射**，旧端口仍返回旧类型；在该站 `LiveSite` 适配层返回 `RoomRecord` 并钉住字段映射，不提前改变全局 `RoomListResult`。站点层不再把 live 判定绑在 `audience` 文案；不修改网络响应解析。
- [ ] **Step 4: 跑绿灯并提交**：上面三站测试 + `dart test test/src/cross/cross_browse_test.dart` + `dart analyze`；`git commit -m '解析轨：统一斗鱼虎牙和 B 站房间输出'`。
- [ ] **Step 5: 第二批重复核对**：在抖音/快手/YY fixture 添加 `LiveSite.resolveRoom` 的统一状态、已知统计值、真正缺值和线路断言；运行 `dart test test/src/platforms/douyin test/src/platforms/kuaishou test/src/platforms/yy`。只有断言失败才修复对应站点映射；绿灯且 `dart analyze` 通过后，若有实际变更提交 `解析轨：统一抖音快手和 YY 房间映射`。
- [ ] **Step 6: 第三批重复核对**：在 Twitch/SOOP/YouTube fixture 添加同样断言，运行 `dart test test/src/platforms/twitch test/src/platforms/soop test/src/platforms/youtube test/src/cross`；只修复被测试证实的映射错误；`cross_browse.dart` 的公开类型保持旧形状至 Task 4；绿灯且 `dart analyze` 通过后，若有实际变更提交 `解析轨：统一海外站房间映射`。

```dart
// 对 `LiveSite.resolveRoom` 测试统一结果；统计 fixture 值从站点测试真实样本读取
expect(room, isA<RoomRecord>());
expect(room.roomState, RoomState.live);
expect(room.site, expectedSite);
expect(room.streams.first.lines.first.url, isNotEmpty);
expect(room.audience, expectedAudienceOrNull);
```

### Task 4: Windows 数据源、关注和 UI 切统一记录

**Files:**
- Modify: `lib/src/shared/application/browse_source.dart`
- Modify: `lib/src/shared/application/parser_sources.dart`
- Modify: `lib/src/shared/application/fixture_sources.dart`
- Modify: `lib/src/shared/application/search_source.dart`
- Modify: `lib/src/features/follow/application/follow_provider.dart`
- Modify: `lib/src/shared/presentation/platform_display.dart`
- Modify: `lib/src/features/browse/widgets/room_card.dart`
- Modify: `lib/src/features/play/widgets/play_side_panel.dart`
- Modify: `lib/src/features/play/widgets/play_meta_bar.dart`
- Modify: `lib/src/features/play/widgets/side_panel/side_panel_header.dart`
- Modify: other `lib/src/features/{browse,follow,play,anchor,search}/` and `lib/src/app/shell/` call sites returned by `rg 'RoomSummary|RoomPayload|online\.is(Not)?Empty|diamondFans' lib/src` (do not modify `lib/legacy/`)
- Test: `test/features/follow/follow_status_refresh_test.dart`
- Test: `test/ui/workflows/public_playback_state_test.dart`
- Test: `test/shared/platform_navigation_filter_test.dart`
- Test: `test/ui/workflows/platform_workflow.dart` (or its existing concrete test entrypoints)

**Interfaces:**
- Consumes: `RoomRecord`, `SiteRegistry.site()`, `RoomRecord.mergeRefresh()`；沿用 `SiteDisplaySpec`。
- Produces: Windows `BrowseSource.fetchRooms`、`RoomSource.resolveRoom/recoverRoom/refreshRoom` 与 follow 状态统一返回/保存 `RoomRecord`；展示 `roomStatValue(RoomRecord?, RoomStatField)`。

- [ ] **Step 1: 失败测试**：fixture 中 live 且 `audience == null` 的房卡仍显示在播；replay 且缓存有 audience 的关注行仍显示轮播；从旧 JSON 恢复关注数据再写回保留粉丝统计；UI formatter 声明列无值显示「—」、未声明不渲染；真实解析错误保留错误态。

```dart
test('缺观众数不把 live 卡片标成离线', () {
  const room = RoomRecord(site: 'douyu', roomId: '1', roomState: RoomState.live);
  expect(room.isLive, isTrue);
  expect(displayStatValue(roomStatValue(room, RoomStatField.audience)), '—');
});
```

- [ ] **Step 2: 跑红灯**：先跑新增的 `flutter test test/features/follow/follow_status_refresh_test.dart test/ui/workflows/public_playback_state_test.dart`；预期旧类型/在线推断断言不符。
- [ ] **Step 3: 分消费边界迁移**：先在同一编译边界切 `RoomListResult` / browse、resolver、refresh 的公开类型并更新 parser 全站/聚合及 Windows application port/provider/fixture，使所有调用方一次保持可编译；再迁移 follow 持久化/刷新和 widgets/formatter。若规模超出单次可验证提交，先把转换集中在应用端边界、保证每个提交编译通过，下一批再切公开类型。旧 JSON 读取兼容集中在模型边界；删除 `online.isNotEmpty` 与 `roomState == offline && hasAudience` 的实时回退，只有旧 JSON 反序列化可以做历史推断。不要在 UI 按 `site` 解包平台原始 Map；若现有字段足够，`extension` 保持 null，先不新增虚构平台扩展卡片。
- [ ] **Step 4: 跑绿灯**：`flutter test test/features/follow test/ui/workflows/public_playback_state_test.dart test/shared/platform_navigation_filter_test.dart`；再 `flutter analyze` 与 `flutter build windows --debug -t lib/main.dart`（先分别在两 package 执行 `dart pub get`）。
- [ ] **Step 5: UI 轨提交**：先将共享的 parser 公开类型切换单独作为解析轨提交并通过 `dart analyze && dart test`；然后只暂存 `lib/src/**` 和 `test/**` 相关文件，`git commit -m 'UI 轨：Windows 房间消费统一记录与状态语义'`。切公开类型期间允许短暂跨提交的编译缺口，但在本 Task 结束前 app/parser 均须全绿；不要在一个提交混 UI 与 parser 文件。

### Task 5: 删除双模型桥接并做整体回归

**Files:**
- Modify: `packages/live_parser/lib/src/models/models.dart`（移除已无生产引用的 `RoomPayload`、`RoomSummary`，保留消息/线路/能力等独立模型）
- Modify: `packages/live_parser/lib/src/contracts/contracts.dart`
- Modify: `packages/live_parser/lib/src/registry/site_registry.dart`
- Modify: `packages/live_parser/lib/src/registry/cached_room_resolver.dart`
- Modify: `packages/live_parser/lib/live_parser.dart`
- Modify: parser 与 Windows 仍引用旧类型的测试及 `docs/testing/windows-public-function-matrix.md`（仅按实际新验收结果更新）
- Test: `packages/live_parser/test/src/models/room_record_test.dart`
- Test: `packages/live_parser/test/src/registry/cached_room_resolver_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4 的统一类型/站点接口与旧 JSON 读取兼容。
- Produces: 生产代码 `rg 'RoomSummary|RoomPayload|SiteRegistration' lib/src packages/live_parser/lib/src` 结果为 0（历史注释/文档例外需人工核对）；`RoomRecord.fromJson` 仍能读旧键。

- [ ] **Step 1: 加入删除桥接前的失败检查**：给 `room_record_test.dart` 添加旧 JSON 解码→统一记录→再编码→再次解码的值保持断言；在缓存测试断言刷新跳过缓存、恢复改变 URL。用 `rg` 列出仍使用旧类型的生产文件，逐个清零。
- [ ] **Step 2: 跑旧 JSON 与缓存定向测试**：`cd packages/live_parser && dart test test/src/models/room_record_test.dart test/src/registry/cached_room_resolver_test.dart test/src/registry/cached_room_resolver_refresh_test.dart`；缺断言或旧模型残留时先确认失败原因。
- [ ] **Step 3: 删除过渡桥接和旧模型**；所有站点注册都返回 `LiveSite`，保留旧 JSON 别名读取，不删历史关注数据。若发现 `lib/legacy/` 仍消费旧 parser 导出，先确认迁移边界，不让 legacy 依赖反向侵入新产品。
- [ ] **Step 4: 解析轨门禁**：`cd packages/live_parser && dart analyze && dart test`；`dart test` 的在线测试如按现有配置跳过，照实记录；只暂存解析文件，提交 `解析轨：移除旧房间模型与站点桥接`。
- [ ] **Step 5: Windows 全量门禁**：在仓库根目录 `cd packages/live_parser && dart pub get`、`cd packages/speech2zh && dart pub get`（两条各自从根目录执行）；`flutter analyze`、`flutter test`、`flutter build windows --debug -t lib/main.dart`、`flutter build windows --release -t lib/main.dart --dart-define=ZISHU_REAL_PARSER=true`；任何失败先修再报告，不能依据先前会话结果宣称通过。
- [ ] **Step 6: 最新 Release 真机验收**：至少斗鱼/虎牙完成浏览→详情→播放→状态刷新→切画质/线路→断流后恢复；核对日志及截图，确认本迁移未破坏线路/状态/头像/统计。独立的黑屏、虎牙零弹幕、Twitch 出口等既有故障保持 FAIL/BLOCKED，不以本重构的测试绿灯关闭；矩阵只回填实际证据，文档单独中文提交。

## 执行注意

- 每个 Task 在自己的红绿周期后提交；Task 3 三批分别提交。修改 `packages/live_parser/**` 与 `lib/src/**` 时保持不同 commit。
- 计划中的 `RoomRecord` 字段完整性以现有 `models.dart` 的真实字段为准；不要为统一而删 `cateNo`、`headers`、`fetchedAt`、三态 replay 或 `DanmakuMessage` 信息。
- 平台特有扩展仅在找到真实数据来源、类型和值的展示位置后添加具体类和对应测试；`RoomExtension?` 的存在不是凭空制造字段的理由。
