/// 「用户」页:账号状态 + 平台登录态凭证(YouTube / 小红书等)。
///
/// 为什么需要它:部分站点必须带登录态才能解析/取流(YouTube 出口 IP 被反爬
/// 拦截、小红书需要 `a1` + `web_session`),而顶栏头像菜单只放得下账号登录。
/// 参考实现把这类入口做成各站点的 Cookie 弹窗
/// (`components/{youtube,xhs,douyin}/*CookieBanner.vue`),桌面端收敛到本页
/// 统一管理(同一套 token 存储,后续解析侧消费)。
///
/// 凭证只落本机 SharedPreferences,UI 只回显**脱敏摘要**,不整串展示。
/// 路由(`/user`)与顶栏入口由壳层接线 —— 本页不自带 Scaffold,依赖 AppShell。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/application/auth_provider.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/platform_icon.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/platform_credentials_provider.dart';
import '../domain/platform_credential.dart';

class UserCredentialsView extends ConsumerWidget {
  const UserCredentialsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return SingleChildScrollView(
      key: const Key('user-credentials-view'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('用户', style: context.textTitle.copyWith(fontSize: 18)),
              const SizedBox(height: AppSpacing.lg),
              const _Group(title: '账号', children: [_AccountRow()]),
              _Group(
                title: '平台登录态',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      '凭证仅存本机,用于解析需要登录态的站点;'
                      '输入框只在本页可见,保存后仅显示脱敏摘要。',
                      style: context.textCaption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  for (final brand in credentialSiteBrands())
                    _SiteCredentialTile(
                      key: Key('user-credential-${brand.id}'),
                      brand: brand,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 账号行:恢复中 / 已登录(用户名 + 退出) / 匿名(提示去顶栏登录)。
class _AccountRow extends ConsumerWidget {
  const _AccountRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final auth = ref.watch(authProvider);
    final username = auth.session?.username.trim().isNotEmpty == true
        ? auth.session!.username.trim()
        : '';
    final authenticated = auth.phase == AuthPhase.authenticated;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_outline_rounded,
            size: 18,
            color: tokens.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              switch (auth.phase) {
                AuthPhase.restoring => '登录状态恢复中…',
                AuthPhase.authenticated => username.isEmpty ? '已登录' : username,
                AuthPhase.anonymous => '未登录 · 点顶栏头像可登录',
              },
              key: const Key('user-account-username'),
              style: context.textBody,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (authenticated)
            TextButton(
              key: const Key('user-account-logout'),
              onPressed: () => ref.read(authProvider.notifier).logout(),
              style: TextButton.styleFrom(foregroundColor: tokens.error),
              child: const Text('退出登录'),
            ),
        ],
      ),
    );
  }
}

/// 单个平台的凭证条目:折叠态看状态,展开后粘贴 + 保存 / 清除。
class _SiteCredentialTile extends ConsumerStatefulWidget {
  const _SiteCredentialTile({super.key, required this.brand});

  final PlatformBrand brand;

  @override
  ConsumerState<_SiteCredentialTile> createState() =>
      _SiteCredentialTileState();
}

class _SiteCredentialTileState extends ConsumerState<_SiteCredentialTile> {
  final TextEditingController _controller = TextEditingController();

  /// 折叠态只显示状态与脱敏摘要;展开态才出输入框。
  bool _expanded = false;

  /// 输入校验提示(空串 = 无提示)。
  String _error = '';

  /// 是否已把存储里的当前值灌进输入框(展开时做一次,避免覆盖用户编辑)。
  bool _prefilled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle(PlatformCredential credential) {
    setState(() {
      _expanded = !_expanded;
      _error = '';
      if (_expanded && !_prefilled) {
        // 展开时回显当前值(便于局部修改;凭据只在本机与本页内存里)。
        _controller.text = credential.value;
        _prefilled = true;
      }
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请先粘贴 Cookie 或 Token');
      return;
    }
    if (text.length < 8) {
      setState(() => _error = '内容过短,请粘贴完整的 Cookie 串');
      return;
    }
    setState(() => _error = '');
    final ok = await ref
        .read(platformCredentialsProvider.notifier)
        .setCredential(widget.brand.id, text);
    if (!mounted) return;
    _toast(ok ? '已保存到本机' : '保存失败,请重试');
  }

  Future<void> _clear() async {
    await ref
        .read(platformCredentialsProvider.notifier)
        .clearCredential(widget.brand.id);
    if (!mounted) return;
    setState(() {
      _controller.clear();
      _error = '';
    });
    _toast('已清除该平台凭证');
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final site = widget.brand.id;
    final credential = ref.watch(
      platformCredentialsProvider.select((state) => state.credentialFor(site)),
    );
    final parsingReady = isParsingImplemented(site);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: AppRadius.allMd,
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PlatformIcon(id: site, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.brand.name,
                        style: context.textBody.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        parsingReady ? '解析已接入' : '该平台解析尚未接入',
                        style: context.textCaption.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                  key: Key('user-credential-status-$site'),
                  configured: credential.isConfigured,
                ),
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  key: Key('user-credential-toggle-$site'),
                  onPressed: () => _toggle(credential),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.accent,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(_expanded ? '收起' : '配置'),
                ),
              ],
            ),
            if (credential.isConfigured && !_expanded)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '${credential.maskedPreview}'
                  '${_savedAtLabel(credential)}',
                  style: context.textCaption.copyWith(
                    color: tokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (_expanded) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: Key('user-credential-input-$site'),
                controller: _controller,
                minLines: 2,
                maxLines: 5,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                style: context.textBody,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _hintFor(site),
                  hintStyle: context.textCaption.copyWith(
                    color: tokens.textSecondary,
                  ),
                  filled: true,
                  fillColor: tokens.surfaceRaised,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.allSm,
                    borderSide: BorderSide(color: tokens.border),
                  ),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _error,
                    key: Key('user-credential-error-$site'),
                    style: context.textCaption.copyWith(color: tokens.error),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  FilledButton(
                    key: Key('user-credential-save-$site'),
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    key: Key('user-credential-clear-$site'),
                    onPressed: credential.isConfigured ? _clear : null,
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                      minimumSize: const Size(0, 30),
                    ),
                    child: const Text('清除'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 保存时间摘要(只到分钟;不引 intl,手写零填充)。
  static String _savedAtLabel(PlatformCredential credential) {
    final at = credential.updatedAt;
    if (at == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '  ·  ${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  /// 各站点的粘贴提示(对齐参考实现的 Cookie 弹窗说明)。
  static String _hintFor(String site) => switch (site) {
    'youtube' => '粘贴完整 Cookie 串(SID=...; HSID=...; ...)',
    'xhs' => '粘贴 a1 与 web_session(如 a1=...; web_session=...)',
    _ => '粘贴该平台的 Cookie 或 Token',
  };
}

/// 状态徽标:已配置 / 未配置。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({super.key, required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = configured ? tokens.success : tokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: AppRadius.allSm,
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        configured ? '已配置' : '未配置',
        style: context.textCaption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 分组容器:标题 + 卡片内容(与设置页同构,便于视觉一致)。
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              title,
              style: context.textBody.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.textSecondary,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: AppRadius.allLg,
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
