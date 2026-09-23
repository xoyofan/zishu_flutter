# 真实网页聊天样式与徽章表情接线实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以 `SFVideoLive` 真实网页源码和实际渲染为证据，把现有平台弹幕中的表情、平台等级、粉丝徽章、虎牙超粉 V、B站大航海等字段接入 `live_parser` 与 Flutter 聊天侧栏。

**Architecture:** 扩展纯 Dart `DanmakuMessage`/`DanmakuBadge`/`DanmakuSegment` 稳定模型，平台 parser 负责把协议字段归一为这些模型；Flutter `ChatBadgeImage`、`_UserLevelBadge`、`_FanBadge` 和 `_ChatRow` 只负责 Web 样式映射与回退。缺失字段不生成假图，聊天行继续使用单段 `Text.rich` 保证折行顶格。

**Tech Stack:** Dart/Flutter、`packages/live_parser` 纯 Dart parser、现有 `Image.network`/`Image.asset`、Riverpod、Material 3、现有 design tokens。

**Spec:** `docs/superpowers/specs/2026-09-24-chat-evidence-style-design.md`

## Global Constraints

- 真实网页取证文件：`F:/project/SFVideoLive/apps/web/src/components/chat/ChatFanBadge.vue`、`ChatUserLevelBadge.vue`、`ChatHuyaSuperFanBadge.vue`、`DanmakuRichText.vue`、`components/play/play-side/SideChatTab.vue`、`utils/badges/*`、`utils/danmaku/*`。
- 实际渲染基准：`/douyu/play/5720533`，聊天 `14px / 1.48`；图片 filter `brightness(1.14) contrast(1.08) saturate(1.1)`。
- `live_parser` 禁止依赖 Flutter、Widget、`media-kit`、`dart:ui`、`package:web` 和 `dart:js_interop`。
- 新代码禁止 import `lib/legacy/`；UI 禁止直接解析原始 `Map`。
- 只补已有协议字段的真实展示；不凭字段名猜 badge URL、等级、guard 或表情图。
- 现有 SOOP `0109` 并行改动必须保留并纳入测试；不能回滚或覆盖。
- 视觉值沿用现有 `DESIGN.md`/token 体系；平台资源颜色是协议数据，不新增全局设计 token。
- 每个生产行为先写失败测试并观察 RED；不修改无关协议/网络问题。
- 推送前运行 parser analyze/test、根 analyze、design token guard、Flutter test 和 Windows debug build。

## Review Focus

- 斗鱼 `bimg/bc`、虎牙 `vFlag/vLogo`、B站 `guard/wealth`、抖音 badge URL、Twitch `badges/emotes` 任一字段缺失时不能导致整条消息丢失。
- `Text.rich` 顺序必须是用户等级 → 粉丝牌 → guard → 昵称/正文；长昵称/正文折行第二行仍从最左侧开始。
- 平台图片必须先走真实协议/官方资源，失败后走已有本地资源/文字回退；不能显示空白占位或虚构图片。
- SOOP `0109` 表情帧和 `0005` 多徽章同时存在时不能串改普通聊天。
- 360/500/1920 宽度都不能出现 RenderFlex overflow；图片加载失败不能留下额外间距。
- Twitch/YY/快手/YouTube 无真实徽章数据时不渲染空 badge；快手表情和无 URL 表情保留协议文本。

---

### Task 1: 扩展稳定弹幕模型并先锁定兼容性

**Files:**
- Modify: `packages/live_parser/lib/src/models/models.dart`
- Create: `packages/live_parser/test/src/models/danmaku_style_fields_test.dart`

**Interfaces:**
- `DanmakuBadge` 新增 `iconUrl`、`vFlag`、`vLogo`，默认 `''`/`0`。
- `DanmakuMessage` 新增 `guard`、`userLevelIconUrl`、`userLevelBadgeStyle`、`userLevelIsPolished`、`userLevelColor`，默认 `null`/`0`。
- `DanmakuSegment` 新增 `name`，默认 `''`；`text`/`emoji` 构造器继续可用。

- [ ] **Step 1: Write failing compatibility/field tests**

