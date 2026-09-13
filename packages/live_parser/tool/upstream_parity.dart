/// 上游对齐跟踪工具:pure_live ↔ live_parser 平台解析层对照报告。
///
/// 目的:把「移植自 pure_live」的人工流程变成可机械核查的清单 ——
/// 上游改了哪些平台文件、我们在对应平台模块是否需要跟进,一目了然。
///
/// 用法(在 packages/live_parser 下):
/// ```
/// dart run tool/upstream_parity.dart                     # 报告打印到 stdout
/// dart run tool/upstream_parity.dart --since 90          # 最近 90 天(默认 60)
/// dart run tool/upstream_parity.dart --out docs/upstream-parity.md
/// dart run tool/upstream_parity.dart --pure-live F:/project/pure_live
/// ```
///
/// 报告三节:
/// 1. 平台对照矩阵 —— 两侧平台目录、文件数/行数,标记「我们独有 / 上游独有」;
/// 2. 上游近期变更 —— `git log --name-only` 扫 `lib/core/site/` 变更文件,
///    映射到我方平台模块(commit 标题保留,供人工判断语义);
/// 3. 待人工审阅清单 —— 有我方对应模块且近期被上游改过的文件。
///
/// 注意:本工具只读,不改任何文件;pure_live 代码不进入本仓库(AGPL-3.0),
/// 报告里只出现文件名/行数/commit 标题等事实性元数据。
library;

import 'dart:convert';
import 'dart:io';

/// 上游(pure_live)解析层根:`lib/core/site/<platform>/`。
const String _defaultUpstreamRoot = r'F:\project\pure_live\lib\core\site';

/// 上游仓库根(用于 git log)。
const String _defaultUpstreamRepo = r'F:\project\pure_live';

/// 我方平台模块根。
const String _defaultOursRoot =
    r'F:\project\zishu_flutter\packages\live_parser\lib\src\platforms';

/// 默认回看的上游变更窗口(天)。
const int _defaultSinceDays = 60;

/// 平台目录别名:上游目录名 → 我方目录名(目前同名,留作未来改名缓冲)。
const Map<String, String> _aliases = {
  'cc': 'cc', // 我方暂无,报告里标「上游独有」
};

void main(List<String> args) {
  var sinceDays = _defaultSinceDays;
  var upstreamRoot = _defaultUpstreamRoot;
  var upstreamRepo = _defaultUpstreamRepo;
  var oursRoot = _defaultOursRoot;
  String? outPath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--since':
        sinceDays = int.tryParse(args[++i]) ?? _defaultSinceDays;
      case '--pure-live':
        upstreamRoot = args[++i] + r'\lib\core\site';
        upstreamRepo = args[i];
      case '--ours':
        oursRoot = args[++i];
      case '--out':
        outPath = args[++i];
    }
  }

  final upstream = _scanPlatformDir(upstreamRoot);
  final ours = _scanPlatformDir(oursRoot);
  final buffer = StringBuffer()
    ..writeln('# pure_live ↔ live_parser 平台解析层对照报告')
    ..writeln()
    ..writeln('- 生成时间:${DateTime.now()}')
    ..writeln('- 上游根:`$upstreamRoot`')
    ..writeln('- 我方根:`$oursRoot`')
    ..writeln('- 变更窗口:最近 $sinceDays 天')
    ..writeln();

  _writeMatrix(buffer, upstream, ours);
  final changed = _writeUpstreamChanges(
    buffer,
    upstreamRepo,
    sinceDays,
    upstream.keys.toSet(),
  );
  _writeReviewList(buffer, changed, upstream, ours);

  final report = buffer.toString();
  if (outPath == null) {
    stdout.write(report);
  } else {
    File(outPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(report);
    stdout.writeln('报告已写入 $outPath');
  }
}

/// 平台目录扫描:{平台名 → (文件数, 行数)}。
Map<String, (int, int)> _scanPlatformDir(String root) {
  final result = <String, (int, int)>{};
  final dir = Directory(root);
  if (!dir.existsSync()) {
    stderr.writeln('警告:目录不存在 $root');
    return result;
  }
  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    var files = 0;
    var lines = 0;
    for (final f in Directory(entity.path)
        .listSync(recursive: true)
        .whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      files++;
      lines += f.readAsLinesSync().length;
    }
    result[entity.uri.pathSegments.reversed.skip(1).first] = (files, lines);
  }
  return result;
}

