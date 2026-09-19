import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 沉浸态右缘侧抽屉,对齐 SFVideoLive web `PlayImmersiveSideSheet.vue`。
///
/// web 真源结构(挂在 #play-frame 内的绝对定位层):
/// - 透明遮罩铺满舞台,点击关闭(`onBackdropClick`);
/// - 右缘 drawer = 左侧 toggle 把手(1.15rem × 40px,左圆角 4px,
///   chevron-right,点击收起)+ 右侧 panel(与播放侧栏同宽,全高,
///   左边框 + 左投影 `-6px 0 28px rgba(0,0,0,.55)`);
/// - 出入动效:遮罩 opacity + drawer `translateX(100%)`,
///   250ms `--fluent-easing`(token [AppMotion.normal]/[AppMotion.curve]);
/// - 关闭后不拦截命中(Vue v-show → display:none)。
///
/// 打开/关闭状态由调用方(播放页)持有;面板内容(交互即重置自动收起计时)
/// 经 [onInteract] 上报;[child] 通常为 [PlaySidePanel],与常规侧栏同一组件。
class PlayImmersiveSideSheet extends StatelessWidget {
  const PlayImmersiveSideSheet({
    super.key = const Key('play-immersive-sheet'),
    required this.open,
    required this.panelWidth,
    required this.onClose,
    required this.onInteract,
    required this.child,
  });

  /// toggle 把手宽度:web `--drawer-toggle-width: 1.15rem` ≈ 18.4px
  /// (styles/main.css:47 覆盖了组件内 0.82rem 兜底值)。
  static const double _toggleWidth = 18.4;

  /// toggle 把手高度:web `--drawer-toggle-height: 40px`。
  static const double _toggleHeight = 40;

  final bool open;

  /// 面板宽度(调用方按视口分档传入,对齐 `--immersive-panel-width`)。
  final double panelWidth;

  /// 点击遮罩 / toggle 把手 → 收起。
  final VoidCallback onClose;

  /// 面板内指针/滚动交互(重置自动收起计时,web `@interact`)。
  final VoidCallback onInteract;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Positioned.fill(
      // 关闭后不拦截舞台点击(对齐 v-show display:none);动画期间即阻断。
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          opacity: open ? 1 : 0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 透明遮罩:抽屉开着时点击舞台空白区 = 关闭(web onBackdropClick)。
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: const SizedBox.expand(),
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSlide(
                  duration: AppMotion.normal,
                  curve: AppMotion.curve,
                  // 关闭时整体平移自身宽度,完全滑出右缘(web translateX(100%))。
                  offset: open ? Offset.zero : const Offset(1, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // toggle 把手(面板左缘中央,web __toggle)。
                      // Material 透明壳只为 InkWell 提供水波纹宿主;
                      // 底色/三边框/左圆角由 Container 承担(web 右边框 none,
                      // 避免与面板左边框贴成双线)。
                      Material(
                        color: Colors.transparent,
                        child: Container(
                          key: const Key('play-immersive-toggle'),
                          width: _toggleWidth,
                          height: _toggleHeight,
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            border: Border(
                              left: BorderSide(color: tokens.border),
                              top: BorderSide(color: tokens.border),
                              bottom: BorderSide(color: tokens.border),
                            ),
                            borderRadius: const BorderRadius.horizontal(
                              // web `--drawer-toggle-radius` =
                              // `--el-border-radius-base`(4px,非 8 兜底)。
                              left: Radius.circular(AppRadius.sm),
                            ),
                          ),
                          child: InkWell(
                            onTap: onClose,
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 13,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      // 面板:全高、左边框 + 左投影(web __panel)。
                      Container(
                        key: const Key('play-immersive-panel'),
                        width: panelWidth,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          border: Border(
                            left: BorderSide(color: tokens.border),
                          ),
                          boxShadow: [
                            BoxShadow(
                              // web: -6px 0 28px rgba(0,0,0,.55)。
                              color: Colors.black.withValues(alpha: 0.55),
                              offset: const Offset(-6, 0),
                              blurRadius: 28,
                            ),
                          ],
                        ),
                        // 指针按下/移动/滚轮 + 滚动:重置自动收起计时。
                        child: Listener(
                          onPointerDown: (_) => onInteract(),
                          onPointerHover: (_) => onInteract(),
                          onPointerMove: (_) => onInteract(),
                          onPointerSignal: (_) => onInteract(),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              onInteract();
                              return false;
                            },
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
