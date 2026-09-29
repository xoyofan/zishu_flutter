/// 主题色 token 的外置层:[ZishuTokens] 的 33 个颜色字段可由 JSON 覆盖,
/// 加载优先级 **外部 override 文件 → 打包内默认 JSON(`assets/config/tokens.json`)
/// → 代码常量(`ZishuTokens.dark/light`)**;任一层缺失或解析失败都静默回退
/// 上一层,任何情况下不会让主题构建失败(不白屏)。
///
/// 真源治理(见 AGENTS.md 视觉真源):**代码常量仍是唯一真源**。打包内 JSON
/// 与代码常量逐字节钉死在 `test/shared/tokens_json_contract_test.dart`
/// (`ZISHU_REGEN_TOKENS=1 flutter test …` 可重新生成);外部 override 只是
/// 运行时叠加层 —— 不回写、不进 golden、不受 `check_design_tokens` 守卫约束。
///
/// JSON 形态:
/// ```json
/// {
///   "schema": 1,
///   "dark": { "background": "#FF181818", "...": "..." },
///   "light": { }
/// }
/// ```
/// - 颜色一律 `#AARRGGBB`(与代码里 `Color(0xFF181818)` 同序)或 `#RRGGBB`
///   (alpha 补 FF)。
/// - `dark`/`light` 可整体缺省,也可只写部分字段(缺的字段保持基线值);
///   **未知字段忽略**(前向兼容),**已知字段的值非法则整个文件拒绝**
///   (宁回退默认,不半截生效)。
/// - 外部 override 路径(仅 Windows):`%APPDATA%\zishu_flutter\overrides\tokens.json`;
///   文件监听热更由 [ZishuTokensReloader] 提供(WindowsApp 启动时开启,
///   变更免重打包即时生效)。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;

import 'tokens_external.dart';
import 'zishu_tokens.dart';

/// 打包内默认 token JSON 资产路径(pubspec 已声明 `assets/config/`)。
const String _kBundledTokensAsset = 'assets/config/tokens.json';

/// [ZishuTokens] 全部颜色字段名(与构造参数同名,顺序即文档序)。
///
/// 解析器按它做白名单(未知字段忽略),编码器按它决定输出顺序。
const List<String> kZishuTokenFields = <String>[
  'background',
  'surface',
  'surfaceSoft',
  'surfaceRaised',
  'brand',
  'brandBright',
  'accent',
  'textPrimary',
  'textSecondary',
  'border',
  'liveBadge',
  'error',
  'success',
  'barrier',
  'coverScrim',
  'coverScrimText',
  'promoBadge',
  'statAudience',
  'statVip',
  'statSvip',
  'chatSuperFan',
  'playFollowBg',
  'playFollowBgHover',
  'playFollowBgActive',
  'playFollowBorder',
  'playFollowText',
  'playFollowTextActive',
  'playSuperBg',
  'playSuperBgHover',
  'playSuperBgActive',
  'playSuperBorder',
  'playSuperText',
  'playSuperTextActive',
];

/// 一套生效 token(深浅两份)。
class ZishuTokenSet {
  const ZishuTokenSet({required this.dark, required this.light});

  final ZishuTokens dark;
  final ZishuTokens light;

  /// 代码常量基线(= `ZishuTokens.dark` / `ZishuTokens.light`)。
  /// 打包内 JSON 与此逐字节同值,由契约测试钉死。
  static const ZishuTokenSet codeDefaults = ZishuTokenSet(
    dark: ZishuTokens.dark,
    light: ZishuTokens.light,
  );
}

/// 从 tokens JSON 解析出的颜色补丁:字段名 → 颜色,深浅各一份。
/// 只含文件里出现的字段,叠加到基线时缺省字段保持基线值。
class ZishuTokensPatch {
  const ZishuTokensPatch({this.dark = const {}, this.light = const {}});

  final Map<String, Color> dark;
  final Map<String, Color> light;

  bool get isEmpty => dark.isEmpty && light.isEmpty;
}

/// tokens JSON 非法。调用方(启动链/热更链)一律捕获后回退,不向上抛。
class ZishuTokensFormatException implements Exception {
  const ZishuTokensFormatException(this.message);

  final String message;

  @override
  String toString() => 'ZishuTokensFormatException: $message';
}

/// 解析 tokens JSON;非法即抛 [ZishuTokensFormatException]。
///
/// 拒绝口径(整文件拒绝,回退上一层):顶层不是对象、schema 不是 1、
/// `dark`/`light` 不是对象、已知字段的值不是合法颜色。未知字段忽略。
ZishuTokensPatch parseZishuTokensJson(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw ZishuTokensFormatException('JSON 语法错误: ${error.message}');
  }
  if (decoded is! Map) {
    throw const ZishuTokensFormatException('顶层必须是 JSON 对象');
  }
  final schema = decoded['schema'];
  if (schema != 1) {
    throw ZishuTokensFormatException('schema 必须为 1,实际是 $schema');
  }
  return ZishuTokensPatch(
    dark: _parseThemeMap(decoded['dark'], theme: 'dark'),
    light: _parseThemeMap(decoded['light'], theme: 'light'),
  );
}

