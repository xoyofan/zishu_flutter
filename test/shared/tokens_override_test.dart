import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/shared/presentation/tokens_override.dart';
import 'package:zishu_flutter/src/shared/presentation/zishu_tokens.dart';

/// 临时 override 文件目录(每个用例独立,addTearDown 清理)。
Future<Directory> _tempDir() async {
  final dir = await Directory.systemTemp.createTemp('zishu_tokens_test');
  return dir;
}

/// 合法 override JSON(可只带部分字段)。
String _overrideJson(Map<String, Object?> dark, Map<String, Object?> light) =>
    jsonEncode({'schema': 1, 'dark': dark, 'light': light});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseZishuTokensJson', () {
    test('完整字段解析为颜色补丁', () {
      final patch = parseZishuTokensJson(
        _overrideJson({'background': '#FF181818'}, {'accent': '#FF6A1B9A'}),
      );
      expect(patch.dark, {'background': const Color(0xFF181818)});
      expect(patch.light, {'accent': const Color(0xFF6A1B9A)});
    });

    test('#RRGGBB 六位补 alpha FF,#AARRGGBB 八位原样', () {
      final patch = parseZishuTokensJson(
        _overrideJson({'surface': '#1F1F1F', 'border': '#ff3a3a3a'}, const {}),
      );
      expect(patch.dark['surface'], const Color(0xFF1F1F1F));
      expect(patch.dark['border'], const Color(0xFF3A3A3A));
    });

    test('未知字段忽略(前向兼容),主题段可缺省', () {
      final patch = parseZishuTokensJson(
        _overrideJson({'noSuchField': '#FF000000', 'brand': '#FFF3D04E'}, {}),
      );
      expect(patch.dark, {'brand': const Color(0xFFF3D04E)});
      expect(patch.light, isEmpty);
    });

    test('已知字段值非法 → 整文件拒绝', () {
      expect(
        () =>
            parseZishuTokensJson(_overrideJson({'accent': '#12345'}, const {})),
        throwsA(isA<ZishuTokensFormatException>()),
      );
      expect(
        () => parseZishuTokensJson(_overrideJson({'accent': 123}, const {})),
        throwsA(isA<ZishuTokensFormatException>()),
      );
    });

    test('schema 缺失 / 不符 → 拒绝', () {
      expect(
        () => parseZishuTokensJson('{"dark": {}}'),
        throwsA(isA<ZishuTokensFormatException>()),
      );
      expect(
        () => parseZishuTokensJson(
          jsonEncode({'schema': 2, 'dark': {}, 'light': {}}),
        ),
        throwsA(isA<ZishuTokensFormatException>()),
      );
    });

    test('顶层不是对象 / JSON 语法错误 → 拒绝', () {
      expect(
        () => parseZishuTokensJson('[]'),
        throwsA(isA<ZishuTokensFormatException>()),
      );
      expect(
        () => parseZishuTokensJson('{bad'),
        throwsA(isA<ZishuTokensFormatException>()),
      );
    });

    test('空对象 → 空补丁', () {
      final patch = parseZishuTokensJson(_overrideJson(const {}, const {}));
      expect(patch.isEmpty, isTrue);
    });
  });

  group('applyZishuTokensPatch', () {
    test('部分字段叠加,其余保持基线', () {
      final patch = ZishuTokensPatch(dark: {'accent': const Color(0xFF112233)});
      final set = applyZishuTokensPatch(ZishuTokenSet.codeDefaults, patch);
      expect(set.dark.accent, const Color(0xFF112233));
      // 未覆盖字段逐位保持基线。
      expect(set.dark.background, ZishuTokens.dark.background);
      expect(set.dark.brand, ZishuTokens.dark.brand);
      expect(set.light.accent, ZishuTokens.light.accent);
    });

    test('空补丁返回基线实例', () {
      final base = ZishuTokenSet.codeDefaults;
      expect(applyZishuTokensPatch(base, const ZishuTokensPatch()), same(base));
    });
  });

  group('resolveZishuTokenSet(启动链)', () {
    test('无外部文件 → 打包内 JSON 叠加代码常量 = 代码常量', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final set = await resolveZishuTokenSet(
        overridePath: '${dir.path}\\tokens.json',
      );
      expect(set.dark.background, ZishuTokens.dark.background);
      expect(set.dark.accent, ZishuTokens.dark.accent);
      expect(set.light.background, ZishuTokens.light.background);
      expect(
        set.light.playSuperTextActive,
        ZishuTokens.light.playSuperTextActive,
      );
    });

    test('外部 override 叠加在打包默认之上,缺省字段保持', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}\\tokens.json');
      await file.writeAsString(
        _overrideJson({'accent': '#FF2468AC'}, {'success': '#FF00AA00'}),
      );
      final set = await resolveZishuTokenSet(overridePath: file.path);
      expect(set.dark.accent, const Color(0xFF2468AC));
      expect(set.dark.background, ZishuTokens.dark.background);
      expect(set.light.success, const Color(0xFF00AA00));
      expect(set.light.error, ZishuTokens.light.error);
    });

    test('外部 override 非法 → 回退打包默认(不抛)', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}\\tokens.json');
      await file.writeAsString('{oops');
      final set = await resolveZishuTokenSet(overridePath: file.path);
      expect(set.dark.accent, ZishuTokens.dark.accent);
    });
  });

  group('reloadExternalZishuTokens(热更链)', () {
    test('无外部文件 → null(保持现值)', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final set = await reloadExternalZishuTokens(
        overridePath: '${dir.path}\\tokens.json',
      );
      expect(set, isNull);
    });

    test('有合法 override → 基线 + 补丁的新 set', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}\\tokens.json');
      await file.writeAsString(_overrideJson({'brand': '#FFABCDEF'}, const {}));
      final set = await reloadExternalZishuTokens(overridePath: file.path);
      expect(set, isNotNull);
      expect(set!.dark.brand, const Color(0xFFABCDEF));
      expect(set.dark.accent, ZishuTokens.dark.accent);
    });

    test('非法 override → null(不把运行中界面打回默认)', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}\\tokens.json');
      await file.writeAsString('{"schema": 1, "dark": {"accent": "#zz"}}');
      final set = await reloadExternalZishuTokens(overridePath: file.path);
      expect(set, isNull);
    });
  });

  group('ZishuTokensReloader', () {
    test('override 文件变更 → 去抖后广播叠加后的新 set', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}\\tokens.json');
      // 先放一版旧内容,再 start 监听:建立监听不应回放历史状态。
      await file.writeAsString(
        _overrideJson({'accent': '#FF111111'}, const {}),
      );

      final reloader = ZishuTokensReloader();
      addTearDown(reloader.stop);
      final newAccent = const Color(0xFF445566);
      final completer = Completer<ZishuTokenSet>();
      final sub = reloader.changes
          .where((set) => set.dark.accent == newAccent)
          .listen(completer.complete);
      addTearDown(sub.cancel);

      reloader.start(overridePath: file.path);
      expect(reloader.isActive, isTrue);
      // 监听建立留出余量,再触发文件变更。
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await file.writeAsString(
        _overrideJson({'accent': '#FF445566', 'error': '#FF000000'}, const {}),
      );

      final set = await completer.future.timeout(const Duration(seconds: 10));
      expect(set.dark.accent, newAccent);
      // 同文件里的其他字段一并生效;未覆盖字段保持代码基线。
      expect(set.dark.error, const Color(0xFF000000));
      expect(set.dark.background, ZishuTokens.dark.background);
    });

    test('重复 start 幂等,stop 后可再 start', () {
      final reloader = ZishuTokensReloader();
      addTearDown(reloader.stop);
      reloader.start(overridePath: 'X:\\no\\such\\dir\\tokens.json');
      reloader.start(overridePath: 'X:\\no\\such\\dir\\tokens.json');
      reloader.stop();
      expect(reloader.isActive, isFalse);
      reloader.start(overridePath: 'X:\\no\\such\\dir\\tokens.json');
    });
  });

  group('encodeZishuTokensJson', () {
    test('编码 → 解析 roundtrip 不丢不改', () {
      final encoded = encodeZishuTokensJson(ZishuTokenSet.codeDefaults);
      final patch = parseZishuTokensJson(encoded);
      final rebuilt = applyZishuTokensPatch(ZishuTokenSet.codeDefaults, patch);
      expect(rebuilt.dark.background, ZishuTokens.dark.background);
      expect(rebuilt.dark.barrier, ZishuTokens.dark.barrier);
      expect(
        rebuilt.dark.playFollowTextActive,
        ZishuTokens.dark.playFollowTextActive,
      );
      expect(rebuilt.light.textSecondary, ZishuTokens.light.textSecondary);
      expect(rebuilt.light.promoBadge, ZishuTokens.light.promoBadge);
    });
  });
}
