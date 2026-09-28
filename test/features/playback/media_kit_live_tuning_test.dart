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

  group('稳定缓冲配置(对齐斗鱼官方 web 缓冲窗口)', () {
    test('cache 开启且 6s 封顶,前向 128MiB / 6s 预读(官方 max_play_buffer_ms=6000)', () {
      final properties = asMap();
      expect(properties['cache'], 'yes');
      // 历史 60s → 20s → 10s → 6s:CDN 假时间线下流缓存层朝目标无意义预读,
      // 是内存爬升(+200MB/10min)推手;2026-09-28 对齐斗鱼官方 web 播放器
      // (getH5PlayV1 p2pMeta:max=6000/best=5000,超窗 1.05x 追帧),与
      // readahead(6s) 对齐,不叠加双层预读余量。
      expect(properties['cache-secs'], '6');
      // 窗口内前向字节上限提到 128MiB(高码率兼底),实际封顶项仍是 readahead。
      expect(properties['demuxer-max-bytes'], '134217728');
      // 预读秒数是前向缓冲的实际封顶项(字节上限很难够着);官方口径 6s。
      expect(properties['demuxer-readahead-secs'], '6');
    });

    test('回看缓冲 8MiB 有界', () {
      final properties = asMap();
      expect(properties['demuxer-max-back-bytes'], '8388608');
    });

    test('demuxer 独立线程读流(demuxer-thread=yes)', () {
      expect(asMap()['demuxer-thread'], 'yes');
    });

    test('丢帧策略 framedrop=yes(视频落后丢帧,与 video-sync=audio 成对)', () {
      final properties = asMap();
      expect(properties['framedrop'], 'yes');
      expect(properties['video-sync'], 'audio');
    });

    test('禁用缓存抽干自动暂停(cache-pause=no,堵死 mpv 自暂停源头)', () {
      // mpv 默认 cache-pause=yes:demuxer 缓存归零时自动置 pause=yes,表现为
      // "播放无故自暂停"(playback.log 16:33:14 实测,playing=false 且无
      // play_cmd)。直播下该暂停可能永不恢复,必须禁用,断流改由
      // buffering 看门狗 + 外部自暂停恢复计时器收敛。
      expect(asMap()['cache-pause'], 'no');
    });

    test('不做传输层透明重连(对齐 pure_live,坏流立即上抛)', () {
      // 2026-09-27 晚间下线 stream-lavf-o reconnect 四件套:透明重连会对
      // 卡死连接原地无限重试("Will reconnect at <offset>" 偏移不前进),
      // 重发旧数据把 FLV 时间戳打回跳 → mpv Reset playback 循环 = 用户
      // 看到的"重复播放"。pure_live 不开这层:坏流让 ffmpeg 立即报错,
      // 由上层有界看门狗(退避 + 上限 + 健康窗)收敛,坏连接不赖在原地。
      final properties = asMap();
      expect(properties['stream-lavf-o'], isNull);
      final source = File(
        'lib/src/platforms/common/playback/media_kit_live_player.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('reconnect_streamed')));
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
      expect(properties['volume-max'], '100');
    });

    test('硬解开启:auto-safe 与软解回退必须成对出现(修 CPU 42% 软解占用)', () {
      final properties = asMap();
      // mpv 默认 hwdec=no → Windows Release 播放整机 CPU 约 42%(24 核),
      // 暂停后降到 1.7%,确认为软件解码;auto-safe 失败时由
      // hwdec-software-fallback 回退软解,两者缺一不可。
      expect(properties['hwdec'], 'auto-safe');
      expect(properties['hwdec-software-fallback'], '1');
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
