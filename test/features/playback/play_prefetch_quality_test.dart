/// 播放页「其他画质线路后台预取」行为锚点。
///
/// 用户口径(2026-09-21):首档先起播,其余档位线路在后台异步补齐;
/// 切换画质时优先复用已预取线路,不再等一次线上解析。
///
/// 数据源用逐档返回不同线路的替身:每档 payload 只给该档真实线路、
/// 其余档位空线路占位 —— 与真实平台(懒取流)同构。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

import '../../support/scripted_live_player.dart';

/// 逐档返回:被请求的档带 HLS 线路,其余档空线路占位。
class _LazyQualityRoomSource implements RoomSource {
  _LazyQualityRoomSource({required this.qualities});

  final List<String> qualities;
  final calls = <String>[];

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    // 与真实平台同口径:偏好档不在列表时回落首档(否到就退)。
    final requested = preferredQuality ?? '';
    final picked = qualities.contains(requested) ? requested : qualities.first;
    calls.add(picked);
    // 让后台预取与首帧竞争,验证它不阻塞起播。
    await Future<void>.delayed(const Duration(milliseconds: 1));
    return RoomPayload(
      site: site,
      roomId: roomIdOrUrl,
      sourceUrl: 'https://$site.example.com/$roomIdOrUrl',
      anchorName: '主播',
      title: '标题',
      cover: '',
      avatar: '',
      category: '测试',
      cid: '1',
      roomState: RoomState.live,
      streams: [
        for (final name in qualities)
          StreamQuality(
            name: name,
            rate: qualities.indexOf(name) + 1,
            lines: name == picked
                ? [
                    StreamLine(
                      name: 'HLS',
                      url: 'https://cdn.example.com/$name.m3u8',
                      format: 'hls',
                    ),
                  ]
                : const [],
          ),
      ],
      availableQualities: [
        for (final name in qualities)
          QualityOption(name: name, rate: qualities.indexOf(name) + 1),
      ],
      source: 'test',
      fetchedAt: DateTime.now(),
    );
  }
}

void main() {
  test('其他画质线路后台补齐,切档直接复用预取线路(不再重新解析)', () async {
    final source = _LazyQualityRoomSource(qualities: const ['原画', '高清', '流畅']);
    final player = ScriptedLivePlayer();
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWithValue(player),
        roomSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(() {
      container.dispose();
      player.dispose();
    });

    final params = (site: 'douyu', roomId: '1');
    final keepAlive = container.listen(
      playControllerProvider(params),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(keepAlive.close);

    // 首档(默认画质键)先起播,不等后台预取。
    final first = await container.read(playControllerProvider(params).future);
    expect(first.line, isNotNull, reason: '首档必须立即有线路可播');

    // 等后台预取把其余两档补齐(等待真实结果,而不是「已发起」)。
    await _until(() {
      final payload = container
          .read(playControllerProvider(params))
          .value
          ?.payload;
      if (payload == null) return false;
      return payload.qualityByName('高清')!.lines.isNotEmpty &&
          payload.qualityByName('流畅')!.lines.isNotEmpty;
    }, timeoutMessage: '后台预取未补齐其余档位,实际请求: ${source.calls}');

    final state = container.read(playControllerProvider(params)).requireValue;
    final lines = {
      for (final stream in state.payload!.streams)
        stream.name: stream.lines.length,
    };
    expect(lines['高清'], greaterThan(0), reason: '预取后「高清」档应带线路');
    expect(lines['流畅'], greaterThan(0), reason: '预取后「流畅」档应带线路');

    final callsBeforeSwitch = source.calls.length;
    final target = state.payload!.streams.firstWhere((s) => s.name == '流畅');
    container
        .read(playControllerProvider(params).notifier)
        .switchQuality(target);
    await player.waitForOpenCount(2);

    expect(source.calls.length, callsBeforeSwitch, reason: '切到已预取档位不应再发起解析');
    expect(
      player.openCalls.last.line.url,
      contains('流畅'),
      reason: '应以预取到的该档线路开流',
    );
    expect(
      container.read(playControllerProvider(params)).requireValue.quality?.name,
      '流畅',
    );
  });
}

/// 轮询等待条件成立(上限约 10s:预取含首批错开 800ms + 真实网络往返,
/// 全量套件并发执行时机器繁忙,预算要给足)。
Future<bool> _until(
  bool Function() condition, {
  required String timeoutMessage,
}) async {
  for (var i = 0; i < 500; i++) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(timeoutMessage);
}
