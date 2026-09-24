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

