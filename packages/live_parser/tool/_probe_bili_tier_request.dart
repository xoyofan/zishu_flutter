// 一次性探针:验证 B 站按档请求(qn=...)返回对应 current_qn 的流。
import 'package:live_parser/src/platforms/bilibili/bilibili_site.dart';
import 'package:live_parser/src/platforms/bilibili/room_api.dart';
import 'package:live_parser/src/platforms/douyu/json_utils.dart';

Future<void> main() async {
  final client = BilibiliClient();
  try {
    for (final qn in const [10000, 400, 250, 150, 80]) {
      final data = await fetchBilibiliRoomPlayInfo(
        client.parserHttp,
        client.credentials,
        '7734200',
        qn: qn,
      );
      final playurl = jsonMapOf(jsonMapOf(data['playurl_info'])['playurl']);
      final currentQns = <int>{};
      for (final stream in jsonListOf(playurl['stream']).whereType<Map<String, dynamic>>()) {
        for (final format in jsonListOf(stream['format']).whereType<Map<String, dynamic>>()) {
          for (final codec in jsonListOf(format['codec']).whereType<Map<String, dynamic>>()) {
            currentQns.add(jsonInt(codec['current_qn']));
          }
        }
      }
      final lines = bilibiliTierLines(data, qn);
      // ignore: avoid_print
      print('request qn=$qn -> current_qn=$currentQns '
          'accept=${bilibiliAvailableQualities(data).map((q) => q.qn).toList()} '
          'lines=${lines?.length ?? 0}');
    }
  } finally {
    client.close();
  }
}
