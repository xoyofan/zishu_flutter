/// 平台房间字段的共享展示 formatter。
///
/// 标签/列顺序来自 `live_parser` 的 `SiteRegistration.display`,这里只负责
/// 取值、空值和本地化时间格式化,不再在各个 Widget 里复制平台分支。
library;

import 'package:live_parser/live_parser.dart';

final SiteRegistry _displayRegistry = buildSiteRegistry();

SiteDisplaySpec displaySpecFor(String site) =>
    _displayRegistry[site]?.display ?? const SiteDisplaySpec();

/// 统一房间记录的列值取数(RoomRecord 版):按列读统计字段,
/// 本次无值为 null → 空串,展示层 [displayStatValue] 渲染「—」。
/// 平台差异只在列声明(`SiteDisplaySpec`),这里不复制平台分支。
String roomStatValue(RoomRecord? record, RoomStatField field) =>
    switch (field) {
      RoomStatField.audience => record?.audience ?? '',
      RoomStatField.vip => record?.vip ?? '',
      RoomStatField.svip => record?.svip ?? '',
    };

String displayStatValue(String? raw) {
  final value = raw?.trim() ?? '';
  return value.isEmpty ? '—' : value;
}

/// 关注数格式化:取 [RoomRecord.followers](或搜索命中等其它文本字段),
/// 千分位清洗后按 1 万档折算;未提供(null/空)显示「—」。
String formatFollowersValue(String? raw) {
  final text = (raw?.trim() ?? '').replaceAll(',', '');
  if (text.isEmpty) return '—';
  final value = int.tryParse(text);
  if (value == null) return text;
  if (value < 10000) return text;
  final wan = value / 10000;
  return wan >= 100
      ? '${wan.toStringAsFixed(0)}万'
      : '${wan.toStringAsFixed(1)}万';
}

String formatStartedAt(DateTime? value, {required bool isLive}) {
  if (value == null) return isLive ? '开播中' : '—';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

bool siteSupportsDanmaku(String site) =>
    _displayRegistry[site]?.capabilities.danmaku == true;
