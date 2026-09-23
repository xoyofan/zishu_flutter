# 现有平台显示与解析字段补齐实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为现有已注册平台建立共享展示契约，补齐可真实取得的时间/统计字段消费，并让 all 浏览/搜索/推荐覆盖现有平台能力。

**Architecture:** `live_parser` 继续作为平台字段与展示语义的单一真源；`SiteRegistration.display` 声明统计列和标签，`RoomSummary.startedAt` 贯穿解析、关注刷新和持久化。Flutter 通过纯 Dart helper 读取契约，桌面侧栏、移动播放条、搜索结果和状态卡共享格式化/空值策略；不把站点解析逻辑复制到 UI。

**Tech Stack:** Flutter/Dart/Riverpod、`packages/live_parser` 纯 Dart package、`live_parser` fixture、Material 3、现有 `ZishuTokens`/`AppSpacing`/`AppFocus`。

**Spec:** `docs/superpowers/specs/2026-09-24-platform-display-completion-design.md`

## Global Constraints

- 视觉真源是项目根 `DESIGN.md`；本轮不新增色值、字号、间距、圆角或 elevation。
- `live_parser` 禁止依赖 Flutter、Widget、`media-kit`、`dart:ui`、`package:web` 和 `dart:js_interop`。
- 新代码禁止 import `package:zishu_flutter/legacy/...`；UI 不直接消费松散 `Map<String, dynamic>`。
- 缺失数据不伪造为 `0`：已声明但无值显示 `—`，未声明的能力不渲染。
- 平台 parser、UI 轨和文档轨分开提交；提交说明使用简体中文。
- 每个生产行为先写失败测试并观察 RED，再写最小实现；不修改与本轮无关的既有失败。
- 推送前必须重新运行本轮局部测试、parser `dart analyze`/`dart test`、根 `flutter analyze`、`dart run tool/check_design_tokens.dart`、`flutter test` 和 Windows debug build。

## Review Focus

- 旧 JSON/旧关注条目没有 `startedAt` 时仍能恢复，且刷新失败不会抹掉已有统计。
- B站/抖音的第 2/3 列标签不能错位，SOOP 只能显示订阅而不能伪造超粉列。
- all 聚合中 IPTV 不应出现，任一站点失败不应让其它站点消失。
- 360px 移动播放条增加平台统计后不能溢出，既有 `play-meta-stat-*` 锚点不能消失。
- 轮播房间不能被搜索/房卡误显示为离线；搜索 all 结果不能丢失站点归属。
- 抖音/快手/YouTube 表情没有真实图片 URL 时必须保留协议文本，不生成假图片。

---

### Task 1: 建立 parser 展示契约

**Files:**
- Create: `packages/live_parser/lib/src/registry/site_display.dart`
- Modify: `packages/live_parser/lib/src/models/models.dart`
- Modify: `packages/live_parser/lib/src/contracts/contracts.dart`
- Modify: `packages/live_parser/lib/live_parser.dart`
- Modify: `packages/live_parser/lib/src/platforms/{douyu,huya,bilibili,douyin,kuaishou,soop,twitch,youtube,yy,iptv}/*_site.dart`
- Create: `packages/live_parser/test/src/models/site_display_spec_test.dart`
- Modify: `packages/live_parser/test/registry_test.dart`

**Interfaces:**
- Produces `enum RoomStatField { audience, vip, svip }`。
- Produces `enum RoomStatTone { audience, vip, svip }`。
- Produces `RoomStatColumn(field, label, tone)`。
- Produces `SiteDisplaySpec(showFollowers, showStartedAt, roomStats)`。
- Adds `SiteRegistration.display`, defaulting to `const SiteDisplaySpec()` so existing test registrations remain source-compatible.
- Exports `site_display.dart` from `package:live_parser/live_parser.dart`.

- [ ] **Step 1: Write the failing contract tests**

Add tests that assert the exact public matrix and old-registration compatibility:

