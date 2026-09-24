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