```dart
test('弹幕身份字段可表达 Web guard/等级/图片语义', () {
  final message = DanmakuMessage(
    type: DanmakuMessageType.chat,
    userName: '主播',
    userId: '1',
    text: '舰长你好',
    guard: const DanmakuBadge(
      name: '舰长', level: 3, color: 0xfff39c12, kind: 'guard',
    ),
    userLevelIconUrl: 'https://cdn.example/wealth.png',
    userLevelBadgeStyle: 2,
    userLevelIsPolished: 1,
    userLevelColor: 0xffffff,
  );
  expect(message.guard?.kind, 'guard');
  expect(message.userLevelIconUrl, contains('wealth'));
  expect(message.userLevelBadgeStyle, 2);
});

test('旧 DanmakuSegment 构造与空字段保持兼容', () {
  const segment = DanmakuSegment.emoji(text: '[smile]', url: 'https://x/e.png');
  expect(segment.name, isEmpty);
  expect(segment.url, 'https://x/e.png');
});
```

Run:

```bash
cd packages/live_parser
/f/flutter/bin/cache/dart-sdk/bin/dart.exe test test/src/models/danmaku_style_fields_test.dart
```

Expected: RED because the new fields do not exist.

- [ ] **Step 2: Add backward-compatible model fields**

Use `const` constructors and empty defaults. Do not add serialization or Flutter imports. Keep `badgeName/badgeLevel/badges` compatibility fields so existing parser/UI callers continue compiling.

- [ ] **Step 3: Run the model test and parser analysis**

```bash
/f/flutter/bin/cache/dart-sdk/bin/dart.exe analyze
/f/flutter/bin/cache/dart-sdk/bin/dart.exe test test/src/models/danmaku_style_fields_test.dart
```

Expected: analysis clean and the new model tests pass.

- [ ] **Step 4: Commit the model contract**

```bash
git add packages/live_parser/lib/src/models/models.dart packages/live_parser/test/src/models/danmaku_style_fields_test.dart
git commit -m "解析轨：扩展弹幕徽章与等级展示字段"
```

Do not stage the uncommitted SOOP parser file in this commit.

---

### Task 2: 接通斗鱼与虎牙真实徽章字段

**Files:**
- Modify: `packages/live_parser/lib/src/platforms/douyu/danmaku.dart`
- Modify: `packages/live_parser/lib/src/platforms/huya/danmaku.dart`
- Modify: `packages/live_parser/test/src/platforms/douyu/danmaku_test.dart`
- Modify: `packages/live_parser/test/src/platforms/huya/danmaku_test.dart`

**Interfaces:**
- Douyu fills one `DanmakuBadge` from `bn/bnn`, `bl/bnnl`, `bimg/bimgurl/badgeimg`, `bc` and keeps legacy `badgeName/badgeLevel`.
- Huya fills `vFlag/vLogo` from BadgeInfo tags 12/13 and `userLevelBadgeStyle/userLevelIsPolished` from ConsumeLevelBadgeInfo tags 2/3.

- [ ] **Step 1: Add failing parser assertions**

For Douyu extend the existing chat message fixture with `bimg`, `bimgurl`, `bc` and assert `badges.single.url/color`. For Huya extend the Tars decoration writer with tag 12/13/17 and assert `vFlag`, `vLogo`, `userLevelBadgeStyle`, `userLevelIsPolished`.

- [ ] **Step 2: Implement Douyu extraction**

Use the existing `parseDouyuStt` map. Select the first non-empty URL among `bimg`, `bimgurl`, `badgeimg`; convert `bc` to the existing packed RGB convention. Create `DanmakuBadge(name: badgeName, level: badgeLevel, color: parsedColor, url: url)` and keep old top-level fields for compatibility. Missing name/level remains invisible; missing URL still produces a text-capable badge.

- [ ] **Step 3: Implement Huya Tars extraction**

Read `BadgeInfo` tags 12 (`vFlag`), 13 (`vLogo`), 17 (`badgeType`) after tags 3/4. Read `ConsumeLevelBadgeInfo` tags 1/2/3. Catch `TarsDecodeException` around decoration parsing as the existing code does; a malformed decoration must not discard the chat body.

- [ ] **Step 4: Run platform parser tests**

```bash
cd packages/live_parser
/f/flutter/bin/cache/dart-sdk/bin/dart.exe test test/src/platforms/douyu/danmaku_test.dart test/src/platforms/huya/danmaku_test.dart
```

