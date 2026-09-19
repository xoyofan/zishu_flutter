/// 弹幕细粒度设置面板(A3),形态对齐 web `OverlayDanmakuSettingsPanel.vue`:
/// 标题行「飘屏弹幕」(amber)+「显示」开关 + 透明度/字号/速度三列滑杆行 +
/// 「区域」下拉(4 档)。
///
/// 总开关沿用 `settings_provider` 的 `danmakuEnabled`(本面板只做透传读写,
/// 与侧栏设置页/控制条按钮共享同一份状态)。细粒度四项读写
/// [danmakuSettingsProvider],无死控件(`onChanged` 全部落到 notifier)。
///
/// 文案禁用全角冒号(用空格 / 半角分隔),避免与侧栏弹幕条目定位约定冲突。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/zishu_tokens.dart';
import '../../follow/application/settings_provider.dart';
import '../application/danmaku_settings_provider.dart';
import '../domain/danmaku_settings.dart';

/// 行首 label 固定宽(px),对齐 web `2.4rem` ≈ 38px。
const double _kLabelWidth = 38;

/// 显示区域档位的可读标签(按 [DanmakuSettings.kDisplayAreaRatios] 顺序,
/// 对齐 web el-select:全屏 / 3/4 / 半屏 / 1/4)。
const List<String> _kDisplayAreaLabels = <String>[
  '全屏',
  '3/4 屏',
  '半屏',
  '1/4 屏',
];

/// 弹幕设置面板。
///
/// 作为独立控件存在,由 lead 统一挂接到侧栏设置 tab / 弹幕设置入口;
/// 总开关消费 `settingsProvider.danmakuEnabled`,细粒度消费
/// [danmakuSettingsProvider]。
class DanmakuSettingsPanel extends ConsumerWidget {
  const DanmakuSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(danmakuSettingsProvider);
    final controller = ref.read(danmakuSettingsProvider.notifier);
    // 「显示」= 全局弹幕总开关(与侧栏设置页/控制条弹幕按钮同一份持久化状态)。
    final danmakuEnabled = ref.watch(
      settingsProvider.select((s) => s.danmakuEnabled),
    );
    final settingsController = ref.read(settingsProvider.notifier);

    final labelStyle = context.textSecondary;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: <Widget>[
        // 标题行:12px w600 amber,底部分隔线(web .overlay-settings__title)。
        Container(
          padding: const EdgeInsets.only(bottom: 6),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.tokens.border),
            ),
          ),
          child: Text(
            '飘屏弹幕',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.tokens.brand,
            ),
          ),
        ),
        // 「显示」开关行(web .overlay-settings__row--toggle)。
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: _kLabelWidth,
                child: Text('显示', style: labelStyle),
              ),
              SizedBox(
                height: 32,
                child: Switch(
                  value: danmakuEnabled,
                  onChanged: settingsController.setDanmakuEnabled,
                ),
              ),
            ],
          ),
        ),
        _SliderRow(
          label: '透明度',
          valueLabel: '${settings.opacity}%',
          value: settings.opacity.toDouble(),
          min: DanmakuSettings.kOpacityMin.toDouble(),
          max: DanmakuSettings.kOpacityMax.toDouble(),
          divisions: DanmakuSettings.kOpacityMax - DanmakuSettings.kOpacityMin,
          onChanged: (v) => controller.setOpacity(v.round()),
        ),
        _SliderRow(
          label: '字号',
          // 对齐 web:值无单位(「20」而非「20px」)。
          valueLabel: '${settings.fontSize}',
          value: settings.fontSize.toDouble(),
          min: DanmakuSettings.kFontSizeMin.toDouble(),
          max: DanmakuSettings.kFontSizeMax.toDouble(),
          divisions:
              DanmakuSettings.kFontSizeMax - DanmakuSettings.kFontSizeMin,
          onChanged: (v) => controller.setFontSize(v.round()),
        ),
        _SliderRow(
          label: '速度',
          valueLabel: '${settings.speed}',
          value: settings.speed.toDouble(),
          min: DanmakuSettings.kSpeedMin.toDouble(),
          max: DanmakuSettings.kSpeedMax.toDouble(),
          divisions: DanmakuSettings.kSpeedMax - DanmakuSettings.kSpeedMin,
          onChanged: (v) => controller.setSpeed(v.round()),
        ),
        // 显示区域:下拉单选(web el-select,4 档)。
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: _kLabelWidth,
                child: Text('区域', style: labelStyle),
              ),
              Expanded(
                child: DropdownButton<double>(
                  key: const Key('danmaku-display-area'),
                  value: settings.displayAreaRatio,
                  isExpanded: true,
                  isDense: true,
                  items: <DropdownMenuItem<double>>[
                    for (var i = 0;
                        i < DanmakuSettings.kDisplayAreaRatios.length;
                        i++)
                      DropdownMenuItem<double>(
                        value: DanmakuSettings.kDisplayAreaRatios[i],
                        child: Text(
                          _kDisplayAreaLabels[i],
                          style: labelStyle,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) controller.setDisplayAreaRatio(v);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单个滑杆行:单行三列(label 固定宽 + Expanded 滑杆 + amber 值右对齐),
/// 对齐 web `.overlay-settings__row` 的 `2.4rem minmax(0,1fr) auto` 网格。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _kLabelWidth,
            child: Text(
              label,
              style: context.textSecondary,
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ),
          Text(
            valueLabel,
            style: TextStyle(
              fontSize: 12,
              color: context.tokens.brand,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
