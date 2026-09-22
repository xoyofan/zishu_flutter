// Design token guard —— 阻止 UI 代码继续散落裸值(裸色值 / 裸阴影 / 裸字号 / 裸圆角)。
//
// 纯 Dart 实现(只 import dart:io + dart:convert),不依赖 Flutter,因此可以:
//   dart run tool/check_design_tokens.dart
//   dart run tool/check_design_tokens.dart --update-baseline
//
// 退出码: 0 = 通过; 1 = 发现新增违规; 2 = 脚本自身异常/用法错误。
//
// 基线机制: 存量违规固化在 tool/design_token_baseline.json。基线 key 与行号无关,
// 形如 "相对路径|规则id|去空白后的字面量文本", value 为该 key 的出现次数。
// 因此重排代码/移动行号不会误报,而同一处字面量复制粘贴到新文件会被拦下。
// 逐条清零后基线只会"变松",可用 --update-baseline 收紧。

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// 扫描范围(相对仓库根)。
const String _scanRoot = 'lib/src';

/// 基线文件(相对仓库根)。
const String _baselineRelativePath = 'tool/design_token_baseline.json';

/// 行内豁免标记: 违规所在行或上一行包含该文本时跳过该条违规。
const String _ignoreMarker = '// ignore: design_token';

const int _baselineFormatVersion = 1;
const String _baselineGeneratedBy =
    'tool/check_design_tokens.dart --update-baseline';

/// 整文件白名单。
///
/// 理由: 这些文件本身就是"token 定义层"或"纯数据表",裸值就是它们的正常内容;
/// 让守卫去扫它们只会得到永远清不掉的基线噪音。
///   - design_tokens.dart / zishu_tokens.dart: 颜色/阴影/字号/圆角的唯一真源。
///   - platform_brands.dart: 各平台品牌色表(数据,不是 UI 代码的取值)。
///   - category_colors.dart: 分类色映射表(同上)。
///   - danmaku_style.dart: 弹幕样式纯数据模型(颜色/字号的领域默认值)。
///   - chat_badges.dart: 聊天徽章的平台渐变/等级色表(对齐 web `badgeHelpers.ts` 的
///     LEVEL_TIER_GRADIENTS 与 HUYA_BAR_GRADIENTS)——是平台数据,不是 UI 取值。
///     更干净的做法是把色表搬到独立数据文件;本次先白名单止血,避免 54 条假债
///     把真实债务淹掉。
const Set<String> _whitelistedFiles = <String>{
  'lib/src/shared/presentation/design_tokens.dart',
  'lib/src/shared/presentation/zishu_tokens.dart',
  'lib/src/shared/presentation/platform_brands.dart',
  'lib/src/shared/presentation/category_colors.dart',
  'lib/src/features/danmaku/domain/danmaku_style.dart',
  'lib/src/features/play/widgets/side_panel/chat_badges.dart',
};

/// 一条规则 = 稳定字符串 id + 人类可读说明 + 正则。
///
/// 正则里的命名组 `lit` 提供"用于基线 key 的字面量文本"; 没有 `lit` 组时退化为
/// 整个匹配文本。字面量文本统一去掉空白,保证 key 与代码格式化无关。
class _Rule {
  const _Rule(this.id, this.description, this.pattern);

  final String id;
  final String description;
  final RegExp pattern;
}

final List<_Rule> _rules = <_Rule>[
  // 裸色值: Color(0xAARRGGBB) 字面量,或 Colors.<name>。
  // 负向后顾排除 AppColors.x / CategoryColors.y 这类 token 访问器(标识符以
  // [A-Za-z0-9_$] 或 '.' 紧跟 "Colors" 时不算裸值)。
  _Rule(
    'raw_color',
    '裸色值(Color(0x...) 字面量 / Colors.<name>)',
    RegExp(
      r'(?<lit>Color\(0x[0-9a-fA-F]+\)'
      r'|(?<![A-Za-z0-9_$.])Colors\.[A-Za-z_][A-Za-z0-9_]*)',
    ),
  ),
  // 裸阴影: BoxShadow(...) 构造(应使用阴影 token)。
  _Rule(
    'raw_shadow',
    '裸阴影(BoxShadow(...))',
    RegExp(r'(?<lit>BoxShadow\()'),
  ),
  // 裸字号: fontSize: <数字字面量>。fontSize: AppTypography.x 之类不算。
  _Rule(
    'raw_font_size',
    '裸字号(fontSize: <数字字面量>)',
    RegExp(r'(?<lit>fontSize:[ \t]*\d+(?:\.\d+)?)'),
  ),
  // 裸圆角: BorderRadius.circular(<数字字面量>) / Radius.circular(<数字字面量>)。
  // 合并成一条正则,避免 BorderRadius.circular 被 Radius.circular 二次计数。
  _Rule(
    'raw_radius',
    '裸圆角(Radius.circular(<数字字面量>))',
    RegExp(r'(?<lit>(?:Border)?Radius\.circular\([ \t]*\d+(?:\.\d+)?)'),
  ),
];

