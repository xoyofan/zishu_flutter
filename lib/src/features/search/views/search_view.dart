import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/search_provider.dart';
import '../widgets/search_direct_tile.dart';
import '../widgets/search_platform_chips.dart';
import '../widgets/search_result_tile.dart';

/// 搜索页:顶部搜索框(autofocus)+ 平台 chips + 快捷直达 + 命中列表。
/// 键盘:Enter 执行(直达优先,否则进入首个结果),Esc 返回上一页。
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // provider 为 keep-alive:再次进入搜索页回填上一次输入。
    _input.text = ref.read(searchProvider).query;
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Enter:直达项优先,其次进入首个命中结果。
  void _submit() {
    final search = ref.read(searchProvider);
    if (search.direct != null) {
      _openDirect(search.direct!);
      return;
    }
    if (search.hits.isNotEmpty) {
      _openRoom(search.hits.first);
    }
  }

  /// 打开直达项:链接直达固定 douyu;房间号直达跟随当前所选平台。
  void _openDirect(DirectTarget target) {
    final site = target.kind == DirectKind.link
        ? 'douyu'
        : ref.read(searchProvider).site;
    _inputFocus.unfocus();
    context.push('/$site/play/${target.roomId}');
  }

  /// 进入直播间:仅直播中可进,未开播给出提示。
  void _openRoom(SearchHit hit) {
    if (hit.state != SearchHitState.live) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('「${hit.anchor}」当前未开播')));
      return;
    }
    _inputFocus.unfocus();
    final site = ref.read(searchProvider.notifier).siteOf(hit);
    context.push('/$site/play/${hit.id}');
  }

  /// 头像/昵称进入主播主页。
  void _openAnchor(SearchHit hit) {
    _inputFocus.unfocus();
    final site = ref.read(searchProvider.notifier).siteOf(hit);
    context.push('/$site/anchor/${hit.id}');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final search = ref.watch(searchProvider);
    return CallbackShortcuts(
      bindings: {
        // Esc 关闭搜索,返回上一页。
        const SingleActivator(LogicalKeyboardKey.escape): () => context.pop(),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: _buildSearchField(tokens, search),
          ),
          const SearchPlatformChips(),
          Expanded(child: _buildResults(tokens, search)),
        ],
      ),
    );
  }

  Widget _buildSearchField(ZishuTokens tokens, SearchState search) {
    return TextField(
      // 测试锚点:定位/输入搜索关键词。
      key: const Key('search-input'),
      controller: _input,
      focusNode: _inputFocus,
      autofocus: true,
      onChanged: ref.read(searchProvider.notifier).setQuery,
      onSubmitted: (_) => _submit(),
      cursorColor: tokens.brand,
      style: AppTypography.body.copyWith(color: tokens.textPrimary),
      decoration: InputDecoration(
        hintText: '搜索主播 / 房间号 / 直播间链接',
        hintStyle: AppTypography.body.copyWith(color: tokens.textSecondary),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: tokens.textSecondary),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _EscHint(),
            if (search.query.isNotEmpty)
              IconButton(
                tooltip: '清空',
                icon: Icon(Icons.close_rounded, size: 18, color: tokens.textSecondary),
                onPressed: () {
                  _input.clear();
                  ref.read(searchProvider.notifier).setQuery('');
                  _inputFocus.requestFocus();
                },
              ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        isDense: true,
        filled: true,
        fillColor: tokens.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: BorderSide(color: tokens.brand),
        ),
      ),
    );
  }

  Widget _buildResults(ZishuTokens tokens, SearchState search) {
    // 未输入:引导空态。
    if (!search.hasQuery) {
      return _EmptyHint(
        icon: Icons.manage_search_rounded,
        title: '搜索主播 / 房间号 / 直播间链接',
        subtitle: '支持纯数字房间号直达,或粘贴 douyu.com 直播间链接',
      );
    }
    final direct = search.direct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (search.searching)
          LinearProgressIndicator(
            minHeight: 2,
            color: tokens.brand,
            backgroundColor: tokens.surfaceRaised,
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (direct != null) ...[
                SearchDirectTile(target: direct, onTap: () => _openDirect(direct)),
                const SizedBox(height: AppSpacing.md),
              ],
              if (search.searching && search.hits.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(
                    child: Text(
                      '搜索中…',
                      style: AppTypography.bodySecondary.copyWith(color: tokens.textSecondary),
                    ),
                  ),
                ),
              for (final (index, hit) in search.hits.indexed)
                SearchResultTile(
                  // 测试锚点:定位第 index 条搜索结果行。
                  key: Key('search-result-$index'),
                  hit: hit,
                  onRowTap: () => _openRoom(hit),
                  onAnchorTap: () => _openAnchor(hit),
                ),
              if (!search.searching && direct == null && search.hits.isEmpty)
                _EmptyHint(
                  icon: Icons.search_off_rounded,
                  title: '未找到与「${search.query.trim()}」相关的主播或房间',
                  subtitle: '换个关键词,或试试房间号 / 直播间链接',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 搜索框尾部「Esc 返回」说明徽标。
class _EscHint extends StatelessWidget {
  const _EscHint();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: AppRadius.allSm,
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        'Esc 返回',
        style: AppTypography.caption.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// 空态提示(未输入引导 / 无结果)。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: tokens.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: AppTypography.body.copyWith(color: tokens.textSecondary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: AppTypography.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
