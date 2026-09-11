import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show DanmakuMessage, DanmakuMessageType;
import 'package:zishu_flutter/src/features/danmaku/widgets/danmaku_overlay.dart';

DanmakuMessage _msg(String text, {int color = 0, String userName = '水友'}) {
  return DanmakuMessage(
    type: DanmakuMessageType.chat,
    userName: userName,
    userId: 'u1',
    text: text,
    color: color,
  );
}

/// 固定帧数 pump(动画流不会 settle,约束禁止 pumpAndSettle)。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pumpOverlay(
  WidgetTester tester,
  Stream<DanmakuMessage>? stream, {
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 360,
          child: DanmakuOverlay(messages: stream, enabled: enabled),
        ),
      ),
    ),
  );
  await _pumpFrames(tester);
}

void main() {
  testWidgets('DanmakuOverlay 挂载后拥有稳定锚点且不抛异常', (tester) async {
    final controller = StreamController<DanmakuMessage>.broadcast();
    await _pumpOverlay(tester, controller.stream);

    expect(find.byKey(const Key('danmaku-overlay')), findsOneWidget);

    controller.add(_msg('来了来了', userName: '星河不入梦'));
    controller.add(_msg('这波可以', color: 0xFF0000, userName: '奶茶'));
    await _pumpFrames(tester);

    // 推入弹幕后持续滚动多帧仍不抛异常。
    await _pumpFrames(tester, frames: 30);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('danmaku-overlay')), findsOneWidget);

    await controller.close();
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空流 / null 数据源安全挂载', (tester) async {
    await _pumpOverlay(tester, null);
    expect(find.byKey(const Key('danmaku-overlay')), findsOneWidget);

    final controller = StreamController<DanmakuMessage>.broadcast();
    await _pumpOverlay(tester, controller.stream);
    await controller.close();
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabled=false 时不抛异常,重新启用后仍可滚动', (tester) async {
    final controller = StreamController<DanmakuMessage>.broadcast();
    await _pumpOverlay(tester, controller.stream, enabled: false);
    controller.add(_msg('暂停态弹幕'));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);

    await _pumpOverlay(tester, controller.stream);
    controller.add(_msg('恢复态弹幕'));
    await _pumpFrames(tester, frames: 20);
    expect(tester.takeException(), isNull);

    await controller.close();
  });

  testWidgets('弹幕流出错不影响挂载', (tester) async {
    final controller = StreamController<DanmakuMessage>();
    await _pumpOverlay(tester, controller.stream);
    controller.addError(StateError('upstream failed'));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);

    await controller.close();
  });

  testWidgets('dispose 时取消订阅,关闭流后再推送不抛异常', (tester) async {
    final controller = StreamController<DanmakuMessage>.broadcast();
    await _pumpOverlay(tester, controller.stream);
    controller.add(_msg('挂载期弹幕'));
    await _pumpFrames(tester);

    // 卸载 overlay。
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await _pumpFrames(tester);

    // 卸载后再推送:订阅已取消,不应触发 setState after dispose。
    controller.add(_msg('卸载后弹幕'));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);

    await controller.close();
  });
}
