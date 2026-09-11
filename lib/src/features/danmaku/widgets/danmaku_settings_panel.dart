/// 弹幕细粒度设置面板(A3)。
///
/// 仅承载「透明度 / 字号 / 速度 / 显示区域」四项细粒度调节,总开关沿用
/// `settings_provider` 的 `danmakuEnabled`(本面板不重复做开关)。所有控件
/// 都读写 [danmakuSettingsProvider],无死控件(`onChanged` 全部落到 notifier)。
///
/// 文案禁用全角冒号(用空格 / 半角分隔),避免与侧栏弹幕条目定位约定冲突。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/danmaku_settings_provider.dart';
import '../domain/danmaku_settings.dart';

/// 显示区域档位的可读标签(按 [DanmakuSettings.kDisplayAreaRatios] 顺序)。
const List<String> _kDisplayAreaLabels = <String>[
  '全屏',
  '3/4 屏',
  '1/2 屏',
  '1/4 屏',
  '1/8 屏',
];

/// 弹幕设置面板。
///
/// 作为独立控件存在,由 lead 统一挂接到侧栏设置 tab / 弹幕设置入口;
/// 自身不依赖总开关,只消费 [danmakuSettingsProvider]。
class DanmakuSettingsPanel extends ConsumerWidget {
  const DanmakuSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(danmakuSettingsProvider);
    final controller = ref.read(danmakuSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: <Widget>[
        _SliderRow(
          label: '不透明度',
          valueLabel: '${settings.opacity}%',
          value: settings.opacity.toDouble(),
          min: DanmakuSettings.kOpacityMin.toDouble(),
          max: DanmakuSettings.kOpacityMax.toDouble(),
          divisions: DanmakuSettings.kOpacityMax - DanmakuSettings.kOpacityMin,
          onChanged: (v) => controller.setOpacity(v.round()),
        ),
        _SliderRow(
          label: '字号',
          valueLabel: '${settings.fontSize}px',
          value: settings.fontSize.toDouble(),
          min: DanmakuSettings.kFontSizeMin.toDouble(),
          max: DanmakuSettings.kFontSizeMax.toDouble(),
          divisions: DanmakuSettings.kFontSizeMax - DanmakuSettings.kFontSizeMin,
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
        const SizedBox(height: 8),
        const _SectionLabel('显示区域'),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          key: const Key('danmaku-display-area'),
          // 多选关闭:单选模式,选中即生效。
          multiSelectionEnabled: false,
          emptySelectionAllowed: false,
          selected: <double>{settings.displayAreaRatio},
          onSelectionChanged: (selected) {
            if (selected.isNotEmpty) {
              controller.setDisplayAreaRatio(selected.single);
            }
          },
          segments: <ButtonSegment<double>>[
            for (var i = 0; i < DanmakuSettings.kDisplayAreaRatios.length; i++)
              ButtonSegment<double>(
                value: DanmakuSettings.kDisplayAreaRatios[i],
                label: Text(_kDisplayAreaLabels[i]),
              ),
          ],
        ),
      ],
    );
  }
}

/// 单个滑杆行:左侧文案 + 右侧实时数值 + 下方滑杆。
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                valueLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 区块标题(避免与滑杆数值混淆)。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}
