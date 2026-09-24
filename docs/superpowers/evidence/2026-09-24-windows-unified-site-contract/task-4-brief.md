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

