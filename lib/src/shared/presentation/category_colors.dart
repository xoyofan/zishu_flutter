import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 分类配色查询的返回结果。
class CategoryStyle {
  const CategoryStyle({required this.background, required this.foreground});

  /// 不透明底色（卡片分类角标用）。
  final Color background;

  /// 底色之上的文字色（按亮度自动取深色或浅色）。
  final Color foreground;
}

/// 分类主题色:对齐 SFVideoLive `web/src/utils/browse/categoryColor.ts`。
///
/// 解析顺序与参考实现一致:
/// 1. 跨平台 key(如 `lol` / `cs2`)命中 [_themeByKey];
/// 2. 归一化后的分类名命中 [_themeByName];
/// 3. 分类名匹配 [_nameRules] 中的正则;
/// 4. 全部落空时按分类名哈希取 [_fallbackHues] 中的一色(色相均匀分布,
///    避免未知分类扎堆红橙)。
abstract final class CategoryColors {
  /// 跨平台分类 key → 基色(不含 alpha)。
  static const Map<String, int> _themeByKey = {
    'lol': 0x1d4ed8,
    'wzry': 0xca8a04,
    'dota2': 0x991b1b,
    'yjwj': 0xa21caf,
    'cs2': 0x9a3412,
    'valorant': 0xe11d48,
    'hpjy': 0x4d7c0f,
    'sjz': 0x0d9488,
    'aqtw': 0x365314,
    'cf': 0xea580c,
    'ys': 0xeab308,
    'bhxy': 0x6d28d9,
    'jql': 0x4f46e5,
    '3': 0x2563eb,
    'tft': 0x9333ea,
    'jcc': 0xa16207,
    'jx3': 0x0f766e,
    'hs': 0x78350f,
    'dnf': 0xbe123c,
    'dzpd': 0xdb2777,
    'dwrg': 0x581c87,
    'hmwk': 0x57534e,
    'wudao': 0xa855f7,
    'huwai': 0x16a34a,
    'xingxiu': 0xc026d3,
    'yanzhi': 0xec4899,
    'group-wangyou': 0x2563eb,
    'group-shouyou': 0x7c3aed,
    'group-danji': 0x475569,
    'group-yule': 0xd97706,
    'g5_8_1010150_83': 0x1e40af,
    'g1105_485_1010324_309': 0x15803d,
  };

  /// 归一化分类名 → 基色。key 已做「去空格 + 全角冒号转半角 + 小写」处理。
  static const Map<String, int> _themeByName = {
    '英雄联盟': 0x1d4ed8,
    'leagueoflegends': 0x1d4ed8,
    'lol': 0x1d4ed8,
    '王者荣耀': 0xca8a04,
    'dota2': 0x991b1b,
    '刀塔': 0x991b1b,
    '反恐精英': 0x9a3412,
    'cs2': 0x9a3412,
    '无畏契约': 0xe11d48,
    'valorant': 0xe11d48,
    '和平精英': 0x4d7c0f,
    '三角洲行动': 0x0d9488,
    '三角洲': 0x0d9488,
    '暗区突围': 0x365314,
    '穿越火线': 0xea580c,
    '原神': 0xeab308,
    '崩坏:星穹铁道': 0x6d28d9,
    '崩坏星穹铁道': 0x6d28d9,
    '绝区零': 0x4f46e5,
    '崩坏3': 0x2563eb,
    '云顶之弈': 0x9333ea,
    '金铲铲之战': 0xa16207,
    '剑网3': 0x0f766e,
    '炉石传说': 0x78350f,
    '炉石': 0x78350f,
    '地下城与勇士': 0xbe123c,
    '蛋仔派对': 0xdb2777,
    '第五人格': 0x581c87,
    '黑神话:悟空': 0x57534e,
    '黑神话悟空': 0x57534e,
    '永劫无间': 0xa21caf,
    '魔兽世界': 0x1e40af,
    '植物大战僵尸': 0x15803d,
    '植物大战': 0x15803d,
    '热门游戏': 0x0891b2,
    '主机其他': 0x475569,
    '户外': 0x16a34a,
    '星秀': 0xc026d3,
    '颜值': 0xec4899,
    '舞蹈': 0xa855f7,
    '网游': 0x2563eb,
    '网游竞技': 0x2563eb,
    '手游': 0x7c3aed,
    '单机': 0x475569,
    '娱乐': 0xd97706,
  };

