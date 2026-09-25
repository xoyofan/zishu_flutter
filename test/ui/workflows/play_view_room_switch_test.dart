/// 切房回归:同一页面元素复用时,标题/主播信息/播放器必须一起切到新房间。
///
/// 复现根因:go_router 对同一路由模式 `/:site/play/:id` 切房会复用页面元素,
/// PlayView 若缓存首次 `_params`,播放器被新房间打开但 UI 仍显示旧房间。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart'
    show playerProvider;
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

import '../../support/recording_live_player.dart';

/// 按 (site, roomId) 返回可区分标题/主播/线路的假解析源。
class _TwoRoomSource implements RoomSource {
  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    final key = '$site/$roomIdOrUrl';
    return RoomPayload(
      site: site,
      roomId: roomIdOrUrl,
      sourceUrl: 'https://example.test/$key',
      anchorName: '主播-$key',
      title: '标题-$key',
      cover: '',
      avatar: '',
      category: '分类-$key',
      cid: key,
      roomState: RoomState.live,
      streams: [
        StreamQuality(
          name: '超清',
          rate: 2,
          lines: [
            StreamLine(
              name: 'HLS',
              url: 'https://fixture.zishu.dev/$key/index.m3u8',
              format: 'hls',
            ),
          ],
        ),
      ],
      availableQualities: const [],
      source: 'live_parser/test',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

Widget _host(RoomSource source, LivePlayer player, String site, String roomId) {
  return ProviderScope(
    overrides: [
      roomSourceProvider.overrideWithValue(source),
      playerProvider.overrideWithValue(player),
    ],
    child: MaterialApp(
      home: PlayView(site: site, roomId: roomId),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('切房复用同一元素:标题/主播与播放器 open 全部切到新房间', (tester) async {
    final player = RecordingLivePlayer();
    addTearDown(player.dispose);

    // A 房(douyu/1001)
    await tester.pumpWidget(_host(_TwoRoomSource(), player, 'douyu', '1001'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('标题-douyu/1001'), findsOneWidget);
    expect(find.text('主播-douyu/1001'), findsOneWidget);
    expect(
      player.openCalls.map((c) => c.line.url),
      contains('https://fixture.zishu.dev/douyu/1001/index.m3u8'),
    );
    // 走完首帧后的 15s 画质预取定时器,避免测试结束时 pending timer。
    await tester.pump(const Duration(seconds: 16));

    // 切到 B 房(soop/2002):同一位置同一 widget 类型 → 元素被复用
    await tester.pumpWidget(_host(_TwoRoomSource(), player, 'soop', '2002'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('标题-soop/2002'), findsOneWidget);
    expect(find.text('主播-soop/2002'), findsOneWidget);
    expect(find.text('标题-douyu/1001'), findsNothing);
    expect(
      player.openCalls.map((c) => c.line.url),
      contains('https://fixture.zishu.dev/soop/2002/index.m3u8'),
    );
    await tester.pump(const Duration(seconds: 16));
  });
}
