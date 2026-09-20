/// TranslatedText / translatedTextProvider 的 widget 测试:
/// 开关门控、原文先显示译文到达替换、已是中文不打引擎。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/shared/application/translation/translation_coordinator.dart';
import 'package:zishu_flutter/src/shared/application/translation/translation_provider.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/translated_text.dart';

void main() {
  testWidgets('开启翻译:原文先显示,译文到达后替换', (tester) async {
    final gate = Completer<void>();
    final harness = _pumpHarness(
      translationEnabled: true,
      engineResult: () => gate.isCompleted ? '你好世界' : null,
      gate: gate,
    );
    await tester.pumpWidget(harness);
    // 译文未到:显示原文。
    expect(find.text('hello world'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('你好世界'), findsOneWidget);
    expect(find.text('hello world'), findsNothing);
  });

  testWidgets('关闭翻译:恒显示原文,引擎不被调用', (tester) async {
    var engineCalls = 0;
    final harness = _pumpHarness(
      translationEnabled: false,
      engineResult: () {
        engineCalls++;
        return '不应出现';
      },
    );
    await tester.pumpWidget(harness);
    await tester.pumpAndSettle();
    expect(find.text('hello world'), findsOneWidget);
    expect(engineCalls, 0);
  });

  testWidgets('文本已是中文:显示原文且不打引擎', (tester) async {
    var engineCalls = 0;
    final harness = _pumpHarness(
      translationEnabled: true,
      engineResult: () {
        engineCalls++;
        return null;
      },
      text: '纯中文标题',
    );
    await tester.pumpWidget(harness);
    await tester.pumpAndSettle();
    expect(find.text('纯中文标题'), findsOneWidget);
    expect(engineCalls, 0);
  });
}

/// 组装 ProviderScope:固定设置(开关/实例地址) + fake 引擎协调器。
Widget _pumpHarness({
  required bool translationEnabled,
  required String? Function() engineResult,
  Completer<void>? gate,
  String text = 'hello world',
}) {
  final coordinator = TranslationCoordinator(
    engines: [
      _FakeEngine(engineResult, onCall: () => gate?.future ?? Future.value()),
    ],
  );
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        () => _FixedSettingsController(enabled: translationEnabled),
      ),
      translationCoordinatorProvider.overrideWith((ref) => coordinator),
    ],
    child: MaterialApp(
      home: Scaffold(body: _TextSlot(text: text)),
    ),
  );
}

class _TextSlot extends ConsumerWidget {
  const _TextSlot({required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 与生产挂接同链路:经 translatedTextProvider 取译文。
    return TranslatedText(text, style: const TextStyle(fontSize: 14));
  }
}

/// 固定态设置控制器:跳过持久化恢复,build 即返回目标状态。
class _FixedSettingsController extends SettingsController {
  _FixedSettingsController({required bool enabled})
    : _translationEnabled = enabled;

  final bool _translationEnabled;

  @override
  SettingsState build() {
    return SettingsState(
      themeMode: ThemeModeChoice.dark,
      defaultQuality: '超清',
      danmakuEnabled: true,
      chatEnabled: true,
      preferredLineFormat: PreferredLineFormat.auto,
      serverUrl: SettingsState.defaultServerUrl,
      translationEnabled: _translationEnabled,
      hydrated: true,
    );
  }
}

class _FakeEngine implements TranslationEngine {
  _FakeEngine(this.compute, {this.onCall});

  final String? Function() compute;
  final Future<void> Function()? onCall;

  @override
  Future<String?> translate(String text) async {
    final hook = onCall;
    if (hook != null) await hook();
    return compute();
  }
}