// ---------------------------------------------------------------------------
// 数据结构
// ---------------------------------------------------------------------------

class _Violation {
  _Violation(this.path, this.ruleId, this.literal, this.line);

  /// 仓库相对路径,统一使用 '/'。
  final String path;
  final String ruleId;

  /// 去空白后的字面量文本(基线 key 的第三段)。
  final String literal;

  /// 1-based 行号(仅用于报错定位,不参与基线 key)。
  final int line;

  String get key => '$path|$ruleId|$literal';
}

/// 基线文件内容: key -> 出现次数。
class _Baseline {
  _Baseline(this.entries);

  final Map<String, int> entries;

  int get total => entries.values.fold<int>(0, (int sum, int v) => sum + v);
}

class _UsageException implements Exception {
  _UsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------

void main(List<String> args) {
  try {
    exit(_run(args));
  } on _UsageException catch (error) {
    stderr.writeln('[design-token-guard] ${error.message}');
    exit(2);
  } catch (error, stackTrace) {
    stderr.writeln('[design-token-guard] 脚本异常: $error');
    stderr.writeln(stackTrace.toString());
    exit(2);
  }
}

int _run(List<String> args) {
  bool updateBaseline = false;
  for (final String arg in args) {
    switch (arg) {
      case '--update-baseline':
        updateBaseline = true;
        break;
      case '-h':
      case '--help':
        _printUsage();
        return 0;
      default:
        throw _UsageException('未知参数: $arg\n\n${_usageText()}');
    }
  }

  final Directory repoRoot = _resolveRepoRoot();
  final Directory scanDir = Directory('${repoRoot.path}/$_scanRoot');
  final File baselineFile = File('${repoRoot.path}/$_baselineRelativePath');

  final List<_Violation> violations = _scan(scanDir, repoRoot.path);
  final Map<String, int> currentCounts = _countByKey(violations);

  if (updateBaseline) {
    _writeBaseline(baselineFile, currentCounts);
    stdout.writeln('== design token guard (update baseline) ==');
    stdout.writeln('扫描范围: $_scanRoot/**/*.dart '
        '(整文件白名单 ${_whitelistedFiles.length} 个, 行内豁免 $_ignoreMarker)');
    stdout.writeln('规则命中:');
    _printRuleTable(currentCounts, currentCounts);
    stdout.writeln(_progressLine(_total(currentCounts), _total(currentCounts)));
    stdout.writeln('基线已写入: $_baselineRelativePath '
        '(${currentCounts.length} 个 key / ${_total(currentCounts)} 条)');
    stdout.writeln('design token guard: OK');
    return 0;
  }

  final _Baseline baseline = _readBaseline(baselineFile);

  // 基线之外的新 key,或计数超出基线的 key,都是"新增违规"。
  // 同一 key 的多个匹配里,只有超出基线数量的那些算新增。
  final List<_Violation> added = <_Violation>[];
  final Map<String, int> seen = <String, int>{};
  for (final _Violation violation in violations) {
    final int seenSoFar = seen[violation.key] ?? 0;
    seen[violation.key] = seenSoFar + 1;
    final int allowed = baseline.entries[violation.key] ?? 0;
    if (seenSoFar >= allowed) {
      added.add(violation);
    }
  }

  // 计数减少(逐条清零)只作为提示。
  final Map<String, int> cleared = <String, int>{};
  for (final MapEntry<String, int> entry in baseline.entries.entries) {
    final int now = currentCounts[entry.key] ?? 0;
    if (now < entry.value) {
      cleared[entry.key] = entry.value - now;
    }
  }
  final int clearedTotal =
      cleared.values.fold<int>(0, (int sum, int v) => sum + v);

  stdout.writeln('== design token guard ==');
  stdout.writeln('扫描范围: $_scanRoot/**/*.dart '
      '(整文件白名单 ${_whitelistedFiles.length} 个, 行内豁免 $_ignoreMarker)');
  stdout.writeln('规则命中(当前 vs 基线):');
  _printRuleTable(currentCounts, baseline.entries);
  stdout.writeln(
    '清零进度: 基线 ${baseline.total} 条 -> 当前 ${_total(currentCounts)} 条',
  );
  if (clearedTotal > 0) {
    stdout.writeln('已清零 $clearedTotal 条（可更新基线）');
    final List<String> keys = cleared.keys.toList()..sort();
    for (final String key in keys) {
      stdout.writeln('  - $key: ${baseline.entries[key]} -> '
          '${currentCounts[key] ?? 0}');
    }
  }

  if (added.isEmpty) {
    stdout.writeln('design token guard: OK');
    return 0;
  }

  added.sort((_Violation a, _Violation b) {
    final int byPath = a.path.compareTo(b.path);
    if (byPath != 0) return byPath;
    return a.line.compareTo(b.line);
  });
  stdout.writeln('');
  stdout.writeln('新增违规 ${added.length} 条(基线之外, 请改用 design token):');
  for (final _Violation violation in added) {
    stdout.writeln(
      '  ${violation.path}:${violation.line}: ${violation.ruleId}: '
      '${violation.literal}',
    );
  }
  stdout.writeln('');
  stdout.writeln('design token guard: FAILED '
      '(新增违规 ${added.length} 条; 新增违规必须改为 token, '
      '或在行内/上一行加 "$_ignoreMarker" 说明理由)');
  return 1;
}

// ---------------------------------------------------------------------------
// 扫描
// ---------------------------------------------------------------------------

String _usageText() => '用法:\n'
    '  dart run tool/check_design_tokens.dart                 # 校验(与基线对比)\n'
    '  dart run tool/check_design_tokens.dart --update-baseline  # 重写基线\n'
    '  dart run tool/check_design_tokens.dart --help';

void _printUsage() => stdout.writeln(_usageText());

/// 仓库根: 优先由脚本自身位置推导(tool/ 的上一级), 退化到当前工作目录。
Directory _resolveRepoRoot() {
  final List<Directory> candidates = <Directory>[];
  try {
    final File script = File.fromUri(Platform.script);
    if (script.existsSync()) {
      candidates.add(script.parent.parent);
    }
  } on Object {
    // Platform.script 在快照/特殊执行方式下可能不可用, 忽略。
  }
  candidates.add(Directory.current);
  for (final Directory candidate in candidates) {
    if (Directory('${candidate.path}/$_scanRoot').existsSync() &&
        Directory('${candidate.path}/tool').existsSync()) {
      return candidate.absolute;
    }
  }
  throw _UsageException(
    '找不到仓库根(需要同时存在 $_scanRoot/ 与 tool/), 请在仓库根执行; '
    '已尝试: ${candidates.map((Directory d) => d.path).join(', ')}',
  );
}

String _toPosix(String path) => path.replaceAll(r'\', '/');

String _relativePath(Directory repoRoot, File file) {
  final String root = _toPosix(repoRoot.absolute.path);
  String full = _toPosix(file.absolute.path);
  if (full.startsWith('$root/')) {
    full = full.substring(root.length + 1);
  }
  return full;
}

List<_Violation> _scan(Directory scanDir, String repoRootPath) {
  if (!scanDir.existsSync()) {
    throw _UsageException('扫描目录不存在: ${_toPosix(scanDir.path)}');
  }
  final List<File> files = <File>[];
  for (final FileSystemEntity entity in scanDir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }
  files.sort((File a, File b) => a.path.compareTo(b.path));

  final List<_Violation> violations = <_Violation>[];
  for (final File file in files) {
    final String relativePath =
        _relativePath(Directory(repoRootPath), file);
    if (_whitelistedFiles.contains(relativePath)) {
      continue;
    }
    final List<String> lines = _readLines(file);
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (_isExempt(line) || (i > 0 && _isExempt(lines[i - 1]))) {
        continue;
      }
      for (final _Rule rule in _rules) {
        for (final RegExpMatch match in rule.pattern.allMatches(line)) {
          final String raw = match.namedGroup('lit') ?? match.group(0) ?? '';
          final String literal = raw.replaceAll(RegExp(r'\s+'), '');
          if (literal.isEmpty) continue;
          violations.add(
            _Violation(relativePath, rule.id, literal, i + 1),
          );
        }
      }
    }
  }
  return violations;
}

bool _isExempt(String line) => line.contains(_ignoreMarker);

List<String> _readLines(File file) {
  final String content = file.readAsStringSync();
  return const LineSplitter().convert(content);
}

// ---------------------------------------------------------------------------
// 基线读写
// ---------------------------------------------------------------------------

Map<String, int> _countByKey(List<_Violation> violations) {
  final Map<String, int> counts = <String, int>{};
  for (final _Violation violation in violations) {
    counts[violation.key] = (counts[violation.key] ?? 0) + 1;
  }
  return counts;
}

int _total(Map<String, int> counts) =>
    counts.values.fold<int>(0, (int sum, int v) => sum + v);

_Baseline _readBaseline(File file) {
  if (!file.existsSync()) {
    throw _UsageException(
      '基线文件不存在: $_baselineRelativePath\n'
      '请先执行: dart run tool/check_design_tokens.dart --update-baseline',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw _UsageException(
      '基线文件不是合法 JSON ($_baselineRelativePath): ${error.message}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw _UsageException('基线文件结构非法(顶层应为对象): $_baselineRelativePath');
  }
  final Object? entries = decoded['entries'];
  if (entries is! Map<String, dynamic>) {
    throw _UsageException('基线文件缺少 entries 对象: $_baselineRelativePath');
  }
  final Map<String, int> counts = <String, int>{};
  for (final MapEntry<String, dynamic> entry in entries.entries) {
    final Object? value = entry.value;
    if (value is! int) {
      throw _UsageException(
        '基线条目 "$_baselineRelativePath" -> ${entry.key} 的计数应为整数, '
        '实际是 $value',
      );
    }
    counts[entry.key] = value;
  }
  return _Baseline(counts);
}

void _writeBaseline(File file, Map<String, int> counts) {
  final List<String> keys = counts.keys.toList()..sort();
  final Map<String, int> sorted = <String, int>{
    for (final String key in keys) key: counts[key]!,
  };
  final Map<String, Object?> payload = <String, Object?>{
    'version': _baselineFormatVersion,
    'generatedBy': _baselineGeneratedBy,
    'scan': '$_scanRoot/**/*.dart',
    'keyFormat': '相对路径|规则id|去空白的字面量文本  (value = 出现次数, 与行号无关)',
    'whitelist': _whitelistedFiles.toList()..sort(),
    'rules': <String, String>{
      for (final _Rule rule in _rules) rule.id: rule.description,
    },
    'entries': sorted,
  };
  final String json = '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(json, encoding: utf8, flush: true);
}

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------

void _printRuleTable(Map<String, int> current, Map<String, int> baseline) {
  for (final _Rule rule in _rules) {
    final int now = _ruleTotal(current, rule.id);
    final int base = _ruleTotal(baseline, rule.id);
    final int delta = now - base;
    final String deltaText = delta > 0 ? '+$delta' : '$delta';
    stdout.writeln('  ${rule.id.padRight(14)} 当前 $now / 基线 $base / 差值 $deltaText');
  }
}

int _ruleTotal(Map<String, int> counts, String ruleId) {
  int total = 0;
  for (final MapEntry<String, int> entry in counts.entries) {
    final List<String> parts = entry.key.split('|');
    if (parts.length == 3 && parts[1] == ruleId) {
      total += entry.value;
    }
  }
  return total;
}

String _progressLine(int baseline, int current) =>
    '清零进度: 基线 $baseline 条 -> 当前 $current 条';
