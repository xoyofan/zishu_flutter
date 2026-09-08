import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/engine/danmaku/danmaku_channel.dart';
import 'package:zishu_flutter/engine/danmaku/danmaku_channel_resolver.dart';
import 'package:zishu_flutter/engine/danmaku/danmaku_message.dart';
import 'package:zishu_flutter/engine/remote/remote_danmaku_source.dart';

/// 可控的假通道：connect/disconnect 状态与事件发射由测试驱动。
class FakeChannel implements DanmakuChannel {
  FakeChannel(this.site);

  @override
  final String site;

  final messagesController = StreamController<DanmakuMessage>.broadcast();
  final statesController = StreamController<DanmakuChannelState>.broadcast();

  List<String> connectedRooms = [];
  int disconnectCount = 0;

  @override
  Stream<DanmakuMessage> get messages => messagesController.stream;

  @override
  Stream<DanmakuChannelState> get states => statesController.stream;

  @override
  Future<void> connect({required String roomId}) async {
    connectedRooms.add(roomId);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
  }

  void emit(DanmakuMessage message) => messagesController.add(message);

  void emitState(DanmakuChannelState state) => statesController.add(state);
}

class FakeResolver extends DanmakuChannelResolver {
  FakeResolver(this.channel);

  FakeChannel channel;

  @override
  DanmakuChannel resolve(
    String site, {
    Map<String, dynamic>? playbackConfig,
    String? streamApiBaseUrl,
  }) =>
      channel;
}

DanmakuMessage message(String text) =>
    DanmakuMessage(user: 'u', text: text);

void main() {
  test('start 连接并把通道消息桥接到 onMessage，ready 触发 onReady', () async {
    final channel = FakeChannel('douyu');
    final source = RemoteDanmakuSource(
      site: 'douyu',
      resolver: FakeResolver(channel),
    );
    var readyCount = 0;
    final received = <String>[];
    source.onReady = () => readyCount += 1;
    source.onMessage = (m) => received.add(m.text);

    await source.start(room: '123');
    expect(channel.connectedRooms, ['123']);

    channel.emitState(DanmakuChannelState.ready);
    channel.emit(message('hello'));
    channel.emit(message('world'));
    await Future<void>.delayed(Duration.zero);

    expect(readyCount, 1);
    expect(received, ['hello', 'world']);
    expect(source.isConnected, isTrue);
    await source.stop();
  });

  test('切房：旧通道被 disconnect，旧通道迟到消息被 fence 丢弃', () async {
    final channelA = FakeChannel('douyu');
    final channelB = FakeChannel('douyu');
    final resolver = FakeResolver(channelA);
    final source = RemoteDanmakuSource(site: 'douyu', resolver: resolver);
    final received = <String>[];
    source.onMessage = (m) => received.add(m.text);

    await source.start(room: '111');
    expect(channelA.connectedRooms, ['111']);

    // 切到新房：resolver 换成返回 channelB。
    resolver.channel = channelB;
    await source.start(room: '222');
    expect(channelB.connectedRooms, ['222']);
    expect(channelA.disconnectCount, 1);

    // 旧通道迟到消息不应进新房（已退订 + generation fence）。
    channelA.emit(message('stale'));
    channelB.emit(message('fresh'));
    await Future<void>.delayed(Duration.zero);
    expect(received, ['fresh']);
    await source.stop();
  });

  test('reconnecting/closed 状态触发 onClose（且不重复通知），ready 恢复复位', () async {
    final channel = FakeChannel('douyu');
    final source = RemoteDanmakuSource(
      site: 'douyu',
      resolver: FakeResolver(channel),
    );
    final closedMessages = <String>[];
    source.onClose = (msg) => closedMessages.add(msg);

    await source.start(room: '1');
    channel.emitState(DanmakuChannelState.ready);
    await Future<void>.delayed(Duration.zero);

    channel.emitState(DanmakuChannelState.reconnecting);
    channel.emitState(DanmakuChannelState.reconnecting);
    await Future<void>.delayed(Duration.zero);
    expect(closedMessages, hasLength(1));
    expect(source.isConnected, isFalse);

    // 重连成功恢复 ready 后再次中断，应能再次通知。
    channel.emitState(DanmakuChannelState.ready);
    channel.emitState(DanmakuChannelState.closed);
    await Future<void>.delayed(Duration.zero);
    expect(closedMessages, hasLength(2));
    await source.stop();
  });

  test('stop 后回调静默且通道断开', () async {
    final channel = FakeChannel('douyu');
    final source = RemoteDanmakuSource(
      site: 'douyu',
      resolver: FakeResolver(channel),
    );
    var messageCount = 0;
    source.onMessage = (_) => messageCount += 1;

    await source.start(room: '42');
    await source.stop();
    expect(channel.disconnectCount, 1);
    expect(source.isConnected, isFalse);

    channel.emit(message('after stop'));
    await Future<void>.delayed(Duration.zero);
    expect(messageCount, 0);
  });
}
