part of '../app_shell.dart';

/// 顶栏主题切换按钮已移除(用户口径 2026-09-23:浅色/主题切换收进设置,
/// 设置入口改弹对话框) —— 主题模式在「设置 → 外观 → 主题模式」下拉中切换,
/// 移动底栏的 [_BottomThemeItem] 快捷入口保留。
///
/// 下面的判定/切换与底栏入口继续服务该能力:
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
