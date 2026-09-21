/// 语音字幕条布局:多句**横向排列**、句间留空隙、充分利用播放宽度。
///
/// 用户口径(2026-09-21):句子横排而不是只显示最新一句;每句存活 5s。
/// 存活计时在 [CaptionLineBuffer] 有单测覆盖,这里只锚定「多句同时可见 +
/// 横向排布 + 占满可用宽度」这一视觉契约。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/features/play/application/caption_lines.dart';
import 'package:zishu_flutter/src/features/play/application/speech_caption_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/caption_overlay.dart';
import 'package:speech2zh/speech2zh.dart';

/// 固定状态的字幕 controller:绕开设置/模型/流水线,只验证渲染。
class _FixedCaption extends SpeechCaptionController {
  _FixedCaption(this.fixed) : super((site: 'douyu', roomId: '1'));

  final CaptionUiState fixed;

  @override
  CaptionUiState build() => fixed;
}

Future<void> _pump(
  WidgetTester tester,
  CaptionUiState state, {
  Size size = const Size(1280, 720),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Riverpod 3.4 起 family notifier 的回调式覆写改名为 overrideWith2。
        roomSpeechCaptionProvider.overrideWith2((_) => _FixedCaption(state)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 24,
                right: 24,
                bottom: 68,
                child: CaptionOverlay(site: 'douyu', roomId: '1'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

CaptionUiState _listening(List<String> texts) {
  final buffer = CaptionLineBuffer();
  final base = DateTime(2026, 9, 21, 12);
  for (var i = 0; i < texts.length; i++) {
    buffer.add(texts[i], base.add(Duration(seconds: i)));
  }
  return CaptionUiState(phase: CaptionUiPhase.listening, lines: buffer.lines);
}

void main() {
  testWidgets('多句同时上屏且横向排列(同一行,左句在右句左侧)', (tester) async {
    await _pump(tester, _listening(['第一句', '第二句', '第三句']));

    final first = find.text('第一句');
    final second = find.text('第二句');
    final third = find.text('第三句');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(third, findsOneWidget);

    final r1 = tester.getRect(first);
    final r2 = tester.getRect(second);
    final r3 = tester.getRect(third);
    expect(r2.left, greaterThan(r1.right), reason: '句间应有空隙(不粘连)');
    expect(r3.left, greaterThan(r2.right));
    expect(r1.center.dy, closeTo(r2.center.dy, 1), reason: '同排:纵向中心一致');
  });

  testWidgets('字幕条占满可用宽度(不再限宽 720 居中)', (tester) async {
    await _pump(tester, _listening(['一句比较长的中文字幕内容用于测量']));

    final overlayWidth = tester.getSize(find.byType(CaptionOverlay)).width;
    // 视口 1280 - 两侧各 24 的定位边距 = 1232;旧的 720 上限会明显更窄。
    expect(overlayWidth, greaterThan(1000), reason: '应充分利用播放宽度');
  });

  testWidgets('放不下时折行而不是截断文案', (tester) async {
    await _pump(
      tester,
      _listening(['一句话', '二句话', '三句话', '四句话', '五句话', '六句话']),
      size: const Size(420, 720),
    );

    final rows = <double>{
      for (final text in ['一句话', '二句话', '三句话', '四句话', '五句话', '六句话'])
        tester.getRect(find.text(text)).center.dy.roundToDouble(),
    };
    expect(rows.length, greaterThan(1), reason: '窄容器应折成多行');
    for (final text in ['一句话', '六句话']) {
      expect(find.text(text), findsOneWidget, reason: '$text 不应被丢弃');
    }
  });

  testWidgets('下载中显示百分比与速度(慢速下载不再像卡死)', (tester) async {
    await _pump(
      tester,
      const CaptionUiState(
        phase: CaptionUiPhase.downloading,
        language: SpeechLanguage.english,
        downloadProgress: 0.42,
        downloadBytesPerSecond: 1258291,
      ),
    );

    expect(find.textContaining('英文字幕模型下载中'), findsOneWidget);
    expect(find.textContaining('42%'), findsOneWidget);
    expect(find.textContaining('MB/s'), findsOneWidget);
  });

  testWidgets('文案指明具体语言模型:下载中(韩文)', (tester) async {
    await _pump(
      tester,
      const CaptionUiState(
        phase: CaptionUiPhase.downloading,
        language: SpeechLanguage.korean,
        downloadProgress: 0.15,
      ),
    );
    expect(find.textContaining('韩文字幕模型下载中 15%'), findsOneWidget);
    expect(find.textContaining('英文'), findsNothing);
  });

  testWidgets('文案指明具体语言模型:引擎加载中(英文)', (tester) async {
    await _pump(
      tester,
      const CaptionUiState(
        phase: CaptionUiPhase.loadingModel,
        language: SpeechLanguage.english,
      ),
    );
    expect(find.textContaining('英文字幕引擎加载中'), findsOneWidget);
  });

  testWidgets('尚未确定语言时回退为「字幕…」,不显示 null', (tester) async {
    await _pump(
      tester,
      const CaptionUiState(
        phase: CaptionUiPhase.downloading,
        downloadProgress: 0.5,
      ),
    );
    expect(find.textContaining('字幕模型下载中 50%'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
  });
}
