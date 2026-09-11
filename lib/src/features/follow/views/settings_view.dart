/// 设置页(U7):外观/播放/弹幕/服务器四组设置,surface 卡片分组。
/// 主题/画质/弹幕变更即持久化;服务器地址点「保存」后 SnackBar 反馈。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/settings_provider.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  late final TextEditingController _serverController;
  final FocusNode _serverFocus = FocusNode();

  /// 「按平台配置默认画质」展开态。默认折叠:折叠时不构建 11 组平台下拉,
  /// 避免设置页被撑爆,也让既有用例的 `find.byType(DropdownButton<String>)`
  /// 仍只命中「全平台默认画质」一个控件。
  bool _platformQualityExpanded = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: ref.read(settingsProvider).serverUrl,
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _serverFocus.dispose();
    super.dispose();
  }

  Future<void> _saveServerUrl() async {
    final url = _serverController.text.trim();
    if (url.isEmpty) {
      _toast('服务器地址不能为空');
      return;
    }
    _serverFocus.unfocus();
    await ref.read(settingsProvider.notifier).setServerUrl(url);
    if (!mounted) return;
    _toast('服务器地址已保存');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsProvider);

    // 持久化恢复完成(或他处修改)后回填输入框;正在编辑时不打断用户。
    ref.listen(settingsProvider.select((s) => s.serverUrl), (_, next) {
      if (!_serverFocus.hasFocus && _serverController.text != next) {
        _serverController.text = next;
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: AppTypography.title.copyWith(fontSize: 18)),
              const SizedBox(height: AppSpacing.lg),
              _SettingsGroup(
                title: '外观',
                children: [
                  _SettingsRow(
                    label: '主题模式',
                    hint: '当前阶段仅保存偏好,全局主题接线由后续任务完成',
                    trailing: _StyledDropdown<ThemeModeChoice>(
                      value: settings.themeMode,
                      items: [
                        for (final mode in ThemeModeChoice.values)
                          (value: mode, label: mode.label),
                      ],
                      onChanged: (mode) => ref
                          .read(settingsProvider.notifier)
                          .setThemeMode(mode),
                    ),
                  ),
                ],
              ),
              _SettingsGroup(
                title: '播放',
                children: [
                  _SettingsRow(
                    label: '全平台默认画质',
                    hint: '各平台未单独配置时使用的画质',
                    trailing: _StyledDropdown<String>(
                      value: settings.defaultQuality,
                      items: [
                        for (final quality in SettingsState.qualityOptions)
                          (value: quality, label: quality),
                      ],
                      onChanged: (quality) => ref
                          .read(settingsProvider.notifier)
                          .setDefaultQuality(quality),
                    ),
                  ),
                  _SettingsRow(
                    label: '按平台配置默认画质',
                    hint: _platformQualityExpanded ? '点此收起' : '为单个平台指定不同默认档',
                    trailing: IconButton(
                      key: const Key('settings-toggle-platform-quality'),
                      tooltip: _platformQualityExpanded
                          ? '收起平台画质配置'
                          : '展开平台画质配置',
                      onPressed: () => setState(
                        () => _platformQualityExpanded =
                            !_platformQualityExpanded,
                      ),
                      icon: Icon(
                        _platformQualityExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  // 折叠时不构建平台下拉:一是页面不至于被 11 行撑爆,二是让
                  // 既有用例的 `find.byType(DropdownButton<String>)` 仍只命中
                  // 「全平台默认画质」一个控件(见 settings_test)。
                  if (_platformQualityExpanded)
                    for (final brand in PlatformBrandCatalog.navPlatforms)
                      if (brand.id != 'all')
                        _SettingsRow(
                          label: brand.name,
                          hint: settings.defaultQualityBySite[brand.id] == null
                              ? '未单独配置,默认「${SettingsState.platformDefaultQuality[brand.id] ?? settings.defaultQuality}」'
                              : null,
                          trailing: _StyledDropdown<String>(
                            // 测试锚点:按平台寻址(settings-quality-{site})。
                            key: Key('settings-quality-${brand.id}'),
                            // 哨兵空串 = 「跟随全平台」;其余值为平台单独配置。
                            value:
                                settings.defaultQualityBySite[brand.id] ?? '',
                            items: [
                              const (value: '', label: '跟随平台默认'),
                              for (final quality
                                  in SettingsState.qualityOptionsForSite(
                                    brand.id,
                                  ))
                                (value: quality, label: quality),
                            ],
                            onChanged: (quality) => ref
                                .read(settingsProvider.notifier)
                                .setDefaultQualityForSite(
                                  brand.id,
                                  quality.isEmpty ? null : quality,
                                ),
                          ),
                        ),
                ],
              ),
              _SettingsGroup(
                title: '弹幕',
                children: [
                  _SettingsRow(
                    label: '弹幕显示',
                    hint: '播放时在画面上方叠加弹幕',
                    trailing: Switch(
                      value: settings.danmakuEnabled,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setDanmakuEnabled(value),
                    ),
                  ),
                ],
              ),
              _SettingsGroup(
                title: '服务器',
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'streaming-server 地址',
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Dart 解析服务的 HTTP/SSE 基础地址,Web 端经它访问解析 API',
                          style: AppTypography.bodySecondary,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _serverController,
                                focusNode: _serverFocus,
                                style: AppTypography.body,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'http://127.0.0.1:8787',
                                  hintStyle: AppTypography.bodySecondary,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  filled: true,
                                  fillColor: tokens.surfaceRaised,
                                  border: OutlineInputBorder(
                                    borderRadius: AppRadius.allSm,
                                    borderSide: BorderSide(
                                      color: tokens.border,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: AppRadius.allSm,
                                    borderSide: BorderSide(
                                      color: tokens.border,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: AppRadius.allSm,
                                    borderSide: BorderSide(color: tokens.brand),
                                  ),
                                ),
                                onSubmitted: (_) => _saveServerUrl(),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            FilledButton.icon(
                              onPressed: _saveServerUrl,
                              style: FilledButton.styleFrom(
                                backgroundColor: tokens.brand,
                                foregroundColor: tokens.surfaceSoft,
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppRadius.allSm,
                                ),
                              ),
                              icon: const Icon(Icons.save_outlined, size: 16),
                              label: const Text('保存'),
                            ),
                          ],
                        ),
                      ],
                    ),
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

/// surface 卡片分组容器。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...children,
        ],
      ),
    );
  }
}

/// 一行设置:左标签/说明,右侧控件。
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.trailing, this.hint});

  final String label;
  final Widget trailing;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint!, style: AppTypography.bodySecondary),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          trailing,
        ],
      ),
    );
  }
}

/// 统一样式的下拉选择(surface 底 + border 描边)。
class _StyledDropdown<T> extends StatelessWidget {
  const _StyledDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<({T value, String label})> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: AppRadius.allSm,
        border: Border.all(color: tokens.border),
      ),
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: tokens.surfaceRaised,
        icon: Icon(
          Icons.expand_more_rounded,
          size: 16,
          color: tokens.textSecondary,
        ),
        style: AppTypography.body,
        items: [
          for (final item in items)
            DropdownMenuItem(value: item.value, child: Text(item.label)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}
