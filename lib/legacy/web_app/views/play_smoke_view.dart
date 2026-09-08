/// E7 前置的播放冒烟视图（临时）：`/:site/play/:roomId` 与穿段深链兜底的真身。
///
/// 职责（最小集，U5 正式播放页落地后整体替换）：
/// 1. `streamApi.fetchRoom` 拉房间 payload → 挑首选档/线路 →
///    [WebVideoPlayerAdapter] 播放（headers 非空的线路由适配层改写代理）；
/// 2. [DanmakuChannelResolver] 按服务端矩阵连弹幕通道，累计消息数；
/// 3. 全程把 phase/error/danmaku 写入 `window.zishuSmoke`（JS 对象）并 print
///    到 console，供 tool/smoke_play.mjs（playwright 无头）断言读取。
///
/// phase 状态机：loading → room → opening → ready → playing（或 error）。
/// site/roomId 依次取：构造参数 → Get.parameters → 当前路由正则解析
/// （兜底路由 `/(.*)` 下 Get.parameters 拿不到穿段 roomId）。
// 冒烟视图以 console 输出为功能本体（playwright 采集），豁免 avoid_print。
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../danmaku/danmaku.dart';
import '../../web_platform/playback/playback.dart';

/// `window.zishuSmoke`：playwright 无头断言读取的冒烟状态对象。
@JS('zishuSmoke')
external set _zishuSmoke(JSAny? value);

class PlaySmokeView extends StatefulWidget {
  const PlaySmokeView({super.key, this.site = '', this.roomId = ''});

  /// 缺省时由路由自行解析（正常路由读 Get.parameters，穿段兜底走正则）。
  final String site;
  final String roomId;

  @override
  State<PlaySmokeView> createState() => _PlaySmokeViewState();
}

class _PlaySmokeViewState extends State<PlaySmokeView> {
  WebVideoPlayerAdapter? _player;
  DanmakuChannel? _danmaku;
  final List<StreamSubscription<void>> _subs = [];

  String _phase = 'loading';
  String _error = '';
  String _info = '';
  int _danmakuCount = 0;

  late final String site;
  late final String roomId;

  @override
  void initState() {
    super.initState();
    final parsed = _parseRoute();
    site = widget.site.isNotEmpty
        ? widget.site
        : (Get.parameters['site'] ?? parsed[1] ?? '');
    roomId = widget.roomId.isNotEmpty
        ? widget.roomId
        : (Get.parameters['roomId'] ?? parsed[2] ?? '');
    _syncSmoke();
    _boot();
  }

  /// 从当前路由手工解析 `/{site}/play/{roomId}`（穿段深链兜底）。
  List<String?> _parseRoute() {
    final m = RegExp(r'^/([^/]+)/play/(.+)$').firstMatch(Get.currentRoute);
    if (m == null) return const [null, null];
    return [Uri.decodeComponent(m[1] ?? ''), Uri.decodeComponent(m[2] ?? '')];
  }

  Future<void> _boot() async {
    if (site.isEmpty || roomId.isEmpty) {
      return _fail('路由参数缺失（site="$site" roomId="$roomId"）');
    }
    final client = Get.find<StreamApiClient>();
    final base = client.config.baseUrl;

    final player = WebVideoPlayerAdapter(resolveStreamApiBaseUrl: () => base);
    _player = player;
    _subs.addAll([
      player.onStateChanged.listen((s) {
        if (s == PlayerState.playing) _setPhase('playing');
      }),
      player.onError.listen((e) => _fail('player: ${e.message}')),
    ]);

    try {
      await player.init();
      _setPhase('room');

      final payload = await client.fetchRoom(
        site: site,
        room: roomId,
        mode: 'lazy',
      );
      if (!payload.ok) {
        return _fail(
          'server: ${payload.error.isEmpty ? '房间解析失败' : payload.error}',
        );
      }
      if (!payload.isLive) {
        return _fail('房间未在播（room_state=${payload.roomState.name}）');
      }

      // 挑首选档第一条可播线路（flv 优先 —— douyu 主链路）。
      final names = payload.qualityNames;
      var stream = names.isNotEmpty ? payload.streamByName(names.first) : null;
      stream ??= payload.streams.isNotEmpty ? payload.streams.first : null;
      final line = pickLines(stream, preferHls: false).firstOrNull;
      if (line == null || line.url.isEmpty) {
        return _fail('无可用播放线路');
      }

      final backups = [
        ...payload.backupUrls,
        for (final l in stream!.lines)
          if (l.url != line.url) l.url,
      ];
      final playSite = payload.site.isNotEmpty ? payload.site : site;
      final playRoomId = payload.roomId.isNotEmpty ? payload.roomId : roomId;
      _setInfo(
        '${payload.title} · ${payload.anchorName} · ${stream.name}/${line.name}',
      );

      _setPhase('opening');
      await player.setDataSource(
        line.url,
        backups,
        line.headers,
        site: playSite,
        roomId: playRoomId,
      );
      if (player.state == PlayerState.error) return; // onError 已记录
      await player.play();
      _setPhase('ready'); // → playing 由 onPlaying 事件推进

      await _connectDanmaku(client, base, playRoomId);
    } catch (e) {
      _fail('boot: $e');
    }
  }

  Future<void> _connectDanmaku(
    StreamApiClient client,
    String base,
    String playRoomId,
  ) async {
    final resolver = const DanmakuChannelResolver();
    try {
      final cfg = await client.playbackConfig();
      _danmaku = resolver.resolve(
        site,
        playbackConfig: cfg is Map<String, dynamic> ? cfg : null,
        streamApiBaseUrl: base,
      );
    } catch (_) {
      // 服务端配置缺失/未配置 base：按默认矩阵（douyu → WS，其余 → SSE）。
      _danmaku = resolver.resolve(site, streamApiBaseUrl: base);
    }
    _subs.addAll([
      _danmaku!.messages.listen((_) {
        _danmakuCount++;
        _syncSmoke();
      }),
      _danmaku!.states.listen((s) => print('[smoke] danmaku state: ${s.name}')),
    ]);
    await _danmaku!.connect(roomId: playRoomId);
  }

  // ---- 状态与冒烟上报 -------------------------------------------------------

  void _setPhase(String phase) {
    if (!mounted) return;
    setState(() => _phase = phase);
    _syncSmoke();
  }

  void _setInfo(String info) {
    if (!mounted) return;
    setState(() => _info = info);
    _syncSmoke();
  }

  void _fail(String message) {
    print('[smoke] ERROR: $message');
    if (!mounted) return;
    setState(() {
      _phase = 'error';
      _error = message;
    });
    _syncSmoke();
  }

  /// 写 `window.zishuSmoke` 供 playwright 断言；同时 print 到 console。
  void _syncSmoke() {
    print('[smoke] phase=$_phase error=$_error danmaku=$_danmakuCount $_info');
    if (!kIsWeb) return;
    try {
      _zishuSmoke = <String, Object?>{
        'phase': _phase,
        'error': _error,
        'danmaku': _danmakuCount,
        'site': site,
        'roomId': roomId,
        'info': _info,
      }.jsify();
    } catch (_) {
      /* 冒烟上报失败不影响播放 */
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _danmaku?.disconnect();
    _player?.hardDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('直播间 $site/$roomId')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child:
                  _player?.getVideoWidget(BoxFit.contain) ??
                  const SizedBox.shrink(),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context).colorScheme.surface,
            child: Text(
              'phase=$_phase  弹幕=$_danmakuCount  $_info'
              '${_error.isEmpty ? '' : '  error=$_error'}',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