Expected: existing tests plus the new field assertions pass.

- [ ] **Step 5: Commit parser fields**

```bash
git add packages/live_parser/lib/src/platforms/douyu/danmaku.dart packages/live_parser/lib/src/platforms/huya/danmaku.dart packages/live_parser/test/src/platforms/douyu/danmaku_test.dart packages/live_parser/test/src/platforms/huya/danmaku_test.dart
git commit -m "解析轨：接通斗鱼虎牙真实徽章字段"
```

---

### Task 3: 接通 B站、抖音、Twitch 与 SOOP 表情/身份

**Files:**
- Modify: `packages/live_parser/lib/src/platforms/bilibili/danmaku.dart`
- Modify: `packages/live_parser/lib/src/platforms/douyin/protobuf_lite.dart`
- Modify: `packages/live_parser/lib/src/platforms/douyin/danmaku.dart`
- Modify: `packages/live_parser/lib/src/platforms/twitch/danmaku.dart`
- Modify: `packages/live_parser/lib/src/platforms/soop/danmaku.dart`（保留并行 `0109` 改动）
- Modify: `packages/live_parser/test/src/platforms/bilibili/danmaku_test.dart`
- Modify: `packages/live_parser/test/src/platforms/douyin/danmaku_test.dart`
- Modify: `packages/live_parser/test/src/platforms/twitch/danmaku_test.dart`
- Modify: `packages/live_parser/test/src/platforms/soop/danmaku_test.dart`

**Interfaces:**
- Bilibili emits `guard: DanmakuBadge(kind: 'guard', ...)` and `userLevelIconUrl` for a valid wealth key.
- Douyin carries badge URL/name and honor icon URL through `DouyinChatItem` into `DanmakuMessage`.
- Twitch carries IRC `badges` into `badges` and names each emote segment.
- SOOP `0109` emits a real `DanmakuSegment.emoji` and keeps 0005 badge order.

- [ ] **Step 1: Add failing Bilibili guard/wealth tests**

Extend the existing `metaUser` fixture with `guard_level: 3` and a wealth object containing `level` plus `dm_icon_key`. Assert `guard.name == '舰长'`, `guard.kind == 'guard'`, and `userLevelIconUrl` is the expected B站 wealth URL.

- [ ] **Step 2: Add failing Douyin badge/honor tests**

Extend the protobuf helper with a badge descriptor containing a fansclub URL/name and a pay-grade icon URL. Assert the message carries the URL and that the existing level/segment behavior remains unchanged.

- [ ] **Step 3: Add failing Twitch badge/emote tests**

Feed an IRC line with `badges=moderator/1,vip/4` and `emotes=25:0-4`. Assert a Twitch `DanmakuBadge` is present and the emoji segment has `name` and the deterministic CDN URL.

- [ ] **Step 4: Add/lock SOOP 0109 tests**

Use a synthetic escaped packet with opcode `0109`, group/sub id/version/user/flag fields and assert a `DanmakuSegment.emoji` with the generated URL. Keep the existing 0005 multi-badge test and assert subscriber → manager → topfan → fanclub order.

- [ ] **Step 5: Implement Bilibili extraction**

Prefer `metaUser.user.medal`; read `guard_level` and the wealth object/extra fallback only when valid. Map guard levels exactly to `总督`, `提督`, `舰长` and colors from the Web source. Set `userLevelIconUrl` only when a real wealth key/resource exists.

- [ ] **Step 6: Implement Douyin extraction**

Add optional `badgeName`, `badgeUrl`, `userLevelIconUrl` to `DouyinChatItem`. Parse repeated badge fields #61/#21 for URL, level and descriptor name; parse the honor image URL from the pay-grade structure when present. Pass all fields to `DanmakuMessage` without replacing the existing `text/segments` assembly.

- [ ] **Step 7: Implement Twitch extraction**

Parse the `badges` tag using the Web priority order and known local/CDN set IDs. Keep at least the highest-priority recognized badge as `DanmakuBadge(kind: 'twitch', url: ...)`; preserve existing emote range parsing and set `DanmakuSegment.name` to the original emote text.

