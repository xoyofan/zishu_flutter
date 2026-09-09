import 'package:live_parser/src/platforms/douyu/play_api.dart';
import 'package:test/test.dart';

PlayV1Response _responseFromJson(Map<String, dynamic> json) => PlayV1Response.fromJson(json);

void main() {
  group('PlayV1Response 解析', () {
    test('multirates / cdnsWithName / re-weight 双拼写', () {
      final response = _responseFromJson(const {
        'error': 0,
        'msg': 'ok',
        'data': {
          'rtmp_url': 'https://hw-tct.douyucdn.cn/live',
          'rtmp_live': '9527x_0_0.flv',
          'rtmp_cdn': 'hw-h5',
          'is_mixed': false,
          'multirates': [
            {'name': '蓝光8M', 'rate': 0},
            {'name': '超清', 'rate': 2},
          ],
          'cdnsWithName': [
            {'name': '线路1', 'cdn': 'hw-h5', 're-weight': 100},
            {'name': '线路2', 'cdn': 'tct-h5', 'reWeight': 80},
          ],
        },
      });

      expect(response.error, 0);
      expect(response.data!.rtmpUrl, 'https://hw-tct.douyucdn.cn/live');
      expect(response.data!.multirates.map((m) => m.rate), [0, 2]);
      expect(response.data!.cdnsWithName[0].reWeight, 100);
      expect(response.data!.cdnsWithName[1].reWeight, 80);
    });

    test('data 缺失时保持 null', () {
      final response = _responseFromJson(const {'error': 1200, 'msg': 'room offline'});
      expect(response.error, 1200);
      expect(response.msg, 'room offline');
      expect(response.data, isNull);
    });
  });

  group('播放地址拼装', () {
    test('flvFromApiData 直拼 rtmp_url/rtmp_live', () {
      final data = PlayV1Data.fromJson(const {
        'rtmp_url': 'https://hw-tct.douyucdn.cn/live',
        'rtmp_live': '9527abc_0_0.flv',
      });
      expect(flvFromApiData(data), 'https://hw-tct.douyucdn.cn/live/9527abc_0_0.flv');
    });

    test('isDouyucdnUrl 过滤 edgesrv 与空串', () {
      expect(isDouyucdnUrl('https://hw-tct.douyucdn.cn/live/1.flv'), isTrue);
      expect(isDouyucdnUrl('https://hw-tct.edgesrv.com/live/1.flv'), isFalse);
      expect(isDouyucdnUrl(''), isFalse);
    });
  });
}
