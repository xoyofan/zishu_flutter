part of '../app_shell.dart';

/// 顶栏右侧账号区:对齐 SFVideoLive `NavSidebar.vue` 登录态的头像 + 用户名。
///
/// 登录态由 [authProvider] 驱动(data-server 账号 + JWT):
/// - restoring:头像占位 + 「…」,交互禁用;
/// - authenticated:头像 + 用户名,点击弹账号菜单(退出登录);
/// - anonymous:头像 + 「登录」,点击弹登录框。
/// 手动登录成功后的关注云同步由 FollowController 的登录监听自动触发。
/// 保留 `nav-user` 锚点;`showLabels` 时附带头像旁文案。
class _UserAvatar extends ConsumerWidget {
  const _UserAvatar({required this.showLabels});

  final bool showLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    // 登录态跃迁(手动登录/启动链完成)→ 拉取云端关注。
    // pullRemote 幂等且防重入;登录早于本页构建时由 FollowController
    // _restore 尾部直接拉取,此处只补「登录在后」的时序。
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.phase == AuthPhase.authenticated &&
          prev?.phase != AuthPhase.authenticated) {
        ref.read(followProvider.notifier).pullRemote();
      }
    });
    final authenticated = auth.phase == AuthPhase.authenticated;
    final restoring = auth.phase == AuthPhase.restoring;
    final label = restoring
        ? '…'
        : authenticated
        ? (auth.session?.username ?? '已登录')
        : '登录';

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: context.tokens.accent,
            child: Icon(
              Icons.person_outline_rounded,
              size: 16,
              color: AppOnBright.white,
            ),
          ),
          if (showLabels) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.bodySecondary,
                fontWeight: FontWeight.w500,
                color: authenticated
                    ? context.tokens.textPrimary
                    : context.tokens.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );

    if (restoring) {
      return Tooltip(message: '账号状态恢复中', child: row);
    }
    if (authenticated) {
      return PopupMenuButton<String>(
        key: const Key('nav-user'),
        tooltip: '账号',
        offset: const Offset(0, 30),
        color: context.tokens.surface,
        onSelected: (action) {
          if (action == 'logout') {
            ref.read(authProvider.notifier).logout();
            return;
          }
          if (action == 'credentials') {
            // 用户/平台凭证页:保存 YouTube / 小红书 等平台的登录态。
            // 用 push(不重置历史栈):凭证页返回后仍能回到原页面。
            context.push('/user');
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'credentials',
            height: 34,
            child: Row(
              children: [
                Icon(
                  Icons.key_outlined,
                  size: 15,
                  color: context.tokens.textSecondary,
                ),
                SizedBox(width: 8),
                Text(
                  '平台凭证',
                  style: TextStyle(
                    fontSize: AppFontSize.bodySecondary,
                    color: context.tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'logout',
            height: 34,
            child: Row(
              children: [
                Icon(
                  Icons.logout_rounded,
                  size: 15,
                  color: context.tokens.error,
                ),
                SizedBox(width: 8),
                Text(
                  '退出登录',
                  style: TextStyle(
                    fontSize: AppFontSize.bodySecondary,
                    color: context.tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: row,
      );
    }
    return Tooltip(
      message: '登录',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('nav-user'),
          borderRadius: AppRadius.allPill,
          hoverColor: context.tokens.surfaceSoft,
          focusColor: context.tokens.surfaceRaised,
          splashColor: _pressTint(context),
          highlightColor: _pressTint(context),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const LoginDialog(),
          ),
          child: row,
        ),
      ),
    );
  }
}

/// data-server 登录对话框:用户名/密码 + 记住密码(默认勾选)。
/// 用户名预填默认账号;成功后关闭,关注云同步由 FollowController 监听登录态触发。
class LoginDialog extends ConsumerStatefulWidget {
  const LoginDialog({super.key});

  @override
  ConsumerState<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends ConsumerState<LoginDialog> {
  final TextEditingController _userController = TextEditingController(
    text: kDefaultAuthUsername,
  );
  final TextEditingController _passController = TextEditingController();
  bool _remember = true;
  bool _busy = false;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = _userController.text.trim();
    final pass = _passController.text;
    if (user.isEmpty || pass.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(authProvider.notifier)
        .login(user, pass, remember: _remember);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastError = ref.watch(authProvider).lastError;
    return AlertDialog(
      backgroundColor: context.tokens.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
      title: Text(
        '登录账号',
        style: TextStyle(
          fontSize: AppFontSize.subtitle,
          fontWeight: FontWeight.w600,
          color: context.tokens.textPrimary,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _userController,
              style: TextStyle(
                fontSize: AppFontSize.body,
                color: context.tokens.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                labelText: '用户名',
                labelStyle: TextStyle(
                  fontSize: AppFontSize.bodySecondary,
                  color: context.tokens.textSecondary,
                ),
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                border: OutlineInputBorder(borderRadius: AppRadius.allMd),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passController,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontSize: AppFontSize.body,
                color: context.tokens.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                labelText: '密码',
                labelStyle: TextStyle(
                  fontSize: AppFontSize.bodySecondary,
                  color: context.tokens.textSecondary,
                ),
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                border: OutlineInputBorder(borderRadius: AppRadius.allMd),
              ),
            ),
            SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Checkbox(
                      value: _remember,
                      visualDensity: VisualDensity.compact,
                      activeColor: context.tokens.accent,
                      onChanged: (v) => setState(() => _remember = v ?? true),
                    ),
                  ),
                  Text(
                    '记住密码(下次打开自动登录)',
                    style: TextStyle(
                      fontSize: AppFontSize.bodySecondary,
                      color: context.tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (lastError != null)
              Padding(
                padding: EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  lastError,
                  style: TextStyle(
                    fontSize: AppFontSize.bodySecondary,
                    color: context.tokens.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(
              fontSize: AppFontSize.bodySecondary,
              color: context.tokens.textSecondary,
            ),
          ),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.tokens.accent,
            foregroundColor: AppOnBright.white,
            textStyle: const TextStyle(fontSize: AppFontSize.bodySecondary),
          ),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
        ),
      ],
    );
  }
}