- [ ] **Step 8: Preserve and verify SOOP 0109 implementation**

Do not reset the incoming SOOP file. Add the missing test and only adjust the implementation if the test exposes an invalid field index, URL construction, or ordinary-chat regression.

- [ ] **Step 9: Run all affected parser tests**

```bash
cd packages/live_parser
/f/flutter/bin/cache/dart-sdk/bin/dart.exe test test/src/platforms/bilibili/danmaku_test.dart test/src/platforms/douyin/danmaku_test.dart test/src/platforms/twitch/danmaku_test.dart test/src/platforms/soop
```

Expected: all affected tests pass, including existing emoji, badge, dedup and SOOP chat tests.

- [ ] **Step 10: Commit parser platform wiring**

```bash
git add packages/live_parser/lib/src/platforms/bilibili/danmaku.dart packages/live_parser/lib/src/platforms/douyin/protobuf_lite.dart packages/live_parser/lib/src/platforms/douyin/danmaku.dart packages/live_parser/lib/src/platforms/twitch/danmaku.dart packages/live_parser/lib/src/platforms/soop/danmaku.dart packages/live_parser/test/src/platforms/bilibili/danmaku_test.dart packages/live_parser/test/src/platforms/douyin/danmaku_test.dart packages/live_parser/test/src/platforms/twitch/danmaku_test.dart packages/live_parser/test/src/platforms/soop/danmaku_test.dart
git commit -m "解析轨：补齐平台徽章等级与表情字段"
```

---

### Task 4: 让 Flutter 聊天组件消费真实字段

**Files:**
- Modify: `lib/src/features/play/widgets/chat_badge_image.dart`
- Modify: `lib/src/features/play/widgets/side_panel/chat_row.dart`
- Modify: `lib/src/features/play/widgets/side_panel/chat_badges.dart`
- Modify: `lib/src/features/play/widgets/side_panel/chat_tab.dart`
- Modify: `test/ui/workflows/chat_badge_image_test.dart`
- Create: `test/ui/workflows/platform_chat_style_matrix_test.dart`

**Interfaces:**
- `ChatBadgeImage` accepts an optional remote `src` and falls back from remote to local asset to caller text fallback.
- `_ChatRowData` carries `guard`, `userLevelIconUrl`, `userLevelBadgeStyle`, `userLevelIsPolished`, and `userLevelColor`.
- `_ChatRow` renders `UserLevelBadge → FanBadge(s) → GuardBadge → user/body` inside one `Text.rich`.

- [ ] **Step 1: Write failing Widget matrix tests**

Use the existing fake connector helper from `chat_badge_image_test.dart`. Inject one message per platform and assert:

```dart
expect(find.text('LV10'), findsOneWidget);                 // douyu level
expect(find.byType(ChatBadgeImage), findsWidgets);          // image-capable badges
expect(find.text('舰长'), findsOneWidget);                 // bilibili guard
expect(find.text('超粉'), findsOneWidget);                 // huya V tooltip
expect(find.byKey(const Key('chat-emoji-image')), findsOneWidget);
```

Add a no-data case for Kuaishou/YouTube that asserts no empty badge widget and that protocol text remains visible.

- [ ] **Step 2: Extend `ChatBadgeImage` with remote-source fallback**

Add `src`/`remoteUrl` input without breaking existing asset-only callers. Prefer the supplied URL, then `badgeAssetPath`, then invoke `onFail`; use `Image.network` with `errorBuilder` and preserve the existing test asset behavior. Apply the Web image filter in a small shared widget wrapper rather than scattering color math.

- [ ] **Step 3: Carry the new fields through `_ChatRowData`**

Copy `message.guard`, `message.userLevelIconUrl`, `message.userLevelBadgeStyle`, `message.userLevelIsPolished`, and `message.userLevelColor` in `fromMessage`. Keep `message.badges` order and the existing `display: contents` equivalent (`Text.rich` inline flow).

- [ ] **Step 4: Implement `_GuardBadge` and Huya V**

Render B站 guard as a small bordered text chip using the parsed color/name. Render Huya `vFlag > 0` after the fan badge: use `vLogo` when present, otherwise a gold italic `V` with tooltip `超粉`. Do not add a V when the parser field is absent.