Map<String, Color> _parseThemeMap(Object? raw, {required String theme}) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw ZishuTokensFormatException('"$theme" 必须是 JSON 对象');
  }
  final out = <String, Color>{};
  for (final entry in raw.entries) {
    final field = entry.key as String;
    // 未知字段忽略:打包 JSON 由生成器保证干净;外部 override 允许带着
    // 更新版本才有的新字段跑在旧 exe 上(前向兼容)。
    if (!kZishuTokenFields.contains(field)) continue;
    out[field] = _parseColor(entry.value, '$theme.$field');
  }
  return out;
}

Color _parseColor(Object? value, String where) {
  if (value is! String) {
    throw ZishuTokensFormatException('$where 颜色必须是字符串,实际是 $value');
  }
  final match = RegExp('^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\$')
      .firstMatch(value.trim());
  if (match == null) {
    throw ZishuTokensFormatException(
      '$where 颜色必须是 #RRGGBB / #AARRGGBB,实际是 "$value"',
    );
  }
  final hex = match.group(1)!;
  final argb = hex.length == 6 ? 'FF$hex' : hex;
  return Color(int.parse(argb, radix: 16));
}

/// 把补丁叠到基线(深浅各自 copyWith,补丁缺的字段保持基线值)。
ZishuTokenSet applyZishuTokensPatch(
  ZishuTokenSet base,
  ZishuTokensPatch patch,
) {
  if (patch.isEmpty) return base;
  return ZishuTokenSet(
    dark: _applyTheme(base.dark, patch.dark),
    light: _applyTheme(base.light, patch.light),
  );
}

ZishuTokens _applyTheme(ZishuTokens base, Map<String, Color> patch) {
  Color? field(String name) => patch[name];
  return base.copyWith(
    background: field('background'),
    surface: field('surface'),
    surfaceSoft: field('surfaceSoft'),
    surfaceRaised: field('surfaceRaised'),
    brand: field('brand'),
    brandBright: field('brandBright'),
    accent: field('accent'),
    textPrimary: field('textPrimary'),
    textSecondary: field('textSecondary'),
    border: field('border'),
    liveBadge: field('liveBadge'),
    error: field('error'),
    success: field('success'),
    barrier: field('barrier'),
    coverScrim: field('coverScrim'),
    coverScrimText: field('coverScrimText'),
    promoBadge: field('promoBadge'),
    statAudience: field('statAudience'),
    statVip: field('statVip'),
    statSvip: field('statSvip'),
    chatSuperFan: field('chatSuperFan'),
    playFollowBg: field('playFollowBg'),
    playFollowBgHover: field('playFollowBgHover'),
    playFollowBgActive: field('playFollowBgActive'),
    playFollowBorder: field('playFollowBorder'),
    playFollowText: field('playFollowText'),
    playFollowTextActive: field('playFollowTextActive'),
    playSuperBg: field('playSuperBg'),
    playSuperBgHover: field('playSuperBgHover'),
    playSuperBgActive: field('playSuperBgActive'),
    playSuperBorder: field('playSuperBorder'),
    playSuperText: field('playSuperText'),
    playSuperTextActive: field('playSuperTextActive'),
  );
}

/// 按字段名读取主题值(编码器用)。
Color _themeColor(ZishuTokens theme, String field) => switch (field) {
  'background' => theme.background,
  'surface' => theme.surface,
  'surfaceSoft' => theme.surfaceSoft,
  'surfaceRaised' => theme.surfaceRaised,
  'brand' => theme.brand,
  'brandBright' => theme.brandBright,
  'accent' => theme.accent,
  'textPrimary' => theme.textPrimary,
  'textSecondary' => theme.textSecondary,
  'border' => theme.border,
  'liveBadge' => theme.liveBadge,
  'error' => theme.error,
  'success' => theme.success,
  'barrier' => theme.barrier,
  'coverScrim' => theme.coverScrim,
  'coverScrimText' => theme.coverScrimText,
  'promoBadge' => theme.promoBadge,
  'statAudience' => theme.statAudience,
  'statVip' => theme.statVip,
  'statSvip' => theme.statSvip,
  'chatSuperFan' => theme.chatSuperFan,
  'playFollowBg' => theme.playFollowBg,
  'playFollowBgHover' => theme.playFollowBgHover,
  'playFollowBgActive' => theme.playFollowBgActive,
  'playFollowBorder' => theme.playFollowBorder,
  'playFollowText' => theme.playFollowText,
  'playFollowTextActive' => theme.playFollowTextActive,
  'playSuperBg' => theme.playSuperBg,
  'playSuperBgHover' => theme.playSuperBgHover,
  'playSuperBgActive' => theme.playSuperBgActive,
  'playSuperBorder' => theme.playSuperBorder,
  'playSuperText' => theme.playSuperText,
  'playSuperTextActive' => theme.playSuperTextActive,
  _ => throw ArgumentError('未知的 ZishuTokens 字段: $field'),
};