  /// 分类名正则兜底规则(对原始分类名匹配,忽略大小写)。
  ///
  /// 用 `final` 而非 `const`:`RegExp` 不是 const 构造。
  static final List<(RegExp, int)> _nameRules = [
    (RegExp(r'英雄联盟|lol', caseSensitive: false), 0x1d4ed8),
    (RegExp(r'王者'), 0xca8a04),
    (RegExp(r'原神'), 0xeab308),
    (RegExp(r'星穹铁道'), 0x6d28d9),
    (RegExp(r'绝区零'), 0x4f46e5),
    (RegExp(r'dota|刀塔', caseSensitive: false), 0x991b1b),
    (RegExp(r'cs2|反恐精英|counter.?strike', caseSensitive: false), 0x9a3412),
    (RegExp(r'valorant|无畏契约', caseSensitive: false), 0xe11d48),
    (RegExp(r'和平精英|pubg', caseSensitive: false), 0x4d7c0f),
    (RegExp(r'穿越火线'), 0xea580c),
    (RegExp(r'暗区突围'), 0x365314),
    (RegExp(r'三角洲'), 0x0d9488),
    (RegExp(r'永劫'), 0xa21caf),
    (RegExp(r'云顶|tft', caseSensitive: false), 0x9333ea),
    (RegExp(r'金铲铲'), 0xa16207),
    (RegExp(r'炉石'), 0x78350f),
    (RegExp(r'地下城|dnf', caseSensitive: false), 0xbe123c),
    (RegExp(r'剑网'), 0x0f766e),
    (RegExp(r'蛋仔'), 0xdb2777),
    (RegExp(r'第五人格'), 0x581c87),
    (RegExp(r'黑神话'), 0x57534e),
    (RegExp(r'魔兽世界'), 0x1e40af),
    (RegExp(r'植物大战'), 0x15803d),
    (RegExp(r'热门游戏'), 0x0891b2),
    (RegExp(r'主机'), 0x475569),
    (RegExp(r'户外'), 0x16a34a),
    (RegExp(r'星秀'), 0xc026d3),
    (RegExp(r'颜值'), 0xec4899),
    (RegExp(r'舞蹈'), 0xa855f7),
    (RegExp(r'射击|fps', caseSensitive: false), 0x0d9488),
    (RegExp(r'棋牌|卡牌'), 0x78350f),
    (RegExp(r'角色扮演|rpg', caseSensitive: false), 0x0f766e),
    (RegExp(r'休闲益智'), 0xd97706),
  ];

  /// 哈希兜底色板:色相均匀分布,避免未知分类扎堆红橙。
  static const List<int> _fallbackHues = [
    0x1d4ed8, 0x0891b2, 0x0d9488, 0x059669, 0x16a34a, 0x65a30d, //
    0xca8a04, 0xea580c, 0xdc2626, 0xe11d48, 0xdb2777, 0xc026d3, //
    0x9333ea, 0x7c3aed, 0x4f46e5, 0x2563eb, 0x0284c7, 0x0369a1, //
    0x047857, 0x15803d, 0x4d7c0f, 0xa16207, 0x9a3412, 0x831843,
  ];

  /// 取分类的**不透明**配色(卡片角标用)。
  ///
  /// [category] 为分类显示名,[site]/[cid] 用于后续扩展跨平台归类,
  /// [crossKey] 为跨平台分类 key(优先级最高)。
  /// 无法解析(分类名为空)时返回 null,调用方回退到中性色。
  static CategoryStyle? opaqueFor({
    required String? category,
    String site = '',
    String cid = '',
    String crossKey = '',
  }) {
    final base = _resolveBase(
      category: category,
      cid: cid,
      crossKey: crossKey,
    );
    if (base == null) return null;
    return _makeOpaquePalette(base);
  }

  static int? _resolveBase({
    required String? category,
    required String cid,
    required String crossKey,
  }) {
    final key = crossKey.trim();
    if (key.isNotEmpty) {
      final byKey = _themeByKey[key];
      if (byKey != null) return byKey;
    }
    final name = (category ?? '').trim();
    if (name.isEmpty) return null;
    final normalized = _normalize(name);
    final byName = _themeByName[normalized];
    if (byName != null) return byName;
    for (final (pattern, color) in _nameRules) {
      if (pattern.hasMatch(name)) return color;
    }
    return _fallbackHues[_hash(name) % _fallbackHues.length];
  }

  /// 归一化:trim + 小写 + 去空白 + 全角冒号转半角(对齐参考实现)。
  static String _normalize(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll('：', ':');
  }

  /// 32 位哈希(对齐 JS `(hash << 5) - hash + code | 0`)。
  static int _hash(String text) {
    var hash = 0;
    for (var i = 0; i < text.length; i++) {
      hash = ((hash * 31) + text.codeUnitAt(i)).toSigned(32);
    }
    return hash.abs();
  }

  /// 由基色生成不透明调色板:底色为基色向 #141414 混 18%,
  /// 文字色按底色亮度在 #1a1400 / #f5f5f5 间自动取值。
  static CategoryStyle _makeOpaquePalette(int base) {
    final bgSolid = _mix(base, 0x141414, 0.18);
    final luminance = _luminance(bgSolid);
    return CategoryStyle(
      background: Color(0xFF000000 | bgSolid),
      foreground: Color(0xFF000000 | (luminance > 0.62 ? 0x1a1400 : 0xf5f5f5)),
    );
  }

  /// sRGB 线性混合,对齐参考实现 `mixHex`。
  static int _mix(int a, int b, double t) {
    final ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
    final br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
    final r = (ar * (1 - t) + br * t).round();
    final g = (ag * (1 - t) + bg * t).round();
    final bl = (ab * (1 - t) + bb * t).round();
    return (math.min(255, math.max(0, r)) << 16) |
        (math.min(255, math.max(0, g)) << 8) |
        math.min(255, math.max(0, bl));
  }

  static double _luminance(int hex) {
    final r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, b = hex & 0xFF;
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  }
}