- [ ] **Step 5: Implement user-level image branches**

For Huya use `userLevelIconUrl`/emblem before the existing local asset; for Douyin use the honor URL before the local asset; for Bilibili use a valid wealth URL before the text gradient. Preserve the measured Douyu 2px radius, 1.15em height and `LV N` text style.

- [ ] **Step 6: Implement fan-badge remote branches**

Use protocol `iconUrl`/`url` before local assets for Douyu/Huya/B站/Douyin/SOOP/Twitch. Keep platform-specific dimensions, gradients, text overlays and fallbacks from the Web components. For Twitch render only the image and no invented name/level text.

- [ ] **Step 7: Add emoji name/tooltip and shared image filter**

Pass `DanmakuSegment.name` into the existing chat `WidgetSpan` image `Tooltip`/semantic label. Wrap badge/level/emoji images with the Web filter matrix. Keep text segments unchanged when URL is empty.

- [ ] **Step 8: Run Widget tests**

```bash
flutter test test/ui/workflows/chat_badge_image_test.dart test/ui/workflows/platform_chat_style_matrix_test.dart test/ui/workflows/danmaku_test.dart
```

Expected: existing badge/chat tests and the new platform matrix pass at phone/desktop widths with no overflow exception.

- [ ] **Step 9: Commit UI chat style wiring**

```bash
git add lib/src/features/play/widgets/chat_badge_image.dart lib/src/features/play/widgets/side_panel/chat_row.dart lib/src/features/play/widgets/side_panel/chat_badges.dart lib/src/features/play/widgets/side_panel/chat_tab.dart test/ui/workflows/chat_badge_image_test.dart test/ui/workflows/platform_chat_style_matrix_test.dart
git commit -m "UI 轨：按真实网页样式显示聊天徽章等级表情"
```

---

### Task 5: 真实网页对照回归与文档收口

**Files:**
- Create: `docs/ui-parity/chat-style-evidence.md`
- Modify: `docs/testing/windows-public-function-matrix.md`
- Modify: `todo.md`

- [ ] **Step 1: Record the evidence matrix**

Document the Web source paths, local preview route, computed style values, screenshot path (temporary, not committed), platform-by-platform field/style status, and explicit non-fixes. Include the current `0109` SOOP parser change and the fact that Kuaishou/Twitch/YouTube protocol reliability remains separate.

- [ ] **Step 2: Run focused parser gates**

```bash
cd packages/live_parser
/f/flutter/bin/cache/dart-sdk/bin/dart.exe pub get
/f/flutter/bin/cache/dart-sdk/bin/dart.exe analyze
/f/flutter/bin/cache/dart-sdk/bin/dart.exe test
```

Expected: exit 0; record exact test counts.

- [ ] **Step 3: Run root gates**

```bash
cd F:\project\zishu_flutter
/f/flutter/bin/flutter.bat pub get
/f/flutter/bin/flutter.bat analyze
/f/flutter/bin/cache/dart-sdk/bin/dart.exe run tool/check_design_tokens.dart
/f/flutter/bin/flutter.bat test
/f/flutter/bin/flutter.bat build windows --debug -t lib/main.dart
```

Expected: every command exits 0. Do not update goldens blindly; inspect any failure image first.

- [ ] **Step 4: Commit docs and push**

```bash
git add docs/ui-parity/chat-style-evidence.md docs/testing/windows-public-function-matrix.md todo.md
git commit -m "文档：记录真实网页聊天样式取证与验收"
git push origin master
git status --short --branch
```

Expected: clean worktree and local `master` aligned with `origin/master`.

## Final Self-Review Checklist

- [ ] 新模型字段全部有默认值，旧 parser/UI 测试未回归。
- [ ] 斗鱼/虎牙/B站/抖音/Twitch/SOOP 的真实字段已接线；快手/无 URL 表情不伪造资源。
- [ ] 聊天徽章顺序、尺寸、圆角、渐变、guard、V 和图片 filter 与 Web 证据一致。
- [ ] `Text.rich` 折行仍从最左侧开始，图片失败不留下幽灵间距。
- [ ] 临时 Web 截图、服务凭据和外部构建目录未进入 Git。
- [ ] 完整 parser/root/Windows 门禁有新鲜证据后才推送。
