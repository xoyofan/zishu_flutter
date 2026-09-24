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