/// 编码为 tokens JSON(缩进两格 + 尾换行),字段顺序按 [kZishuTokenFields]。
///
/// 只被契约测试用于生成/校验 `assets/config/tokens.json` —— 代码常量是真源,
/// JSON 是它的序列化产物,两者必须逐字节一致。
String encodeZishuTokensJson(ZishuTokenSet set) {
  final json = <String, Object?>{
    '_note':
        '由 test/shared/tokens_json_contract_test.dart '
        '(ZISHU_REGEN_TOKENS=1)从代码常量生成,勿手改;颜色为 #AARRGGBB。',
    'schema': 1,
    'dark': {
      for (final field in kZishuTokenFields)
        field: _toHex(_themeColor(set.dark, field)),
    },
    'light': {
      for (final field in kZishuTokenFields)
        field: _toHex(_themeColor(set.light, field)),
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

String _toHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// 打包内默认 JSON → 补丁;资产缺失/损坏返回 null(回退代码常量)。
Future<ZishuTokensPatch?> _loadBundledPatch() async {
  try {
    return parseZishuTokensJson(
      await rootBundle.loadString(_kBundledTokensAsset),
    );
  } on Object catch (error) {
    _debugWarn('打包内 tokens.json 解析失败,回退代码常量: $error');
    return null;
  }
}

/// 外部 override 文件 → 补丁;无文件 / IO 失败 / 解析失败返回 null。
Future<ZishuTokensPatch?> _loadExternalPatch({String? overridePath}) async {
  final source = await readZishuTokensOverrideFile(overridePath);
  if (source == null) return null;
  try {
    return parseZishuTokensJson(source);
  } on ZishuTokensFormatException catch (error) {
    _debugWarn('外部 override 解析失败(整文件忽略): $error');
    return null;
  }
}

/// 启动链:外部 override → 打包 JSON → 代码常量;永不抛、永不返回 null。
/// `main()` 在首帧前调用,避免 override 生效时先闪一帧代码默认色。
Future<ZishuTokenSet> resolveZishuTokenSet({String? overridePath}) async {
  var set = ZishuTokenSet.codeDefaults;
  final bundled = await _loadBundledPatch();
  if (bundled != null) set = applyZishuTokensPatch(set, bundled);
  final external = await _loadExternalPatch(overridePath: overridePath);
  if (external != null) set = applyZishuTokensPatch(set, external);
  return set;
}

/// 热更链:只重读外部 override,叠加到「打包 JSON → 代码常量」基线。
///
/// 外部无文件或本次解析失败 → null(调用方保持现值):编辑器保存瞬间的
/// 半截文件、误删文件,都不应把运行中的界面打回默认。
Future<ZishuTokenSet?> reloadExternalZishuTokens({String? overridePath}) async {
  final external = await _loadExternalPatch(overridePath: overridePath);
  if (external == null) return null;
  var base = ZishuTokenSet.codeDefaults;
  final bundled = await _loadBundledPatch();
  if (bundled != null) base = applyZishuTokensPatch(base, bundled);
  return applyZishuTokensPatch(base, external);
}

/// 外部 override 文件监听器:文件变更去抖后重载,经 [changes] 广播。
///
/// **纯通知方**:不直接改 `ZishuTheme.tokens` —— 那是 app 壳的事
/// (订阅 → 安装 → 重建 MaterialApp),监听器保持可独立单测。
/// start 前与 stop 后不产生任何 IO;重复 start 幂等;所有失败静默(保持现值)。
class ZishuTokensReloader {
  ZishuTokensReloader();

  /// 应用级单例(app 壳订阅它;测试自建实例互不干扰)。
  static final ZishuTokensReloader instance = ZishuTokensReloader();

  final StreamController<ZishuTokenSet> _changes =
      StreamController<ZishuTokenSet>.broadcast();

  /// 热更后的完整 token set(外部 override 已叠加)。
  Stream<ZishuTokenSet> get changes => _changes.stream;

  StreamSubscription<void>? _subscription;
  Timer? _debounce;
  String? _overridePath;

  bool get isActive => _subscription != null;

  /// 开始监听;平台不支持 / 路径无法解析时静默不监听。
  void start({String? overridePath}) {
    if (isActive) return;
    final events = watchZishuTokensOverrideFile(overridePath);
    if (events == null) return;
    _overridePath = overridePath;
    _subscription = events.listen(
      (_) {
        // 编辑器一次保存常触发多个目录事件,去抖后只重读一次。
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), () {
          unawaited(_reloadAndBroadcast());
        });
      },
      onError: (_) {
        // 监听中断(目录被移走等):停止即可,运行中的样式保持现值。
        stop();
      },
    );
  }

  Future<void> _reloadAndBroadcast() async {
    final set = await reloadExternalZishuTokens(overridePath: _overridePath);
    if (set != null) _changes.add(set);
  }

  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _subscription?.cancel();
    _subscription = null;
    _overridePath = null;
  }
}

void _debugWarn(String message) {
  if (kDebugMode) debugPrint('[tokens] $message');
}
