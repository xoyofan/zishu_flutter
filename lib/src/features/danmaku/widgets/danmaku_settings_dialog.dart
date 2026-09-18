/// 弹幕细粒度设置的统一入口:设置页与播放页侧栏共用同一对话框,
/// 避免两处各自复制控件(旧实现侧栏是写死的死滑杆,`onChanged: (_) {}`)。
library;

import 'package:flutter/material.dart';

import 'danmaku_settings_panel.dart';

/// 打开弹幕样式设置(不透明度 / 字号 / 速度 / 显示区域)。
Future<void> showDanmakuSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('danmaku-settings-dialog'),
      title: const Text('弹幕样式'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      content: const SizedBox(
        width: 380,
        height: 420,
        child: DanmakuSettingsPanel(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}