```dart
test('每个注册平台的展示列与标签固定', () {
  final registry = buildSiteRegistry();
  expect(registry['douyu']!.display.roomStats.map((c) => c.label), ['观众', '贵宾', '钻粉']);
  expect(registry['huya']!.display.roomStats.map((c) => c.label), ['观众', '贵宾', '超粉']);
  expect(registry['bilibili']!.display.roomStats.map((c) => c.label), ['观众', '粉丝勋章', '大航海']);
  expect(registry['douyin']!.display.roomStats.map((c) => c.label), ['观众', '粉丝团', '会员']);
  expect(registry['soop']!.display.roomStats.map((c) => c.label), ['观看', '订阅']);
  expect(registry['twitch']!.display.roomStats.single.label, '观众');
  expect(registry['iptv']!.display.roomStats, isEmpty);
});

test('SiteRegistration 未传 display 时使用空展示能力', () {
  final registration = SiteRegistration(
    id: 'fake',
    name: 'Fake',
    capabilities: const SiteCapabilities(),
    resolver: const UnsupportedRoomResolver('fake'),
  );
  expect(registration.display.roomStats, isEmpty);
  expect(registration.display.showFollowers, isFalse);
  expect(registration.display.showStartedAt, isFalse);
});
```

Run:

```bash
cd packages/live_parser
dart test test/src/models/site_display_spec_test.dart
```

Expected: FAIL because the new enums/classes and `SiteRegistration.display` do not exist yet.

- [ ] **Step 2: Add the pure Dart display types**

In `models.dart`, define the enums and immutable value classes. `SiteDisplaySpec.roomStats` must default to `const []`; constructors are `const`; no Flutter imports are added. In `site_display.dart`, define the canonical constants:

```dart
const RoomStatColumn audienceStat = RoomStatColumn(
  field: RoomStatField.audience,
  label: '观众',
  tone: RoomStatTone.audience,
);
const RoomStatColumn watchingStat = RoomStatColumn(
  field: RoomStatField.audience,
  label: '观看',
  tone: RoomStatTone.audience,
);

const RoomStatColumn vipStat = RoomStatColumn(
  field: RoomStatField.vip,
  label: '贵宾',
  tone: RoomStatTone.vip,
);
const RoomStatColumn svipStat = RoomStatColumn(
  field: RoomStatField.svip,
  label: '钻粉',
  tone: RoomStatTone.svip,
);

const SiteDisplaySpec kDouyuDisplay = SiteDisplaySpec(
  showFollowers: true,
  showStartedAt: true,
  roomStats: [audienceStat, vipStat, svipStat],
);
```

为其它平台再定义同形状的具名常量（例如 `kHuyaDisplay`、`kBilibiliDisplay`、`kDouyinDisplay`、`kSoopDisplay`、`kTwitchDisplay`、`kKuaishouDisplay`、`kYyDisplay`、`kYoutubeDisplay`、`kIptvDisplay`），标签直接对应设计矩阵，不提供运行时拼接标签的 helper。

- [ ] **Step 3: Wire `SiteRegistration.display` and all registrations**

Add `this.display = const SiteDisplaySpec()` to `SiteRegistration`. Pass the matching `k*Display` constant from every `build*Registration` function. Keep `cross` display empty because `all` is not a room platform. Update test-only registrations only if they need a non-default display.

- [ ] **Step 4: Run the focused parser tests**

```bash
cd packages/live_parser
dart analyze
dart test test/src/models/site_display_spec_test.dart test/registry_test.dart
```

Expected: analysis clean and both tests pass.

- [ ] **Step 5: Commit the parser contract**

```bash
git add packages/live_parser/lib packages/live_parser/test/src/models/site_display_spec_test.dart packages/live_parser/test/registry_test.dart
git commit -m "解析轨：建立平台展示契约"
```

---

### Task 2: 补齐 `startedAt` 与现有平台真实字段

