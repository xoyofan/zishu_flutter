# 平台显示与解析字段矩阵

> 本文档是 2026-09-24 显示补齐计划（`docs/superpowers/plans/2026-09-24-platform-display-completion.md`）Task 8 的验收产物。
> 真源顺序：`DESIGN.md`（视觉）> `live_parser` 注册表（能力/字段语义）> 本文档（汇总证据）。
> 最后更新：2026-09-24（同日移除 IPTV、CC，见 §1）。

## 1. 注册平台清单（9 站）

| id | 站点 | 状态 |
|---|---|---|
| `douyu` | 斗鱼 | 已注册，主链路全能力 |
| `huya` | 虎牙 | 已注册，主链路全能力 |
| `bilibili` | B站 | 已注册，主链路全能力 |
| `douyin` | 抖音 | 已注册，主链路全能力 |
| `kuaishou` | 快手 | 已注册，**无搜索**（见 §4） |
| `yy` | YY | 已注册,弹幕已接入(现行 trident 协议) |
| `twitch` | Twitch | 已注册，**无 multiLine**（单线路 HLS） |
| `soop` | SOOP | 已注册，主链路全能力 |
| `youtube` | YouTube | 已注册，**无搜索**；依赖 yt-dlp 子进程 |
| ~~`iptv`~~ | IPTV | **2026-09-24 整平台移除**（解析轨 `85b0471` / UI 轨 `deb5096`），不再是缺口 |
| ~~`cc`~~ | CC | **已停运，无 parser 实现**；本轮清空全部残留（注释/parity 映射/legacy 能力表），不规划恢复 |
| ~~`xhs`~~ | 小红书 | 仅存于 Flutter fixture 品牌目录，**不伪装支持**，不进入真实入口（设计 §2.2 非目标） |

## 2. 能力矩阵（`SiteCapabilities`，与 `public_capability_matrix_test` 钉死一致）

| 平台 | Browse | Room search | Anchor search | Danmaku | Multi-quality | Multi-line |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| douyu | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| huya | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| bilibili | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| douyin | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| kuaishou | ✓ | — | — | ✓ | ✓ | ✓ |
| yy | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| twitch | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| soop | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| youtube | ✓ | — | — | ✓ | ✓ | ✓ |

- 能力为 `—` 的组合：UI 不渲染对应入口（不支持弹幕的站点显示明确 N/A 空态,不伪造）。
- YY 弹幕 2026-09-24 接入现行官方 Web trident 协议(h5-sinchl.yy.com,登录/注册/模板订阅/80216 弹幕帧,参考 SFVideoLive yy-stream.ts 2026-09-04 逆向);旧 pure_live 游客 join(uri=3104100)路径失效结论仅针对旧协议。**真实网络连通性待在线 smoke**。
- `all` 聚合（浏览/搜索/推荐）由注册表能力动态派生（`eligibleCrossBrowseSites` / `SearchSource.aggregateSites`），排除 `all` 自身；单站失败只损失该站结果。

## 3. 展示契约矩阵（`SiteRegistration.display`）

| 平台 | 关注数 | 开播时间 | 统计列（`RoomStatColumn` 标签） |
|---|:---:|:---:|---|
| 斗鱼 | 是 | 是 | 观众 / 贵宾 / 钻粉 |
| 虎牙 | 是 | 否（来源无稳定字段） | 观众 / 贵宾 / 超粉 |
| B站 | 是 | 否 | 观众 / 粉丝勋章 / 大航海 |
| 抖音 | 是 | 否 | 观众 / 粉丝团 / 会员 |
| SOOP | 是 | 是（dashboard `station.broadStart`） | 观看 / 订阅 |
| Twitch | 否 | 是（GQL `stream.createdAt`） | 观众 |
| 快手 | 否 | 否 | 观众 |
| YY | 否 | 是（`detail.startTime` 秒级时间戳） | 观众 |
| YouTube | 否 | 是（yt-dlp `liveStartAtSec` / `release_timestamp`） | 观看 |

**开播时间（`RoomSummary.startedAt`）其余来源**：斗鱼 `betard.show_time`。虎牙/B站/抖音/快手当前来源拿不到，保持 `null`，**不猜测**。

**消费面（共享 formatter `lib/src/shared/presentation/platform_display.dart`）**：
- 桌面播放侧栏 `_SideHeader`（`play-side-stat-*` 锚点）
- 移动 `PlayMetaBar`（`play-meta-stat-*` 锚点 + 契约驱动行）
- 搜索结果 `SearchResultTile`（平台归属 chip + `粉丝 N`）
- 房卡/关注卡/时间线（`room.isReplay` 轮播态不显示离线遮罩）

## 4. 空值与边界语义

| 情况 | 行为 |
|---|---|
| 已声明列、本次无值 | 渲染 `—`，Tooltip 用平台列名 |
| 未声明列 | 不渲染（快手无搜索 → 不进 all 搜索；YY 无弹幕 → N/A 态） |
| 旧 JSON 无 `startedAt` | `null`，向后兼容；刷新失败不清除已有值（`fresh.startedAt ?? current.startedAt`） |
| 单个 all 聚合站失败 | 保留其余站结果 |
| 轮播（replay）房间 | 显示「轮播」，不显示「未开播」/离线遮罩 |
| 表情无真实图片 URL | 保留协议文本，**不生成假图片** |
| 缺失字段 | **不填 `0`**，缺数据与不支持可区分 |

## 5. 明确的非本轮项（真实缺口，另立任务）

以下为**协议/网络级真实缺口**，不得因显示契约完成而声称已解决：

1. **虎牙弹幕「已连接但零消息」**（BUG-WIN-DANMAKU-003，协议/anti_code 层）；
2. **Twitch 弹幕连接与出口稳定性**（BUG-WIN-DANMAKU-004）——其 HTTP/弹幕代理分流属正常设计（`UpstreamProxy` 白名单），非缺口；
3. **快手表情真实图片 URL 未从协议取得**（PARSER-GAP-002，当前文本兜底）；
4. **YouTube 个别频道源不可播**（OBS-WIN-PLAY-001）；冷解析受 yt-dlp 子进程 2.8–4.7s 主导；
5. **飘屏多轨重叠观感**；
6. **功能缺口**：快手搜索能力、A11 导航能力过滤（已完成 438f743）、YY 弹幕（已完成,见 §2 注）；**待办**：YY 弹幕真实在线 smoke。

**不属于缺口（用户口径 2026-09-24）**：
- Twitch / 虎牙的上游代理（VPN）代码是正常功能，保留不处理；
- IPTV、CC 两平台为已移除/已停运，不规划补齐；
- CC/小红书不接入真实入口（设计 §2.2 非目标）。

**proxy 分流规则**（`UpstreamProxy.proxyHostSuffixes`）：只收直连不可达域（Twitch/YouTube/Google/HF/翻译实例）；国内站（虎牙/斗鱼/B站/抖音/快手/YY/SOOP）一律直连，`upstream_proxy_test` 断言 `needsProxy('al.hls.huya.com') == false`。
