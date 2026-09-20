part of '../app_shell.dart';

/// 顶栏主题切换:在深色 ⇄ 浅色之间切换(写 `settingsProvider.setThemeMode`)。
///
/// 按钮文案与图标表示「点击后要切到的目标」:当前生效为深色 → 显示「浅色」+
/// [Icons.light_mode_outlined](与 web `NavSidebar.vue` 的 `themeMode === 'dark'
/// ? '浅色' : '深色'` 一致)。判定/切换本身由 [_isDarkTheme] / [_toggleTheme]
/// 单一实现提供,移动底栏的「主题」项复用同一份。
class _NavThemeAction extends ConsumerWidget {
  const _NavThemeAction({required this.showLabel});

  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = _isDarkTheme(context, ref);
    return _NavAction(
      key: const Key('nav-theme'),
      icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      label: isDark ? '浅色' : '深色',
      tooltip: '切换主题',
      showLabel: showLabel,
      onTap: (_) => _toggleTheme(context, ref),
    );
  }
}

/// 当前**生效**主题是否为深色。
///
/// 显式 dark/light 直接取设置值;system 按平台亮度解析 —— 与 MaterialApp 的
/// `themeMode` 解析口径一致,保证按钮文案与真实观感不拧。
bool _isDarkTheme(BuildContext context, WidgetRef ref) {
  return switch (ref.watch(settingsProvider).themeMode) {
    ThemeModeChoice.dark => true,
    ThemeModeChoice.light => false,
    ThemeModeChoice.system =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark,
  };
}

/// 深色 ⇄ 浅色 切换(顶栏与移动底栏共用,避免两处各写一份漂移)。
void _toggleTheme(BuildContext context, WidgetRef ref) {
  ref
      .read(settingsProvider.notifier)
      .setThemeMode(
        _isDarkTheme(context, ref)
            ? ThemeModeChoice.light
            : ThemeModeChoice.dark,
      );
}

/// 移动底栏「主题」项:与顶栏 `nav-theme` 同一份判定与切换逻辑。
///
/// 文案同样表示「点击后要切到的目标」,与顶栏保持一致(旧实现是 `onTap: () {}`
/// 的空按钮 —— 移动端主题切换一直没接上)。
class _BottomThemeItem extends ConsumerWidget {
  const _BottomThemeItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = _isDarkTheme(context, ref);
    return _BottomItem(
      key: const Key('nav-theme'),
      leading: _bottomIcon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        false,
        context.tokens,
      ),
      label: isDark ? '浅色' : '深色',
      onTap: () => _toggleTheme(context, ref),
      active: false,
    );
  }
}