**Files:**
- Modify: `packages/live_parser/lib/src/models/models.dart`
- Modify: `packages/live_parser/lib/src/platforms/douyu/douyu_site.dart`
- Modify: `packages/live_parser/lib/src/platforms/soop/room_api.dart`
- Modify: `packages/live_parser/lib/src/platforms/soop/soop_site.dart`
- Modify: `packages/live_parser/lib/src/platforms/twitch/room_api.dart`
- Modify: `packages/live_parser/lib/src/platforms/twitch/twitch_site.dart`
- Modify: `packages/live_parser/lib/src/platforms/yy/room_api.dart`
- Modify: `packages/live_parser/lib/src/platforms/yy/yy_site.dart`
- Modify: `packages/live_parser/lib/src/platforms/youtube/dlp.dart`
- Modify: `packages/live_parser/lib/src/platforms/youtube/youtube_site.dart`
- Modify: `lib/src/features/follow/application/follow_provider.dart`
- Modify: `lib/src/features/play/widgets/play_side_panel.dart`
- Create: `packages/live_parser/test/src/models/started_at_test.dart`
- Modify: parser fixture tests for SOOP/Twitch/YY/YouTube and UI follow refresh tests.

**Interfaces:**
- Adds `DateTime? RoomSummary.startedAt` with JSON round-trip and old-JSON compatibility.
- `RoomPayload.startedAt` remains the existing optional field and is filled on paths where the source returns a timestamp.
- SOOP `fetchSoopDashboard` returns `({int fans, int subscribers, DateTime? startedAt})`.
- `TwitchStreamInfo` gains `DateTime? startedAt` parsed from GQL `createdAt`.
- `YyRoomDetail` exposes `DateTime? startedAt` from `startTime`.
- `YoutubeDlpExtract.liveStartAtSec` is converted to `RoomPayload.startedAt` when dlp succeeds.

- [ ] **Step 1: Write failing startedAt tests**

Add parser tests for JSON and source mapping:

```dart
test('RoomSummary startedAt roundtrip，旧 JSON 仍为 null', () {
  final at = DateTime(2026, 9, 24, 20, 30);
  final restored = RoomSummary.fromJson(RoomSummary(
    site: 'douyu', roomId: '1', title: '', anchorName: '', cid: '',
    category: '', online: '', cover: '', startedAt: at,
  ).toJson());
  expect(restored.startedAt, at);
  expect(RoomSummary.fromJson({'site': 'douyu'}).startedAt, isNull);
});

test('YY detail.startTime 转成 RoomSummary.startedAt', () async {
  final fake = FakeYyApi()..detailResponse = yyFixture('detail_live.json');
  final summary = await YyRoomResolver(YyClient(httpClient: fake)).refreshRoomSummary(
    const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909'),
  );
  expect(summary.startedAt, DateTime.fromMillisecondsSinceEpoch(1788911253 * 1000));
});

test('Twitch UseLive.createdAt 转成 RoomSummary.startedAt', () async {
  final fake = FakeTwitchApi()
    ..useLiveResponse = twitchFixtureData('use_live.json')['user'];
  final summary = await TwitchRoomResolver(TwitchClient(httpClient: fake)).refreshRoomSummary(
    const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
  );
  expect(summary.startedAt, DateTime.parse('2026-09-09T06:12:41Z').toLocal());
});
```

Also add a SOOP assertion for `station.broadStart`, a YouTube injected `YoutubeDlpExtract` assertion, and a follow-provider merge assertion that a fresh null does not erase a stored timestamp.

Run the focused tests and confirm they fail because the field/source plumbing is absent.

- [ ] **Step 2: Add `RoomSummary.startedAt` and serialization**

Add the optional constructor field, `if (startedAt != null) 'startedAt': ...` in `toJson`, and `DateTime.tryParse` in `fromJson`. Do not make it required, so all existing constructors and old JSON remain valid.

- [ ] **Step 3: Wire parser sources**

Use the existing source values without new network calls:

- Douyu refresh: `startedAt: room.startedAt`.
- SOOP dashboard: parse `station.broadStart` with `DateTime.tryParse`; return null on missing/invalid values; copy it into both offline/live `RoomSummary` instances.
- Twitch: add `createdAt` to `TwitchStreamInfo`, parse with `DateTime.tryParse`, and pass it to refresh/payload results.
- YY: add a getter that converts positive `startTime` seconds with `DateTime.fromMillisecondsSinceEpoch`; pass it to `RoomSummary` and `RoomPayload`.
- YouTube: change the dlp path to retain the `YoutubeDlpExtract` metadata long enough to pass `liveStartAtSec` into `_buildPayload`; do not parse page fallback timestamps that are not present.

