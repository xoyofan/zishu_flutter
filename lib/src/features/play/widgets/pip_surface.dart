/// 画中画小窗的桌面包壳(播放页共享 UI,不含平台依赖)。
///
/// 真正的原生窗口交互(Windows 下窗口边缘的拖拽/缩放热区)由播放器实现提供
/// (见 [LivePlayer.wrapPipSurface]):那笔实现直接 import window_manager,
/// 传递性引入 `dart:io`,只能落在 platforms 实现层。本组件位于播放页共享
/// 依赖图,把请求转交给当前播放器,让 play_view 不 import 任何窗口库。
///
/// 单测里播放器替身用接口默认实现(直接透传),故 PiP 用例不会触碰原生。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platforms/common/playback/live_player.dart' show LivePlayer;
import '../application/play_provider.dart' show playerProvider;

class PipResizeSurface extends ConsumerWidget {
  const PipResizeSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LivePlayer player = ref.watch(playerProvider);
    return player.wrapPipSurface(child);
  }
}
