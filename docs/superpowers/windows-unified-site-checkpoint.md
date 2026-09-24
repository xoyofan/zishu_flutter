# Windows 统一契约阶段交接（2026-09-24）

**状态：按用户要求暂停，未完成、未合并、未推送。** 工作分支 `feat/windows-unified-site-contract`，隔离工作树 `.worktrees/windows-unified-site/`，最后代码提交 `509e148`。不要把当前 `master` 的其他未提交改动混入本分支。

## 已完成并有验证记录

- Task 1 `RoomRecord`：统一房间值模型、旧 JSON 兼容、构造时冻结线路集合；6sol 审阅通过。
- Task 2 `LiveSite`：统一站点出口和可选能力；修复快手搜索能力假阳性、YouTube 恢复绕缓存、`all` 全部来源失败被吞；6sol 审阅通过。
- Task 3 第一批斗鱼/虎牙/B站：统一出口与真实 fixture 契约测试，6sol 复审通过；虎牙 WUP 原始零为不可信值，不能当有效 `0`。
- Windows 关注排序：超关在播 → 普通在播 → 轮播 → 未直播；各档内观看数降序，缺失最后、同数按关注时间倒序；移除“最近关注”下拉。6sol 复审通过。
- Windows 关注统计回归：点击关注不再把已取得的关注人数/VIP/SVIP 抹空；统计解析值逐字段优先，本地快照回退；云端关注条目集合/标记仍为准，云端提供的标题/主播/封面非空优先。6sol 复审通过，提交 `ca2d4a7`、`ed78b04`；上次验证记录为 Flutter 全量 778 通过、analyze 0、token guard OK、Windows debug build 通过（这些不代表当前 HEAD 的完整回归已重跑）。
- Task 3 第二批抖音/快手/YY：新增 fixture 测试并修正三站刷新状态，提交 `3d9e922`。YY 三次详情均缺 `totalViewer` 时状态不确定，改为抛错保留旧关注状态，提交 `509e148`。该子任务在**写报告阶段**因模型 `terminated` 失败，但提交已存在；当前 HEAD 已重新运行 `dart test test/src/platforms/yy`（29 通过）及 `dart analyze`（No issues found）。

## 暂缓/未验证

1. **YY `509e148` 尚未经过 6sol 的独立修复复审**；仅有上述定向测试和 parser analyze。不要将 Task 3 第二批标为最终验收。
2. Task 3 第三批 Twitch/SOOP/YouTube 的统一出口映射核对尚未执行。
3. Task 4：九站列表/详情/刷新公开类型与 Windows 消费层统一切换尚未执行。当前仍有旧 `RoomSummary`/`RoomPayload` 迁移桥；列表摘要默认 `offline` 与旧 `online` 判据的差异须在切换时处理。
4. Task 5：清理旧模型/桥接、当前 HEAD 全量 parser/app 分析与测试、Windows 真实解析 Release 构建和真机验收尚未执行。
5. 主工作树的 `AGENTS.md` 尚未记入“手动打包默认带真实解析”约定；现有 GitHub Windows Release workflow 已显式传 `--dart-define=ZISHU_REAL_PARSER=true`。此事未在本轮擅自改动。
6. 隔离工作树中的三个 `windows/flutter/generated_plugin*` 文件显示未暂存 `M`，此前 `git diff --exit-code` 为 0（索引/换行标记）；恢复工作时先核对，勿 `git add -A`。主工作树目前另有无关未提交文件，勿覆盖或清理。

下次恢复：先检查分支/工作树和 YY diff，复审 `509e148`，再决定是否继续 Task 3 第三批。未经全量门禁与 Windows 真实验收，不宣称统一契约已交付。