Keep all failed/empty source values null.

- [ ] **Step 4: Preserve startedAt in the app follow layer**

Update `_currentRoom`, `_mergeRefreshed`, local JSON restoration and `_persist`. The merge rule is `fresh.startedAt ?? current.startedAt`; a failed/partial refresh must not erase the last known value. Keep `lastLiveAt` transition tracking unchanged.

- [ ] **Step 5: Run parser and follow tests**

```bash
cd packages/live_parser
dart analyze
dart test test/src/models/started_at_test.dart test/src/platforms/soop/room_summary_refresh_test.dart

cd F:\project\zishu_flutter
flutter test test/features/follow/follow_last_live_test.dart test/features/follow/follow_status_refresh_test.dart
```

Expected: all new and existing tests pass, with no `uri_does_not_exist` errors after `pub get`.

- [ ] **Step 6: Commit parser field wiring**

```bash
git add packages/live_parser/lib packages/live_parser/test lib/src/features/follow/application/follow_provider.dart lib/src/features/play/widgets/play_side_panel.dart
git commit -m "解析轨：接通各平台开播时间与摘要字段"
```

---

### Task 3: 让 all 浏览、搜索和推荐覆盖现有平台

**Files:**
- Modify: `packages/live_parser/lib/src/cross/cross_browse.dart`
- Modify: `lib/src/shared/application/search_source.dart`
- Modify: `lib/src/features/search/application/search_provider.dart`
- Modify: `lib/src/features/play/application/play_recommend_provider.dart`
- Modify: `packages/live_parser/test/registry_test.dart`
- Modify: `test/search/search_source_test.dart`
- Create: `packages/live_parser/test/src/cross/cross_site_selection_test.dart`

**Interfaces:**
- Produces `eligibleCrossBrowseSites(SiteRegistry)` and uses it as `CrossBrowseRepository.siteIds` when no explicit list is supplied.
- Excludes `all` and `iptv`, keeps registry order for existing sites, and appends future eligible IDs after the canonical order.
- `SearchSource.aggregateSites` is a getter implemented by parser and fixture sources; the real implementation derives from `search != null` and room/anchor capability.
- `recommendSites()` filters the expanded canonical order through `PlatformBrandCatalog.supportsBrowse`.

- [ ] **Step 1: Write failing aggregation tests**

Cover exact membership, IPTV exclusion, stable order, and single-site failure isolation:

```dart
test('all 浏览包含所有现有可浏览直播站，不含 all/iptv', () {
  final registry = buildSiteRegistry();
  expect(eligibleCrossBrowseSites(registry), [
    'douyu', 'huya', 'bilibili', 'douyin', 'kuaishou',
    'yy', 'twitch', 'soop', 'youtube',
  ]);
});

test('全平台搜索站点来自真实 search capability', () {
  final source = ParserSearchSource();
  expect(source.aggregateSites, containsAll(['douyu', 'huya', 'bilibili', 'douyin', 'yy', 'twitch', 'soop']));
  expect(source.aggregateSites, isNot(contains('iptv')));
});
```

Add a fake browse where one site throws and assert the other site’s room remains in the merged result.

- [ ] **Step 2: Implement dynamic cross browse membership and bounded fetch**

Keep the canonical order in one pure helper. Filter by `registration.capabilities.browse && registration.browse != null`, explicitly reject `kCrossSiteId` and `kIptvSiteId`. Change `CrossBrowseRepository` to accept `List<String>? siteIds` and initialize from the helper. Replace the unbounded `Future.wait` with chunks of at most four requests, preserving result order and the existing per-site failure isolation.

- [ ] **Step 3: Make search aggregation capability-driven**

Add `List<String> get aggregateSites` to `SearchSource`. `ParserSearchSource` returns IDs from its registry where a search repository exists and `roomSearch || anchorSearch` is true. `FixtureSearchSource` returns the fixture site IDs needed by existing tests. Replace the static three-site list in `SearchController` with `_source.aggregateSites`, keeping the existing `Future.wait` and per-site catch behavior.

- [ ] **Step 4: Expand recommendation platform order**

