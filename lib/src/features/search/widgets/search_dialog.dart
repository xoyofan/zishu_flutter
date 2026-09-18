/// 全局搜索对话框:对齐 SFVideoLive `components/browse/SearchDialog.vue`。
///
/// 搜索在参考实现里**不是一个页面**,而是顶栏/底栏都能拉起的弹框(`openSearchDialog`
/// 见 `composables/useAppDialogs.ts`),`/search` 路由本身只做重定向。本文件复刻该形态:
/// 输入与结果都不离开当前页面,关框即回到原处。
///
/// 导航职责的划分是关键:对话框**只把目标 location 作为返回值上抛**,由
/// [openSearchDialog] 在关框之后导航 —— 若在框内直接 push,新页面会被弹框压在下面,
/// 且关框后原 context 可能已失效。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../views/search_view.dart';

/// 对话框宽度上限:对齐 web `width="min(92vw, 520px)"`。
const double _kDialogWidth = 520;

/// 高度上限:web 的结果区 `max-height: min(50vh, 420px)`,加上输入框/chips/内边距,
/// 这里给 640 的整体上限,小窗口下再按视口 82% 收敛。
const double _kDialogMaxHeight = 640;

/// 打开全局搜索对话框(顶栏 `nav-search` / 移动底栏 `nav-search` 共用入口)。
Future<void> openSearchDialog(BuildContext context) async {
  // 先取 router:对话框关闭后原 context 可能已 deactivate,不能再从它读路由。
  final router = GoRouter.of(context);
  // 发起页是不是播放页:决定命中另一个直播间时走替换还是入栈(见下)。
  final fromPlayPage = _isOnPlayPage(context);
  final location = await showDialog<String>(
    context: context,
    // 锚点:搜索对话框根(测试与人工定位用)。
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) => _SearchDialogFrame(
      onClose: () => Navigator.of(dialogContext).pop(),
      onNavigate: (target) => Navigator.of(dialogContext).pop(target),
    ),
  );
  if (location == null || location.isEmpty) return;
  // 播放页里搜到另一个直播间 = 切房:必须**替换**而不是入栈,否则旧播放页
  // 连同它的 media-kit 会话被压在栈下继续存活(与侧栏切房同一口径)。
  if (fromPlayPage && location.contains('/play/')) {
    router.pushReplacement(location);
    return;
  }
  router.push(location);
}

/// 当前页面是否播放页。
///
/// 没有路由宿主(裸 pump 的组件测试)时 `GoRouterState.of` 会抛错,一律按
/// 「非播放页」处理 —— 那时也只有 push 一条路可走。
bool _isOnPlayPage(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.path.contains('/play/');
  } catch (_) {
    return false;
  }
}

/// 对话框外框:标题栏(搜索 + 关闭)+ 搜索主体。
class _SearchDialogFrame extends StatelessWidget {
  const _SearchDialogFrame({required this.onClose, required this.onNavigate});

  final VoidCallback onClose;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(viewport.width * 0.92, _kDialogWidth);
    final height = math.min(viewport.height * 0.82, _kDialogMaxHeight);
    return Dialog(
      key: const Key('search-dialog'),
      backgroundColor: tokens.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    '搜索',
                    style: AppTypography.title.copyWith(
                      fontSize: 15,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('search-dialog-close'),
                    tooltip: '关闭',
                    onPressed: onClose,
                    iconSize: 18,
                    color: tokens.textSecondary,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SearchView(onNavigate: onNavigate, onClose: onClose),
            ),
          ],
        ),
      ),
    );
  }
}
