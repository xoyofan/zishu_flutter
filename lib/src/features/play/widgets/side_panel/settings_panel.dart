part of '../play_side_panel.dart';

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsProvider);
    final throttled = settings.chatThrottleMode == ChatThrottleMode.perNSeconds;
    return ListView(
      key: const Key('play-side-settings-panel'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      children: [
        _SettingsGroup(
          title: '播放',
          children: [
            _SettingRow(
              label: '线路格式',
              trailing: DropdownButton<PreferredLineFormat>(
                key: const Key('play-side-setting-line-format'),
                value: settings.preferredLineFormat,
                isDense: true,
                underline: const SizedBox.shrink(),
                dropdownColor: tokens.surfaceRaised,
                style: TextStyle(fontSize: 11, color: tokens.textPrimary),
                items: [
                  for (final format in PreferredLineFormat.values)
                    DropdownMenuItem(value: format, child: Text(format.label)),
                ],
                onChanged: (format) {
                  if (format != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setPreferredLineFormat(format);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _SettingsGroup(
          title: '聊天弹幕',
          children: [
            _SettingRow(
              label: '聊天',
              trailing: CompactSwitch(
                key: const Key('play-side-setting-chat'),
                value: settings.chatEnabled,
                onChanged: (enabled) =>
                    ref.read(settingsProvider.notifier).setChatEnabled(enabled),
              ),
            ),
            // 聊天开时内联渲染设置(对齐 web SideSettingsTab.vue 41-105:
            // 透明度 10-100 / 字号 12-24 / 间距 0-16 / 速度 1-10 + 节流开关),
            // 控制**侧栏聊天区**的消息渲染(字号/行距/透明度/放行速率)。
            // 旧「弹幕样式 → 调整」入口(飘屏弹幕设置对话框)已按用户口径
            // (2026-09-19)移除,飘屏细项不再从侧栏进入。
            if (settings.chatEnabled) ...[
              _SettingSliderRow(
                key: const Key('play-side-setting-chat-opacity'),
                label: '透明度',
                value: settings.chatOpacity.toDouble(),
                min: SettingsState.chatOpacityMin.toDouble(),
                max: SettingsState.chatOpacityMax.toDouble(),
                valueText: '${settings.chatOpacity}%',
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setChatOpacity(value.round()),
              ),
              _SettingSliderRow(
                key: const Key('play-side-setting-chat-font-size'),
                label: '字号',
                value: settings.chatFontSize.toDouble(),
                min: SettingsState.chatFontSizeMin.toDouble(),
                max: SettingsState.chatFontSizeMax.toDouble(),
                valueText: '${settings.chatFontSize}',
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setChatFontSize(value.round()),
              ),
              _SettingSliderRow(
                key: const Key('play-side-setting-chat-gap'),
                label: '间距',
                value: settings.chatLineSpacing.toDouble(),
                min: SettingsState.chatLineSpacingMin.toDouble(),
                max: SettingsState.chatLineSpacingMax.toDouble(),
                valueText: '${settings.chatLineSpacing}',
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setChatLineSpacing(value.round()),
              ),
              _SettingSliderRow(
                key: const Key('play-side-setting-chat-speed'),
                label: '速度',
                value: settings.chatSpeed.toDouble(),
                min: SettingsState.chatSpeedMin.toDouble(),
                max: SettingsState.chatSpeedMax.toDouble(),
                enabled: throttled,
                valueText: throttled
                    ? '每${settings.chatSpeed}秒一条'
                    : ChatThrottleMode.unlimited.label,
                leading: CompactSwitch(
                  key: const Key('play-side-setting-chat-throttle'),
                  value: throttled,
                  onChanged: (on) => ref
                      .read(settingsProvider.notifier)
                      .setChatThrottleMode(
                        on
                            ? ChatThrottleMode.perNSeconds
                            : ChatThrottleMode.unlimited,
                      ),
                ),
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setChatSpeed(value.round()),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: context.tokens.surfaceSoft,
        // 对齐 web .settings-group 圆角(--fluent-radius-sm ≈ 8)。
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              // 对齐 web .settings-group__title(.78rem ≈ 12.5)。
              fontSize: 12.5,
              height: 1.2,
              color: context.tokens.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: context.textCaption)),
        trailing,
      ],
    );
  }
}

/// 设置滑杆行(对齐 web SideSettingsTab `.setting-row` 三列布局:
/// label 列约 3.25rem、滑杆弹性、数值右对齐)。
///
/// [leading] 供速度行放节流开关(web el-checkbox,位于滑杆前);
/// [enabled] = false 时滑杆禁用但数值文案保留(web 速度行在全量态的呈现)。
class _SettingSliderRow extends StatelessWidget {
  const _SettingSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
    this.enabled = true,
    this.leading,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueText;

  /// null = 禁用(节流关闭时的速度滑杆)。
  final ValueChanged<double>? onChanged;
  final bool enabled;

  /// 滑杆前的附加控件(节流开关)。
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        // 对齐 web label 列 3.25rem ≈ 52。
        SizedBox(width: 52, child: Text(label, style: context.textCaption)),
        if (leading != null) ...[leading!, const SizedBox(width: 4)],
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: (max - min).round(),
              activeColor: tokens.accent,
              inactiveColor: tokens.border,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        // 右对齐数值文案(对齐 web .setting-value),宽度容纳「每10秒一条」。
        SizedBox(
          width: 72,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: context.textCaption,
          ),
        ),
      ],
    );
  }
}