/// 第一节:平台对照矩阵。
void _writeMatrix(
  StringBuffer out,
  Map<String, (int, int)> upstream,
  Map<String, (int, int)> ours,
) {
  out
    ..writeln('## 一、平台对照矩阵')
    ..writeln()
    ..writeln('| 平台 | 上游(文件/行) | 我方(文件/行) | 归属 |')
    ..writeln('|---|---|---|---|');
  final platforms = {...upstream.keys, ...ours.keys}.toList()..sort();
  for (final platform in platforms) {
    final up = upstream[platform];
    final our = ours[platform];
    final ownership = up == null
        ? '我方独有'
        : our == null
            ? '上游独有(缺失)'
            : '共有';
    String cell((int, int)? stat) =>
        stat == null ? '—' : '${stat.$1} 文件 / ${stat.$2} 行';
    out.writeln('| $platform | ${cell(up)} | ${cell(our)} | $ownership |');
  }
  out..writeln()..writeln('> 「上游独有」是候选移植项;「我方独有」无需对照。');
}

/// 第二节:上游近期变更(git log --name-only),返回 (平台, 文件, commit 标题)。
List<(String, String, String)> _writeUpstreamChanges(
  StringBuffer out,
  String repo,
  int sinceDays,
  Set<String> upstreamPlatforms,
) {
  out..writeln()..writeln('## 二、上游近期变更(lib/core/site/)')..writeln();
  final since = DateTime.now().subtract(Duration(days: sinceDays));
  final iso = since.toIso8601String().substring(0, 10);
  ProcessResult result;
  try {
    result = Process.runSync(
      'git',
      [
        '-C', repo,
        'log',
        '--since=$iso',
        '--name-only',
        '--pretty=format:__COMMIT__%s',
      ],
      // git 输出恒为 UTF-8;不显式指定时 Dart 按系统 GBK 解码,中文标题变乱码。
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } catch (error) {
    out.writeln('> git 不可用:$error');
    return const [];
  }
  if (result.exitCode != 0) {
    out.writeln('> git log 失败(exit ${result.exitCode}):'
        '${result.stderr}')
    ;
    return const [];
  }

  final changed = <(String, String, String)>[];
  var commit = '';
  for (final line in (result.stdout as String).split('\n')) {
    final text = line.trim();
    if (text.isEmpty) continue;
    if (text.startsWith('__COMMIT__')) {
      commit = text.substring('__COMMIT__'.length);
      continue;
    }
    final normalized = text.replaceAll('\\', '/');
    const prefix = 'lib/core/site/';
    if (!normalized.startsWith(prefix)) continue;
    final rest = normalized.substring(prefix.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) continue;
    final platform = _aliases[rest.substring(0, slash)] ??
        rest.substring(0, slash);
    if (!upstreamPlatforms.contains(platform)) continue;
    changed.add((platform, rest.substring(slash + 1), commit));
  }

  if (changed.isEmpty) {
    out.writeln('> 窗口内 lib/core/site/ 无变更。');
    return changed;
  }
  out.writeln('| 平台 | 文件 | 上游 commit 标题 |');
  out.writeln('|---|---|---|');
  for (final (platform, file, title) in changed) {
    out.writeln('| $platform | $file | $title |');
  }
  return changed;
}

/// 第三节:待人工审阅清单(有我方对应模块且近期被上游改过)。
void _writeReviewList(
  StringBuffer out,
  List<(String, String, String)> changed,
  Map<String, (int, int)> upstream,
  Map<String, (int, int)> ours,
) {
  out..writeln()..writeln('## 三、待人工审阅清单')..writeln();
  final relevant = changed
      .where((entry) => ours.containsKey(entry.$1))
      .map((entry) => entry.$1)
      .toSet()
      .toList()
    ..sort();
  if (relevant.isEmpty) {
    out.writeln('> 窗口内无需跟进:上游改动只落在了我方尚无对应模块的平台。');
    return;
  }
  out.writeln('以下平台在上游窗口内有解析层变更,且我方存在对应模块,'
      '逐个人工比对语义(抄契约不抄代码,注意 AGPL 边界):');
  for (final platform in relevant) {
    final up = upstream[platform]!;
    final our = ours[platform]!;
    final delta = up.$2 - our.$2;
    out.writeln(
      '- **$platform**:上游 ${up.$1} 文件/${up.$2} 行,'
      '我方 ${our.$1} 文件/${our.$2} 行(行数差 ${delta >= 0 ? '+' : ''}$delta)',
    );
  }
}