Replace the four-item recommendation order with the same canonical live-platform order used by cross browse, and keep the existing `supportsBrowse` filter. Do not include IPTV, `all`, or any site whose browse repository is absent in the real registry.

- [ ] **Step 5: Run aggregation/search tests**

```bash
cd packages/live_parser
dart test test/src/cross/cross_site_selection_test.dart test/registry_test.dart

cd F:\project\zishu_flutter
flutter test test/search/search_source_test.dart test/ui/workflows/play_recommend_panel_test.dart
```

- [ ] **Step 6: Commit aggregation wiring**

```bash
git add packages/live_parser/lib/src/cross/cross_browse.dart packages/live_parser/test/src/cross/cross_site_selection_test.dart packages/live_parser/test/registry_test.dart lib/src/shared/application/search_source.dart lib/src/features/search/application/search_provider.dart lib/src/features/play/application/play_recommend_provider.dart test/search/search_source_test.dart
git commit -m "功能轨：统一全平台浏览搜索推荐站点集合"
```

---

### Task 4: 建立 Flutter 共享展示 formatter

**Files:**
- Create: `lib/src/shared/presentation/platform_display.dart`
- Create: `test/shared/platform_display_test.dart`
- Modify: `lib/src/shared/presentation/platform_brands.dart` only if a cached registry/helper is needed.

**Interfaces:**
- `SiteDisplaySpec displaySpecFor(String site)` returns the registration display or an empty spec.
- `String roomStatValue(RoomSummary summary, RoomStatField field)` maps `audience/vip/svip` to `online/vip/diamondFans`.
- `String displayStatValue(String? raw)` returns trimmed text or `—`.
- `String formatFollowersValue(String? raw)` centralizes the existing 万-formatting rule.
- `String formatStartedAt(DateTime? value, {required bool isLive})` returns `MM-DD HH:mm`, `开播中`, or `—`.
- `bool siteSupportsDanmaku(String site)` reads the registration capability without making network calls.

- [ ] **Step 1: Write formatter tests first**

```dart
test('平台列值按契约映射，缺失值为占位符', () {
  const summary = RoomSummary(
    site: 'huya', roomId: '1', title: '', anchorName: '', cid: '',
    category: '', online: '12万', cover: '', followers: '12345',
    vip: '88', diamondFans: '',
  );
  expect(roomStatValue(summary, RoomStatField.audience), '12万');
  expect(roomStatValue(summary, RoomStatField.vip), '88');
  expect(displayStatValue(roomStatValue(summary, RoomStatField.svip)), '—');
  expect(formatFollowersValue('12345'), '1.2万');
});

test('平台声明决定列名而不是 UI site 分支', () {
  expect(displaySpecFor('douyin').roomStats.map((c) => c.label), ['观众', '粉丝团', '会员']);
  expect(displaySpecFor('soop').roomStats.map((c) => c.label), ['观看', '订阅']);
});
```

Run the test and observe the expected missing-symbol failure.

- [ ] **Step 2: Implement the pure helper**

Use a cached `SiteRegistry` only for synchronous display metadata; constructing registrations must not perform network I/O. Keep all formatting functions pure and use no `BuildContext`, so they can be tested in the parser/UI split.

- [ ] **Step 3: Run the helper test and token guard**

```bash
flutter test test/shared/platform_display_test.dart
dart run tool/check_design_tokens.dart
```

Expected: helper tests pass and the token guard reports no new violations.

- [ ] **Step 4: Commit the shared helper**

```bash
git add lib/src/shared/presentation/platform_display.dart test/shared/platform_display_test.dart lib/src/shared/presentation/platform_brands.dart
git commit -m "UI 轨：新增平台字段共享展示格式化层"
```

---

### Task 5: 用共享契约重写桌面/移动播放统计显示

**Files:**
- Modify: `lib/src/features/play/widgets/side_panel/side_panel_header.dart`
- Modify: `lib/src/features/play/widgets/play_meta_bar.dart`
- Modify: `lib/src/features/play/widgets/play_side_panel.dart` only for imports/keys if required.
- Modify: `test/ui/workflows/play_meta_bar_test.dart`
- Modify: `test/ui/play_page_test.dart` or `test/ui/workflows/side_panel_features_test.dart` for desktop stat labels.

