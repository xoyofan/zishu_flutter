import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show DanmakuMessage, DanmakuMessageType, DanmakuSegment;
import 'package:zishu_flutter/src/features/danmaku/domain/danmaku_style.dart';
import 'package:zishu_flutter/src/features/danmaku/domain/danmaku_track.dart';

/// 构造一条最小可用的弹幕消息。
DanmakuMessage msg({
  String text = '弹幕',
  String userName = '水友',
  int color = 0,
  List<DanmakuSegment> segments = const [],
}) {
  return DanmakuMessage(
    type: DanmakuMessageType.chat,
    userName: userName,
    userId: 'u1',
    text: text,
    color: color,
    segments: segments,
  );
}

void main() {
  group('DanmakuStyle.resolveColor 颜色归一', () {
    test('color == 0 使用默认弹幕色', () {
      expect(DanmakuStyle.resolveColor(0), DanmakuStyle.defaultTextColor);
      expect(DanmakuStyle.defaultTextColor.a, 1.0, reason: '默认色必须不透明');
    });

    test('0xRRGGBB 补满 alpha 后解析', () {
      expect(DanmakuStyle.resolveColor(0xFF0000), const Color(0xFFFF0000));
      expect(DanmakuStyle.resolveColor(0x00FF00), const Color(0xFF00FF00));
      expect(DanmakuStyle.resolveColor(0x123456), const Color(0xFF123456));
    });

    test('解析结果始终不透明,且高 8 位被忽略', () {
      final c = DanmakuStyle.resolveColor(0xFFABCDEF);
      expect(c.a, 1.0);
      expect(c, const Color(0xFFABCDEF));
      // 传入带非法高位的值也只取低 24 位。
      expect(DanmakuStyle.resolveColor(0x7F00FF00), const Color(0xFF00FF00));
    });

    test('用户名着色:指定颜色时统一用消息色,默认时按 hash 稳定', () {
      final colored = msg(color: 0xFF0000);
      expect(DanmakuStyle.resolveUserNameColor(colored), const Color(0xFFFF0000));

      final a = msg(userName: '星河不入梦');
      final b = msg(userName: '星河不入梦');
      expect(DanmakuStyle.resolveUserNameColor(a),
          DanmakuStyle.resolveUserNameColor(b),
          reason: '同一用户名应稳定同色');
      // 与正文色区分(默认用户名带色相,正文纯白)。
      expect(DanmakuStyle.resolveUserNameColor(a),
          isNot(DanmakuStyle.defaultTextColor));
    });
  });

  group('DanmakuStyle 富文本构建', () {
    test('用户名 + 正文两段,样式不同', () {
      // 用户口径 2026-09-19:飘屏只画正文,不显示昵称(对齐 web
      // DanmakuOverlay 语义),buildSpan 输出单段纯正文。
      final span = DanmakuStyle.buildSpan(msg(userName: '阿星', text: '你好'));
      expect(span.text, '你好', reason: '飘屏不应包含昵称前缀');
      expect(span.children, isNull);
      expect(span.style, isNotNull);
    });

    test('空用户名同样只输出正文', () {
      final span = DanmakuStyle.buildSpan(msg(userName: '', text: '仅正文'));
      expect(span.text, '仅正文');
    });

    test('segments 非空:表情段以「[表情名]」文本参与,不做图片内联', () {
      // 飘屏绘制走 ParagraphBuilder 纯文本(_buildParagraph),表情段只能以
      // 「[表情名]」括号文本参与,children 里不得出现 WidgetSpan/图片。
      final span = DanmakuStyle.buildSpan(msg(
        text: '哈哈[捂脸]真逗',
        segments: const [
          DanmakuSegment.text('哈哈'),
          DanmakuSegment.emoji(
            text: '[捂脸]',
            url: 'https://example.com/emote/rou.png',
          ),
          DanmakuSegment.text('真逗'),
        ],
      ));
      expect(span.text, isNull, reason: '多段形态:根 span 只带样式不带 text');
      expect(span.children, isNotNull);
      for (final child in span.children!) {
        expect(child, isA<TextSpan>(), reason: '飘屏不做图片内联,全部为 TextSpan');
      }
      final joined = span.children!
          .map((child) => (child as TextSpan).text ?? '')
          .join();
      expect(joined, '哈哈[捂脸]真逗', reason: '各段文本拼接应与 message.text 一致');
      expect(joined, contains('[捂脸]'), reason: '表情段以「[表情名]」括号形态参与');
      // 每段显式携带正文样式(颜色/字号),ParagraphBuilder 填充不回退引擎默认黑。
      for (final child in span.children!) {
        final segmentSpan = child as TextSpan;
        expect(segmentSpan.style?.fontSize, DanmakuStyle.fontSize);
        expect(segmentSpan.style?.color, DanmakuStyle.defaultTextColor);
      }
      // 多段结构可正常测量宽度(不回归飘屏空白)。
      expect(DanmakuStyle.measureWidth(span), greaterThan(0));
    });

    test('segments 非空且消息带色:各段样式跟随消息色', () {
      final span = DanmakuStyle.buildSpan(msg(
        text: '红色弹幕',
        color: 0xFF0000,
        segments: const [
          DanmakuSegment.text('红色'),
          DanmakuSegment.emoji(text: '[色]'),
          DanmakuSegment.text('弹幕'),
        ],
      ));
      for (final child in span.children!) {
        expect((child as TextSpan).style?.color, const Color(0xFFFF0000),
            reason: '所有正文段(含表情文本段)应与消息色一致');
      }
    });
  });

  group('DanmakuStyle 段落布局(飘屏空白回归防护)', () {
    test('单段纯正文经 _buildParagraph 布局后 maxIntrinsicWidth > 0', () {
      // 回归:buildSpan 改为单段(根 span 持 text、无 children)后,
      // _buildParagraph 若仍只遍历 children,ParagraphBuilder 零字符,
      // 飘屏整条空白。measureWidth 必须测出实际宽度。
      final span = DanmakuStyle.buildSpan(msg(text: '这条弹幕必须有宽度'));
      expect(span.text, isNotEmpty);
      expect(DanmakuStyle.measureWidth(span), greaterThan(0));
    });

    test('自定义字号(A3 注入)下单段 span 仍可测量出宽度', () {
      final span = DanmakuStyle.buildSpan(msg(text: '大字号弹幕'), fontSize: 28);
      expect(DanmakuStyle.measureWidth(span), greaterThan(0));
    });

    test('旧两段结构(带 children)仍兼容:嵌套正文计入宽度', () {
      // 兼容历史富文本形态:根 span 无 text,children 为昵称 + 正文。
      final body = DanmakuStyle.buildSpan(msg(text: '正文部分'));
      final legacy = TextSpan(
        children: [
          TextSpan(
            text: '昵称:',
            style: body.style,
          ),
          body,
        ],
      );
      expect(legacy.text, isNull);
      final legacyWidth = DanmakuStyle.measureWidth(legacy);
      expect(legacyWidth, greaterThan(DanmakuStyle.measureWidth(body)),
          reason: '昵称段宽度应叠加在正文之上');
    });

    test('paintRichText 对单段 span 做描边 + 填充两遍绘制不抛异常', () {
      final span = DanmakuStyle.buildSpan(msg(text: '描边填充'));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      DanmakuStyle.paintRichText(canvas, span, offset: ui.Offset.zero);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
      picture.dispose();
    });
  });

  group('DanmakuTrackAllocator 轨道分配', () {
    test('初始所有 lane 可立即分配,且不重叠', () {
      final alloc = DanmakuTrackAllocator(laneCount: 3, durationSeconds: 8);
      expect(alloc.freeLaneCount(0), 3);

      final a = alloc.tryAllocate(0, 0.2);
      final b = alloc.tryAllocate(0, 0.2);
      final c = alloc.tryAllocate(0, 0.2);
      expect({a, b, c}, {0, 1, 2}, reason: '同一时刻三条弹幕应分到不同 lane');

      // 第四条:所有 lane 都忙,返回 null(O(1) 判定,不做两两比较)。
      expect(alloc.tryAllocate(0, 0.2), isNull);
    });

    test('O(1) 判定:lane 满时立即返回 null,不需等待', () {
      final alloc = DanmakuTrackAllocator(
        laneCount: 2,
        durationSeconds: 10,
        gapSeconds: 0,
      );
      alloc.tryAllocate(0, 0.5);
      alloc.tryAllocate(0, 0.5);
      // lane 尾端离场时刻 = 0 + 10 * (1 + 0.5) = 15s;
      // 另有宽弹幕安全间隙 gap = 0 + 0.5*10*0.25 = 1.25s,即 16.25s 可复用。
      expect(alloc.tryAllocate(1.0, 0.5), isNull, reason: '1s 时两条 lane 仍被占');
      expect(alloc.tryAllocate(14.9, 0.5), isNull);
      expect(alloc.tryAllocate(16.25, 0.5), 0, reason: '尾端离场 + 间隙后 lane0 释放');
    });

    test('无可用 lane 时复用最早释放的 lane', () {
      final alloc = DanmakuTrackAllocator(
        laneCount: 2,
        durationSeconds: 4,
        gapSeconds: 0,
      );
      // lane0 占用:释放 4*(1+0.1)=4.4s;lane1:4*(1+0.5)=6.0s。
      expect(alloc.tryAllocate(0, 0.1), 0);
      expect(alloc.tryAllocate(0, 0.5), 1);
      expect(alloc.tryAllocate(0, 0.1), isNull);
      // 最早释放的是 lane0(4.4 < 6.0)。
      expect(alloc.allocateReusingEarliest(0, 0.1), 0);
    });

    test('安全间隙:同 lane 需等尾弹幕离场后再入', () {
      final alloc = DanmakuTrackAllocator(
        laneCount: 1,
        durationSeconds: 8,
        gapSeconds: 1.0,
      );
      expect(alloc.tryAllocate(0, 0.1), 0);
      // 尾端离场 = 0 + 8*(1+0.1) + gap(1 + 0.1*8*0.25=0.2) = 8.8 + 1.2 = 10.0
      expect(alloc.tryAllocate(9.0, 0.1), isNull);
      expect(alloc.tryAllocate(10.0, 0.1), 0);
    });

    test('lanesForHeight 按行高换算,至少 1 条且封顶', () {
      expect(DanmakuTrackAllocator.lanesForHeight(280, 28), 10);
      expect(DanmakuTrackAllocator.lanesForHeight(10, 28), 1);
      expect(DanmakuTrackAllocator.lanesForHeight(9999, 28, max: 12), 12);
    });

    test('laneCount 必须为正(构造断言)', () {
      expect(
        () => DanmakuTrackAllocator(laneCount: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
