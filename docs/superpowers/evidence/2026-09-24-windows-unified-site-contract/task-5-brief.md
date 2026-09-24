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
