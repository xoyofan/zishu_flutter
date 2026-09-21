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

  group('缓冲分档(用户口径 2026-09-21:twitch/soop/youtube 宁可变延迟也不断画面)', () {
    Map<String, String> profile(List<(String, String)> entries) => {
      for (final (name, value) in entries) name: value,
    };

    test('深缓冲档:起播不等待缓存(首帧优先),欠载恢复才攒 2s', () {
      // 用户口径 2026-09-22:进页面必须先出画面 —— 任何缓存等待都不得挡在
      // 起播前面;`cache-pause-wait` 只在欠载恢复时生效。
      final deep = profile(MediaKitLivePlayer.kDeepBufferProperties);
      expect(deep['cache-pause-initial'], 'no');
      expect(deep['cache-pause-wait'], '2');
    });

    test('深缓冲档:前向字节顶 96MiB(高码率也有十几秒以上余量)', () {
      // 旧值 32MiB 在 20 Mbps 下只有约 13s,高清源一抖就欠载;
      // 96MiB ≈ 20 Mbps 38s / 8 Mbps 96s。
      final deep = profile(MediaKitLivePlayer.kDeepBufferProperties);
      expect(deep['demuxer-max-bytes'], '100663296');
      expect(deep['demuxer-readahead-secs'], '8');
      expect(deep['cache-secs'], '90');
    });

    test('低延迟档:国内直连源不为起播额外等待,保持快速起播', () {
      final low = profile(MediaKitLivePlayer.kLowLatencyBufferProperties);
      expect(low['cache-pause-initial'], 'no');
      expect(low['cache-pause-wait'], '1');
      expect(low['demuxer-max-bytes'], '33554432');
      expect(low['demuxer-readahead-secs'], '2');
    });

    test('主机判定:twitch / youtube / soop 走深缓冲,国内站走低延迟', () {
      expect(
        MediaKitLivePlayer.needsDeepBuffer('apn12.playlist.ttvnw.net'),
        isTrue,
      );
      expect(MediaKitLivePlayer.needsDeepBuffer('gql.twitch.tv'), isTrue);
      expect(
        MediaKitLivePlayer.needsDeepBuffer('manifest.googlevideo.com'),
        isTrue,
      );
      expect(
        MediaKitLivePlayer.needsDeepBuffer('live-global-cdn-v02.sooplive.com'),
        isTrue,
      );
      expect(MediaKitLivePlayer.needsDeepBuffer('live.sooplive.co.kr'), isTrue);

      expect(MediaKitLivePlayer.needsDeepBuffer('hw1a.douyucdn2.cn'), isFalse);
      expect(MediaKitLivePlayer.needsDeepBuffer('al.hls.huya.com'), isFalse);
      expect(
        MediaKitLivePlayer.needsDeepBuffer('cn-hbwh-cm-01-03.bilivideo.com'),
        isFalse,
      );
      // 后缀匹配不误伤相似域名。
      expect(MediaKitLivePlayer.needsDeepBuffer('eviltwitch.tv'), isFalse);
    });

    test('两档覆盖同一组键,避免切换时残留上一个源的取值', () {
      final deep = MediaKitLivePlayer.kDeepBufferProperties
          .map((e) => e.$1)
          .toSet();
      final low = MediaKitLivePlayer.kLowLatencyBufferProperties
          .map((e) => e.$1)
          .toSet();
      expect(deep, equals(low));
    });

    test('回看缓冲仍在基础表里有界(4MiB,与源无关)', () {
      expect(asMap()['demuxer-max-back-bytes'], '4194304');
      expect(asMap()['cache'], 'yes');
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

    test('代理与缓冲档都按当前线路主机在 open 前重设', () {
      // mpv 既不读系统代理也不读 Dart 侧 findProxy:YouTube 的
      // manifest.googlevideo.com 实测直连 `tcp: Connection failed`;
      // 而 SOOP 等直连更快的站点走代理会慢一个数量级。mpv 的 http-proxy
      // 与缓冲项都是进程级选项,故每次 open 都按当前线路主机重设。
      final source = File(
        'lib/src/platforms/common/playback/media_kit_live_player.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('_applyStreamProfileFor'),
        reason: 'mpv 需显式 http-proxy,且必须按当前源主机决定走不走代理/多深缓冲',
      );
      expect(source, contains('UpstreamProxy.needsProxy(host)'));
      expect(source, contains('needsDeepBuffer(host)'));
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
