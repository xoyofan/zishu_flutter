import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../platforms/web/streaming_server_client.dart';

class WindowsApp extends StatelessWidget {
  const WindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '紫薯直播',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF09090B),
        useMaterial3: true,
      ),
      home: const DouyuPlayerPage(),
    );
  }
}

/// 新 Windows UI 的第一张验证页：streaming-server 解析 + media-kit 播放。
///
/// Windows/Android 后续接入纯 Dart parser 时，只替换解析 adapter；页面与播放器不变。
class DouyuPlayerPage extends StatefulWidget {
  const DouyuPlayerPage({super.key});

  @override
  State<DouyuPlayerPage> createState() => _DouyuPlayerPageState();
}

class _DouyuPlayerPageState extends State<DouyuPlayerPage> {
  static const _fallbackRoomId = '24422';

  late final Player _player;
  late final VideoController _videoController;
  late final StreamingServerClient _resolver;
  late final TextEditingController _roomController;
  StreamSubscription<String>? _errorSubscription;

  String _status = '准备加载斗鱼直播间';
  String _title = '斗鱼播放验证';
  String _anchor = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _resolver = StreamingServerClient();
    _roomController = TextEditingController(text: _fallbackRoomId);
    _errorSubscription = _player.stream.error.listen((error) {
      if (!mounted || error.isEmpty) return;
      setState(() => _status = '播放错误：$error');
    });
    unawaited(_loadRecommendedRoom());
  }

  Future<void> _loadRecommendedRoom() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _status = '正在寻找当前在播的斗鱼房间…';
    });
    try {
      final room = await _resolver.resolveRecommendedLiveRoom();
      _roomController.text = room.roomId;
      await _playResolvedRoom(room);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '自动选房失败，正在尝试 $_fallbackRoomId：$error');
      _roomController.text = _fallbackRoomId;
      await _resolveAndPlay(_fallbackRoomId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRoom() async {
    final roomId = _roomController.text.trim();
    if (roomId.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _status = '正在解析斗鱼房间 $roomId…';
    });
    try {
      await _resolveAndPlay(roomId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '加载失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveAndPlay(String roomId) async {
    final room = await _resolver.resolveRoom(site: 'douyu', roomId: roomId);
    if (!room.ok) throw StateError(room.error.isEmpty ? '解析失败' : room.error);
    if (!room.isLive) throw StateError('当前房间未开播');
    if (room.playUrl.isEmpty) throw StateError('解析结果没有可播放地址');
    await _playResolvedRoom(room);
  }

  Future<void> _playResolvedRoom(ResolvedLiveRoom room) async {
    await _player.open(Media(room.playUrl), play: true);
    if (!mounted) return;
    setState(() {
      _title = room.title.isEmpty ? '斗鱼房间 ${room.roomId}' : room.title;
      _anchor = room.anchorName;
      _status = '房间 ${room.roomId} · media-kit 正在播放 HLS';
    });
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _roomController.dispose();
    _resolver.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _PlayerHeader(
              title: _title,
              anchor: _anchor,
              status: _status,
              loading: _loading,
              roomController: _roomController,
              onLoad: _loadRoom,
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Video(
                  controller: _videoController,
                  fit: BoxFit.contain,
                  controls: AdaptiveVideoControls,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.title,
    required this.anchor,
    required this.status,
    required this.loading,
    required this.roomController,
    required this.onLoad,
  });

  final String title;
  final String anchor;
  final String status;
  final bool loading;
  final TextEditingController roomController;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Icon(Icons.live_tv_rounded, color: Color(0xFFA78BFA), size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  [if (anchor.isNotEmpty) anchor, status].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 180,
            child: TextField(
              controller: roomController,
              enabled: !loading,
              onSubmitted: (_) => onLoad(),
              decoration: const InputDecoration(
                labelText: '斗鱼房间号',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: loading ? null : onLoad,
            icon: loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: const Text('播放'),
          ),
        ],
      ),
    );
  }
}
