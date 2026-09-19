# 播放域对齐 Wave 3:剩余 backlog 并行计划(2026-09-19)

> 方法论:dispatching-parallel-agents(同 Wave 2)。基线:app 524/0;parser 305/10skip;analyze 双 0。

## 优先级排序(价值 × 成本 × 风险;真源线索沿用 Wave2 调研)

| 优先级 | 任务 | 轨 | 理由 |
|---|---|---|---|
| P0 | cross-categories 全量 328 条 codegen(现仅 25 热门 key,displayCategoryName 第二层兜底不全,非热门分类名归一缺失) | A | 数据缺口确定性高,web `packages/shared/src/data/cross-categories.json` 为完整真源 |
| P0 | 分类缓存键升版(上轮 remap 表修正,旧缓存残留英文名/错拆名) | A | 小成本正确性,对齐 web c4f8ba4(v2→v4 流程) |
| P0 | kuaishou/soop/yy RoomSummaryRefresher 补齐(关注在播刷新覆盖面) | B | 四站已有实现,三站为同构补齐,成本低 |
| P1 | twitch 进房单清晰度档(web 6b4983e:默认高清档不解析其他档,提速) | B | 仅 twitch resolver 内部,不动公共契约 |
| P1 | AppTypography → context.textX 机械替换(UI 层,颜色随主题一致性收口) | C | 127 处/36 文件,纯机械低风险 |
| P1 | 搜索 type=anchors|rooms 分流(web SearchDialog 服务端分流) | D | SearchRequest 契约加参 + parser + UI 三层 |
| 推迟 | 徽章图片态全套、超粉 V/guard/wealth、twitch emote、关注批量导入、首页直达表单、移动目录抽屉、开播提醒通知、房间统计回填、pad-x 10.4、1920 底部工具栏 | — | 契约面宽/需产品裁决/纯视觉微调,记录 backlog |

## 文件归属矩阵(冲突红线)

| 轨 | 独占文件 |
|---|---|
| A | `tool/sync_cross_map.dart`(或新 codegen 脚本)、`packages/live_parser/lib/src/catalog/cross_*generated*`、`lib/src/shared/domain/category_display.dart` 数据源、分类缓存键常量(各平台 browse 缓存 key) |
| B | `packages/live_parser/lib/src/platforms/{kuaishou,soop,yy}/`(refresher 新文件 + 注册处)、`platforms/twitch/` 取流查询(resolve 层) |
| C | `lib/src/**` 的 UI widgets/views 文件(AppTypography 替换,排除轨 B 的 play application 两文件与所有 platforms/) |
| D | `packages/live_parser` contracts/models 的 SearchRequest + search 实现、`lib/src/features/search/**` |
| 共享只读 | `app_shell.dart`、`app_router.dart`、`models.dart`(DanmakuMessage/RoomSummary 不动) |

> 冲突消解:C 的替换范围**排除** `features/play/application/`(轨 B 潜在触点)与 `platforms/`;A/B 都在 packages/live_parser 但文件不相交(A:catalog/cache key;B:platforms refresher/twitch resolve)。

## 各轨任务卡(要点;子代理以任务卡全文为准)

- **A**:codegen 从 web cross-categories.json(328 条)生成全量表;`displayCategoryName` 第二层兜底从「25 热门」扩到全量;分类缓存键全部升版(旧键作废);fail-fast 校验;测试 +2(全量条数、命中样例)。
- **B**:kuaishou/soop/yy 各补 `RoomSummaryRefresher` 实现(对齐 douyu/huya/bilibili/douyin 四站:只取元信息不碰取流、不签名、不走短缓存);twitch resolver 进房仅解析默认高清档(web 6b4983e);测试 +3。
- **C**:`AppTypography.title/body/bodySecondary/caption` → `context.textTitle/textBody/textSecondary/textCaption`(带 color 参数的 copyWith 处保持行为等价);范围 = `lib/src/features/**/widgets|views` + `lib/src/apps/**`,排除 application/platforms;静态守则(light_theme_test)与全量回归必须绿。
- **D**:SearchRequest 加 `type`(anchors/rooms/null=混合);parser search 实现分流(web `type=anchors|rooms` 真源);search_view 双档(主播/房间 tab)接线到 type;测试 +2。

## 收尾(主代理)

`_gate.py` 全量 → golden 定性 → 4 笔分轨 commit → 推送 → release 重建 → schtasks 拉起。
