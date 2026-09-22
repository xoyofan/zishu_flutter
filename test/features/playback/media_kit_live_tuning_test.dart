/// 直播 mpv 属性调优表单测：配置注入的唯一来源是
/// [MediaKitLivePlayer.kLiveTuningProperties]。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/media_kit_live_player.dart';

void main() {
  Map<String, String> asMap() => {
    for (final (name, value) in MediaKitLivePlayer.kLiveTuningProperties)
      name: value,
  };

  group('统一缓冲配置(对齐 pure_live)', () {
    test('前向缓冲保持 32MiB / 2s 预读 / 60s 封顶', () {
      final properties = asMap();
      expect(properties['demuxer-max-bytes'], '33554432');
      expect(properties['demuxer-readahead-secs'], '2');
      expect(properties['cache-secs'], '60');
    });

    test('回看缓冲保持 4MiB 有界', () {
      final properties = asMap();
      expect(properties['demuxer-max-back-bytes'], '4194304');
      expect(properties.containsKey('cache'), isFalse);
    });

    test('不按线路主机切换深缓冲配置', () {
      final source = File(
        'lib/src/platforms/common/playback/media_kit_live_player.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('kDeepBufferProperties')));
      expect(source, isNot(contains('kLowLatencyBufferProperties')));
      expect(source, isNot(contains('needsDeepBuffer')));
      expect(source, contains('_applyProxyForLine'));
    });
  });

  group('kLiveTuningProperties 既有调优防回归', () {
    test('协议白名单含直播所需协议(斗鱼主线路 rtmp://)', () {
      expect(
        asMap()['protocol_whitelist'],
        'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto,rtmp,rtmps,rtsp,srt',
      );
    });

    test('网络超时与探测加速仍在', () {
      final properties = asMap();
      expect(properties['network-timeout'], '15');
      expect(properties['demuxer-lavf-probesize'], '2097152');
      expect(properties['demuxer-lavf-analyzeduration'], '2');
      expect(properties['force-seekable'], 'yes');
      expect(properties['hwdec-software-fallback'], '1');
      expect(properties['video-sync'], 'audio');
      expect(properties['volume-max'], '100');
    });

    test('代理仍按当前线路主机在 open 前重设', () {
      final source = File(
        'lib/src/platforms/common/playback/media_kit_live_player.dart',
      ).readAsStringSync();
      expect(source, contains('_applyProxyForLine'));
      expect(source, contains('UpstreamProxy.needsProxy(host)'));
      expect(source, contains("'http-proxy'"));
    });

    test('属性名不重复(重复设置以最后一条为准,易掩盖配置意图)', () {
      final names = MediaKitLivePlayer.kLiveTuningProperties
          .map((entry) => entry.$1)
          .toList();
      expect(names.toSet().length, names.length);
    });
  });
}
