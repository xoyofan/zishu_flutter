import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/legacy/danmaku/danmaku_channel_resolver.dart';
import 'package:zishu_flutter/legacy/danmaku/douyu_ws_danmaku_channel.dart';
import 'package:zishu_flutter/legacy/danmaku/sse_danmaku_channel.dart';

void main() {
  test('默认矩阵：douyu → WS，其余 → SSE', () {
    expect(
      DanmakuChannelResolver.modeFor('douyu', null),
      DanmakuConnectorMode.browserWs,
    );
    for (final site in ['huya', 'bilibili', 'douyin', 'kuaishou', 'yy']) {
      expect(
        DanmakuChannelResolver.modeFor(site, null),
        DanmakuConnectorMode.serverSse,
        reason: site,
      );
    }
  });

  test('服务端 danmaku_connector 明键优先', () {
    const config = {
      'danmaku_connector': {'douyu': 'server_sse'},
    };
    expect(
      DanmakuChannelResolver.modeFor('douyu', config),
      DanmakuConnectorMode.serverSse,
    );
  });

  test('*_browser 键优先于明键，*_native 键不消费', () {
    const config = {
      'danmaku_connector': {
        'bilibili': 'server_sse',
        'bilibili_browser': 'browser_ws',
        'douyin': 'browser_ws',
        'douyin_native': 'server_sse',
      },
    };
    // bilibili：browser_ws 但无 WS 协议实现 → 回退 SSE。
    expect(
      DanmakuChannelResolver.modeFor('bilibili', config),
      DanmakuConnectorMode.serverSse,
    );
    // douyin：*_native 键忽略 → 默认 SSE。
    expect(
      DanmakuChannelResolver.modeFor('douyin', config),
      DanmakuConnectorMode.serverSse,
    );
  });

  test('rust_ws 在 Web 端回退 SSE', () {
    const config = {
      'danmaku_connector': {'bilibili_native': 'rust_ws'},
    };
    expect(
      DanmakuChannelResolver.modeFor('bilibili', config),
      DanmakuConnectorMode.serverSse,
    );
  });

  test('browser_ws 仅 douyu 有实现，huya 等回退 SSE', () {
    const config = {
      'danmaku_connector': {'huya': 'browser_ws'},
    };
    expect(
      DanmakuChannelResolver.modeFor('huya', config),
      DanmakuConnectorMode.serverSse,
    );
  });

  test('未知配置值走默认回退', () {
    const config = {
      'danmaku_connector': {'douyu': 'mystery_mode', 'huya': ''},
    };
    expect(
      DanmakuChannelResolver.modeFor('douyu', config),
      DanmakuConnectorMode.browserWs,
    );
    expect(
      DanmakuChannelResolver.modeFor('huya', config),
      DanmakuConnectorMode.serverSse,
    );
  });

  test('resolve 返回对应通道实例并带上 SSE base URL', () {
    const resolver = DanmakuChannelResolver();
    final ws = resolver.resolve('douyu');
    expect(ws, isA<DouyuWsDanmakuChannel>());
    expect(ws.site, 'douyu');

    final sse = resolver.resolve('huya', streamApiBaseUrl: 'http://h:1/');
    expect(sse, isA<SseDanmakuChannel>());
    expect(sse.site, 'huya');
  });
}
