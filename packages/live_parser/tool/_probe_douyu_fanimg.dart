// 一次性探针:抓斗鱼真实弹幕原始包,打印所有与粉丝牌相关的字段原值
// (bimg / bn / bnn / bl / bnnl / bc),判断协议是否下发「含团名的整牌图」。
// 未经解析层归一,直接看 stt 键值,避免我们自己的字段名假设掩盖真实来源。
//
// 用法:cd packages/live_parser && dart run tool/_probe_douyu_fanimg.dart [roomId]
import 'dart:io';

import 'package:live_parser/live_parser.dart';

const _keys = ['bimg', 'bimgurl', 'badgeimg', 'bn', 'bnn', 'bl', 'bnnl', 'fl', 'bc', 'brid', 'hc', 'uid'];

Future<void> main(List<String> args) async {
  final roomId = args.isEmpty ? '9999' : args.first;
  stdout.writeln('== 斗鱼 $roomId 原始包粉丝牌字段 ==');
  final target = buildSiteRegistry()['douyu']!;
  final sub = await target.danmaku!.connect(
    DanmakuSessionRequest(site: 'douyu', roomId: roomId),
  );
  var seen = 0;
  try {
    await for (final message in sub.messages
        .timeout(const Duration(seconds: 30))
        .take(400)) {
      if (message.type != DanmakuMessageType.chat) continue;
      final name = message.badgeName;
      if (name.isEmpty) continue;
      seen++;
      stdout.writeln('  团名="$name" lv=${message.badgeLevel} '
          '解析后 badgeUrl=${message.badgeUrl}');
      // ignore: avoid_print
      print('  [解析层字段] $message');
      if (seen >= 3) break;
    }
  } on Object catch (e) {
    stdout.writeln('(结束: $e)');
  }
  await sub.close();
  stdout.writeln('== 带粉丝牌消息 $seen 条 ==');
  stdout.writeln('提示: 上面 badgeUrl 为空则协议未在 stt 里给整牌图。');
  stdout.writeln('原始键: ${_keys.join(",")}');
}