**Interfaces:**
- Desktop and mobile consume `displaySpecFor(site)` and `roomStatValue` rather than `_platformVipStat/_showsVipStat`-style UI branches.
- Existing keys `play-side-stat-audience`, `play-side-stat-vip`, `play-side-stat-svip`, `play-meta-stat-followers`, `play-meta-stat-started`, `play-meta-stat-audience`, `play-meta-stat-danmaku` remain stable for supported rows.
- New mobile keys `play-meta-stat-vip` and `play-meta-stat-svip` identify platform-specific rows.

- [ ] **Step 1: Add failing platform-label/missing-row tests**

Extend the existing fake room source to accept any site and inject a summary with distinct values. Assert:

```dart
testWidgets('桌面侧栏按平台声明显示观众/粉丝团/会员列', (tester) async {
  await pumpDesktopPanel(site: 'douyin', summary: summary(vip: '', diamondFans: '66'));
  expect(find.byKey(const Key('play-side-stat-vip')), findsOneWidget);
  expect(find.byKey(const Key('play-side-stat-svip')), findsOneWidget);
  expect(find.text('粉丝团'), findsOneWidget);
  expect(find.text('会员'), findsOneWidget);
});

testWidgets('不支持的 VIP 列不渲染，缺失值仍显示占位符', (tester) async {
  await pumpDesktopPanel(site: 'twitch', summary: summary(vip: '88'));
  expect(find.byKey(const Key('play-side-stat-vip')), findsNothing);
  expect(find.byKey(const Key('play-side-stat-audience')), findsOneWidget);
});
```

Add a 360px mobile test that enables all douyin columns and asserts `tester.takeException()` is null.

- [ ] **Step 2: Replace desktop hardcoded mapping**

In `side_panel_header.dart`, remove `_platformVipStat`, `_platformSvipStat`, `_showsVipStat`, `_showsSvipStat` and label switches. Build the stat row from `displaySpecFor(site).roomStats`; use `roomStatValue`, `displayStatValue`, and a small icon/tone switch. Keep `FittedBox` and existing token colors so the desktop geometry remains stable.

Render `关注 N` only when `display.showFollowers` is true. For a declared but empty field, use `—`; for an undeclared field, omit it.

- [ ] **Step 3: Make the mobile bar contract-driven without overflow**

In `play_meta_bar.dart`:

- derive `site`, `displaySpec`, and summary from the existing payload/follow/roomStats sources;
- keep the follower, started, audience and danmaku keys when their corresponding capability is declared;
- append vip/svip rows from `display.roomStats` and use the same formatter as desktop;
- omit danmaku for a site whose registration says `danmaku == false`;
- replace the rigid two-row grid with a compact `Wrap`/`FittedBox` layout that can grow to the declared number of rows without changing avatar/action widths;
- keep `startedAt` display as `MM-DD HH:mm` when available, `开播中` for a live room without a timestamp, and `—` otherwise.

Do not add a new color or raw numeric style; use existing `AppFontSize`, `AppSpacing`, and `ZishuTokens`.

- [ ] **Step 4: Run focused playback tests**

```bash
flutter test test/ui/workflows/play_meta_bar_test.dart test/ui/play_page_test.dart test/ui/workflows/side_panel_features_test.dart
```

Expected: new platform matrix cases and all existing playback/anchor tests pass with no overflow exception.

- [ ] **Step 5: Commit playback display wiring**

```bash
git add lib/src/features/play/widgets/side_panel/side_panel_header.dart lib/src/features/play/widgets/play_meta_bar.dart lib/src/features/play/widgets/play_side_panel.dart test/ui/workflows/play_meta_bar_test.dart test/ui/play_page_test.dart test/ui/workflows/side_panel_features_test.dart
git commit -m "UI 轨：按平台契约统一播放统计显示"
```

---

### Task 6: 补齐搜索、房卡和时间线的公共状态显示

