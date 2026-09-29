/// 平台凭证弹框:顶栏账号菜单「平台凭证」入口弹出的对话框。
///
/// 为什么是弹框:凭证是低频配置项,不值得占一个路由页面;web 的 `/user`
/// 本就只是弹框,桌面端对齐(原独立页面已收编,`/user` 深链重定向 /all)。
/// 存在原因:部分站点必须带登录态才能解析/取流(YouTube 出口 IP 被反爬
/// 拦截、小红书需要 `a1` + `web_session`),而顶栏头像菜单只放得下账号登录。
/// 参考实现把这类入口做成各站点的 Cookie 弹窗
/// (`components/{youtube,xhs,douyin}/*CookieBanner.vue`),桌面端收敛到本弹框
/// 统一管理(同一套 token 存储,后续解析侧消费)。
///
/// 凭证只落本机 SharedPreferences,UI 只回显**脱敏摘要**,不整串展示。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/platform_icon.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/platform_credentials_provider.dart';
import '../domain/platform_credential.dart';

/// 顶栏账号菜单「平台凭证」入口:弹出凭证管理对话框。
Future<void> showUserCredentialsDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const UserCredentialsDialog(),
    );

/// 平台凭证对话框:平台条目渲染、粘贴 + 保存 / 清除。
class UserCredentialsDialog extends ConsumerWidget {
  const UserCredentialsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return AlertDialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
      title: Text(
        '平台凭证',
        key: const Key('user-credentials-dialog'),
        style: context.textTitle.copyWith(
          fontSize: AppFontSize.subtitle,
          fontWeight: FontWeight.w600,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      content: SizedBox(
        width: 640,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    '保存后仅显示脱敏摘要。',
                    style: context.textCaption.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                _Group(
                  title: '平台登录态',
                  children: [
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
      ),
      actions: [
        TextButton(
          key: const Key('user-credentials-close'),
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: tokens.textSecondary,
            minimumSize: const Size(0, 30),
          ),
          child: const Text('关闭'),
        ),
      ],
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

  /// 小红书键名模板:`a1` 与 `web_session` 两个键缺一不可,展开未配置时
  /// 预填,用户往等号后补值即可(对齐参考实现 a1/web_session 双输入框)。
  static const String _kXhsTemplate = 'a1=; web_session=';

  /// 小红书获取方法(常驻 helperText:模板预填后 hint 不可见,方法说明
  /// 必须仍可见;报错时被 errorText 顶替,可接受)。
  static const String _kXhsHelperText =
      '获取:浏览器登录 www.xiaohongshu.com → F12 → 网络 → 任选请求'
      '复制整串 Cookie(含 a1 与 web_session);约 7 天过期需重新导出';

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
        // 展开时回显当前值(便于局部修改);未配置且平台有多段键时预填
        // 键名模板,用户往等号后补值。
        _controller.text = credential.isConfigured
            ? credential.value
            : _templateFor(widget.brand.id);
        _prefilled = true;
      }
    });
  }

  /// 未配置时的输入框预填模板;空串 = 不预填。
  static String _templateFor(String site) =>
      site == 'xhs' ? _kXhsTemplate : '';

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
    // xhs 专项校验:签名与登录态都吃 `a1` + `web_session` 两个键的**非空值**;
    // 整串 Cookie 或只填模板两个键都放行(与参考实现 signing.ts 口径一致)。
    // 不能用 contains('a1=') 判定 —— 会把未填值的模板 `a1=; web_session=` 放行。
    if (widget.brand.id == 'xhs') {
      String? valueOf(String key) =>
          RegExp('$key=\\s*([^\\s;]+)').firstMatch(text)?.group(1);
      final a1 = valueOf('a1');
      final webSession = valueOf('web_session');
      if (a1 == null ||
          a1.isEmpty ||
          webSession == null ||
          webSession.isEmpty) {
        setState(() => _error = '小红书 Cookie 需同时包含 a1 与 web_session 的值');
        return;
      }
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
      _controller.text = _templateFor(widget.brand.id);
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
                  // xhs 的获取方法走常驻 helperText:模板预填进输入框后
                  // hint 不可见,方法说明必须仍可见(报错时被 error 顶替)。
                  helperText: site == 'xhs' ? _kXhsHelperText : null,
                  helperMaxLines: 3,
                  helperStyle: context.textCaption.copyWith(
                    color: tokens.textSecondary,
                  ),
                  hintMaxLines: 3,
                  hintStyle: context.textCaption.copyWith(
                    color: tokens.textSecondary,
                  ),
                  filled: true,
                  fillColor: tokens.surfaceRaised,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.allSm,
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  // 键盘焦点可见:描边转 accent(与搜索页输入框同法,不新增色值)。
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.allSm,
                    borderSide: BorderSide(color: tokens.accent),
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
  ///
  /// xhs 只提示填法 —— 获取方法在常驻 helperText([_kXhsHelperText]),
  /// 模板预填后 hint 不可见。
  static String _hintFor(String site) => switch (site) {
    'youtube' => '粘贴完整 Cookie 串(SID=...; HSID=...; ...)',
    'xhs' => '整串 Cookie,或保留模板只填等号后的值',
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
