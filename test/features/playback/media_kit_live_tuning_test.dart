/// 直播 mpv 属性调优表单测:配置注入的唯一来源是
/// [MediaKitLivePlayer.kLiveTuningProperties],`_applyLiveTuning` 构造期把它
/// 逐条 setProperty 到 NativePlayer(对每一次 open/起播生效)。
///
/// 为什么只断言配置表:VM 单测无法实例化 `NativePlayer`(要
/// `DynamicLibrary.open(libmpv)`),故按「纯配置断言配置值」覆盖 —— 表内容即
/// 生产注入内容,逐条对应关系由 `_applyLiveTuning` 的遍历保证。
///
/// 缓冲上限语义(对齐 SFVideoLive commit 7515cff:hls.js
/// `backBufferLength: 60`,防长时观看内存持续涨):mpv 侧以 `cache-secs=60`
/// 表达「回放缓冲约 60s 封顶」,字节顶 `demuxer-max-bytes` 在高码率下先到,
/// 两者任一到达即停止预读(mpv 手册)。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/media_kit_live_player.dart';

void main() {
  Map<String, String> asMap() => {
    for (final (name, value) in MediaKitLivePlayer.kLiveTuningProperties)
      name: value,
  };

  group('kLiveTuningProperties 缓冲上限(60s 封顶语义)', () {
    test('cache-secs=60:回放缓冲约 60s 封顶(对齐 hls.js backBufferLength: 60)', () {
      expect(asMap()['cache-secs'], '60');
    });

    test('前向字节硬顶保持 32MiB,高码率先于 60s 到达即封顶', () {
      expect(asMap()['demuxer-max-bytes'], '33554432');
    });

    test('回看缓冲保持 4MiB 有界(mpv 手册:back buffer 无秒级控制)', () {
      expect(asMap()['demuxer-max-back-bytes'], '4194304');
    });

    test('预读秒数保持 2s 低延迟目标(cache-secs 与之取较大者)', () {
      expect(asMap()['demuxer-readahead-secs'], '2');
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

    test('上游代理注入 mpv(http-proxy):被墙 CDN 只能经代理播放', () {
      // mpv 既不读系统代理也不读 Dart 侧 findProxy:YouTube 的
      // manifest.googlevideo.com 实测直连 `tcp: Connection failed`,
      // 必须由 _applyLiveTuning 从 UpstreamProxy 取运行期值注入。
      final source = File(
        'lib/src/platforms/common/playback/media_kit_live_player.dart',
      ).readAsStringSync();
      expect(
        source,
        contains("setProperty('http-proxy', 'http://\$proxy')"),
        reason: 'mpv 需显式 http-proxy,否则被墙线路永远连不上',
      );
      expect(source, contains('UpstreamProxy.hostPort'));
    });

    test('属性名不重复(重复设置以最后一条为准,易掩盖配置意图)', () {
      final names = MediaKitLivePlayer.kLiveTuningProperties
          .map((entry) => entry.$1)
          .toList();
      expect(names.toSet().length, names.length);
    });
  });
}