**Files:**
- Modify: `lib/src/features/search/widgets/search_result_tile.dart`
- Modify: `lib/src/features/search/views/search_view.dart`
- Modify: `lib/src/features/browse/widgets/room_card.dart`
- Modify: `lib/src/features/anchor/widgets/related_rooms.dart`
- Modify: `lib/src/features/anchor/widgets/timeline_tile.dart`
- Create: `test/ui/workflows/platform_display_surface_test.dart`
- Modify: `test/ui/search_test.dart` and relevant room-card/timeline tests.

**Interfaces:**
- `SearchResultTile` receives `site` in addition to `SearchHit`, renders the platform chip and non-empty `hit.fans`.
- `SearchHitState.replay` renders `轮播`, not `未开播`.
- Room cards use `RoomSummary.roomState` so replay is not covered by the offline overlay.
- Existing card keys and route callbacks remain unchanged.

- [ ] **Step 1: Write failing surface tests**

Cover all-search attribution, fans, replay and card status:

```dart
testWidgets('全平台搜索结果显示站点与粉丝数', (tester) async {
  await pumpSearchHit(const SearchHitItem(
    site: 'bilibili',
    hit: SearchHit(id: '1', anchor: '主播', title: '房间', avatar: '', cover: '',
      state: SearchHitState.live, category: '网游', online: '1万', fans: '12345'),
  ));
  expect(find.text('B站'), findsOneWidget);
  expect(find.text('粉丝 1.2万'), findsOneWidget);
});

testWidgets('轮播搜索结果显示轮播而不是未开播', (tester) async {
  await pumpSearchHit(itemWithState(SearchHitState.replay));
  expect(find.text('轮播'), findsOneWidget);
  expect(find.text('未开播'), findsNothing);
});

testWidgets('轮播房卡不显示离线遮罩', (tester) async {
  await pumpRoomCard(replaySummary);
  expect(find.byKey(const Key('room-card-offline')), findsNothing);
  expect(find.text('轮播'), findsOneWidget);
});
```

- [ ] **Step 2: Update search result tile and caller**

Add `site` to `SearchResultTile`, render `PlatformBadgeChip(site: site)` beside the anchor/state row, and render `fans` with a people icon and `formatFollowersValue`. Treat `live`, `replay`, and `offline` as three explicit visual states, using `tokens.brandBright` for replay and `tokens.textSecondary` for offline.

- [ ] **Step 3: Fix replay semantics on room/summary surfaces**

In `room_card.dart`, derive `live` from `room.isLive` and `replay` from `room.isReplay`; apply the offline overlay only when both are false, and add a small `轮播` cover badge for replay. Apply the same state check to related-room and timeline status text without changing their existing dimensions or keys.

- [ ] **Step 4: Run focused surface tests**

```bash
flutter test test/ui/workflows/platform_display_surface_test.dart test/ui/search_test.dart test/ui/browse_home_test.dart test/ui/anchor_timeline_test.dart
```

Expected: platform attribution/fans/replay tests pass and existing home/timeline tests remain green.

- [ ] **Step 5: Commit common surface display**

```bash
git add lib/src/features/search/widgets/search_result_tile.dart lib/src/features/search/views/search_view.dart lib/src/features/browse/widgets/room_card.dart lib/src/features/anchor/widgets/related_rooms.dart lib/src/features/anchor/widgets/timeline_tile.dart test/ui/workflows/platform_display_surface_test.dart test/ui/search_test.dart test/ui/browse_home_test.dart test/ui/anchor_timeline_test.dart
git commit -m "UI 轨：补齐平台搜索与轮播状态显示"
```

---

### Task 7: 平台聊天徽章/等级/表情显示矩阵收口

**Files:**
- Modify: `lib/src/features/play/widgets/side_panel/chat_badges.dart` only for shared fallback labels/tooltips.
- Modify: `lib/src/features/danmaku/domain/danmaku_style.dart` only if a real segment URL is not currently preserved in the overlay fallback.
- Modify: `test/ui/workflows/chat_badge_image_test.dart`
- Create: `test/ui/workflows/platform_chat_display_matrix_test.dart`
- Modify: parser chat tests only where a fixture exposes a previously unconsumed badge/segment field.

**Interfaces:**
- Every `DanmakuMessage.badges` item remains rendered in protocol order.
- A platform with no specific image asset uses the existing neutral text fallback and a meaningful tooltip.
- `DanmakuSegment.emoji` renders an image only when `url` is non-empty; otherwise it renders the protocol text.

- [ ] **Step 1: Write the platform matrix tests**

Use a fake connector per site and inject messages containing `userLevel`, `badges`, and emoji segments. Assert the four main platform styles, SOOP multi-badge order, generic fallback for Twitch/YY/快手/YouTube, and text fallback for an emoji with no URL. These tests must not access the network.

- [ ] **Step 2: Make only the missing display fixes**

If the matrix test shows a field is already rendered, do not rewrite the platform branch. Add only the missing tooltip/label or segment fallback. Do not manufacture a badge URL or infer a level from a missing field.

- [ ] **Step 3: Run chat tests**

```bash
flutter test test/ui/workflows/chat_badge_image_test.dart test/ui/workflows/platform_chat_display_matrix_test.dart test/features/danmaku
```

Expected: all existing badge tests and the new matrix pass.

- [ ] **Step 4: Commit chat display closure**

```bash
git add lib/src/features/play/widgets/side_panel/chat_badges.dart lib/src/features/danmaku/domain/danmaku_style.dart test/ui/workflows/chat_badge_image_test.dart test/ui/workflows/platform_chat_display_matrix_test.dart
git commit -m "UI 轨：收口各平台聊天徽章与表情显示"
```

---

### Task 8: 文档、门禁、提交与推送

**Files:**
- Modify: `docs/testing/windows-public-function-matrix.md`
- Modify: `todo.md`
- Modify: `tasks.md` only to record this completed display track and its verification results.
- Create: `docs/ui-parity/platform-display-matrix.md` with the final public/unique field table and explicit non-fixes.

- [ ] **Step 1: Write the final platform matrix**

Record for each of the ten registered IDs: browse/search/danmaku capability, common fields, platform-specific labels, `startedAt` source, UI surfaces, and `NOT_SUPPORTED`/`EMPTY_VALUE` semantics. Explicitly list Huya zero-message, Twitch connector, Kuaishou image URL and YouTube single-channel stream issues as non-display follow-ups.

- [ ] **Step 2: Run parser gates**

```bash
cd packages/live_parser
dart pub get
dart analyze
dart test
```

Expected: exit code 0; record exact passed/failed/skipped counts.

- [ ] **Step 3: Run root gates**

```bash
cd F:\project\zishu_flutter
flutter pub get
flutter analyze
dart run tool/check_design_tokens.dart
flutter test
flutter build windows --debug -t lib/main.dart
```

Expected: exit code 0 for each command; record raw result lines. If golden files change, inspect `test/ui/failures/*` images before accepting any update; do not blindly update goldens.

- [ ] **Step 4: Review the final diff and track boundaries**

```bash
git diff origin/master...HEAD --stat
git diff --check
git status --short
```

Confirm no `build/`, credentials, temporary screenshots, or unrelated TODO edits are staged. Confirm parser/UI/docs commits remain separable.

- [ ] **Step 5: Commit documentation and push**

```bash
git add docs/testing/windows-public-function-matrix.md docs/ui-parity/platform-display-matrix.md todo.md tasks.md
git commit -m "文档：回写平台显示矩阵与验收结果"
git push origin master
```

Use the repository’s existing credential path; never print or persist a token. After push, verify:

```bash
git status --short --branch
git log --oneline -5
```

Expected: working tree clean and local `master` aligned with `origin/master`.

## Final Self-Review Checklist

- [ ] Every production change had a failing test first.
- [ ] `SiteRegistration.display` is the only source of platform stat labels.
- [ ] `RoomSummary.startedAt` is optional and backward-compatible.
- [ ] All existing platform IDs are covered by parser capability/display tests.
- [ ] `all` browse/search/recommend include eligible existing platforms and exclude IPTV/`all`.
- [ ] Desktop/mobile stats use the same formatter and preserve existing anchors.
- [ ] Search all results retain platform attribution and real fans values.
- [ ] Replay is not rendered as offline on browse/search surfaces.
- [ ] No unsupported badge/emoji/image data is fabricated.
- [ ] Full parser/root/Windows verification evidence is recorded before push.
