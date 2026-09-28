import 'package:live_parser/src/platforms/douyu/encryption.dart';
import 'package:live_parser/src/platforms/douyu/lines.dart';
import 'package:live_parser/src/platforms/douyu/play_api.dart';
import 'package:test/test.dart';

PlayV1Response _resp({
  String rtmpUrl = 'https://cdn.douyucdn.cn/live',
  String rtmpLive = '9527_0_0.flv',
  String rtmpCdn = 'hw-h5',
  bool isMixed = false,
  String mixedUrl = '',
}) {
  return PlayV1Response.fromJson({
    'error': 0,
    'data': {
      'rtmp_url': rtmpUrl,
      'rtmp_live': rtmpLive,
      'rtmp_cdn': rtmpCdn,
      if (isMixed) 'is_mixed': true,
      if (mixedUrl.isNotEmpty) 'mixed_url': mixedUrl,
    },
  });
}

void main() {
  group('parseDouyuCdnList', () {
    test('按 re-weight 降序(对齐官方 web 2026-09-28 实测:scdn 99999 优先)', () {
      final response = PlayV1Response.fromJson(const {
        'error': 0,
        'data': {
          'rtmp_cdn': 'scdncmccanhhf',
          'cdnsWithName': [
            {'name': '线路7', 'cdn': 'hw-h5', 're-weight': 10009},
            {'name': '线路1', 'cdn': 'scdncmccanhhf', 're-weight': 99999},
            {'name': '线路13', 'cdn': 'hs-h5', 're-weight': 10010},
            {'name': '坏数据', 'cdn': ''},
          ],
        },
      });
      final cdns = parseDouyuCdnList(response.data);
      expect(
        cdns.map((c) => c.cdn),
        ['scdncmccanhhf', 'hs-h5', 'hw-h5'],
        reason: '服务端 re-weight 即选线依据,不再硬编码 hw-h5 恒最前',
      );
    });

    test('同 weight 保持输入顺序(稳定排序)', () {
      final response = PlayV1Response.fromJson(const {
        'error': 0,
        'data': {
          'cdnsWithName': [
            {'name': 'a', 'cdn': 'a-h5', 're-weight': 10},
            {'name': 'b', 'cdn': 'b-h5', 're-weight': 10},
          ],
        },
      });
      final cdns = parseDouyuCdnList(response.data);
      expect(cdns.map((c) => c.cdn), ['a-h5', 'b-h5']);
    });

    test('cdnsWithName 缺失时回退 rtmp_cdn', () {
      final cdns = parseDouyuCdnList(_resp(rtmpCdn: 'sc-h5').data);
      expect(cdns, hasLength(1));
      expect(cdns.first.cdn, 'sc-h5');
      expect(cdns.first.name, '默认');
    });

    test('全空数据回退 hw-h5', () {
      final cdns = parseDouyuCdnList(null);
      expect(cdns.single.cdn, 'hw-h5');
    });
  });

  group('preferredDouyuCdnCode', () {
    test('无偏好时取 weight 最高(服务端首选),显式偏好命中仍尊重', () {
      final response = PlayV1Response.fromJson(const {
        'error': 0,
        'data': {
          'rtmp_cdn': 'hw-h5',
          'cdnsWithName': [
            {'name': '线路7', 'cdn': 'hw-h5', 're-weight': 10009},
            {'name': '线路1', 'cdn': 'scdncmccanhhf', 're-weight': 99999},
          ],
        },
      });
      final cdns = parseDouyuCdnList(response.data);
      expect(preferredDouyuCdnCode(cdns), 'scdncmccanhhf');
      expect(preferredDouyuCdnCode(cdns, 'hw-h5'), 'hw-h5');
    });
  });

  group('playUrlFromResponse', () {
    test('普通流返回 rtmp_url/rtmp_live', () {
      final url = playUrlFromResponse(
        _resp(rtmpLive: '9527abc_0_0.flv'),
      );
      expect(url, 'https://cdn.douyucdn.cn/live/9527abc_0_0.flv');
    });

    test('is_mixed 且 mixed_url 是完整 douyucdn 地址', () {
      final url = playUrlFromResponse(
        _resp(
          isMixed: true,
          mixedUrl: 'https://mix.douyucdn.cn/live/mix.flv',
        ),
      );
      expect(url, 'https://mix.douyucdn.cn/live/mix.flv');
    });

    test('is_mixed 且 mixed_url 为相对路径时拼 base', () {
      final url = playUrlFromResponse(
        _resp(rtmpUrl: 'https://cdn.douyucdn.cn/live/', isMixed: true, mixedUrl: 'mix_9527.flv'),
      );
      expect(url, 'https://cdn.douyucdn.cn/live/mix_9527.flv');
    });

    test('rtmp_live 含 mix=1 时优先拼 mixed_url', () {
      final url = playUrlFromResponse(
        _resp(rtmpLive: '9527abc_0_0.flv?mix=1', isMixed: false, mixedUrl: 'mix_9527.flv'),
      );
      expect(url, 'https://cdn.douyucdn.cn/live/mix_9527.flv');
    });

    test('非官方流域名(第三方)的混合地址回退普通拼装', () {
      final url = playUrlFromResponse(
        _resp(isMixed: true, mixedUrl: 'https://evil.example.com/x.flv'),
      );
      expect(url, 'https://cdn.douyucdn.cn/live/9527_0_0.flv');
    });
  });

  group('appendHlsFallbackLine', () {
    test('有 FLV 线路时不插 HLS(避免预览流抢占首选)', () {
      final lines = appendHlsFallbackLine(
        const [DouyuLineDraft(name: '线路1 FLV', url: 'https://a.douyucdn.cn/1.flv', format: 'flv')],
        'https://a.douyucdn.cn/1.m3u8',
      );
      expect(lines, hasLength(1));
      expect(lines.single.name, '线路1 FLV');
      expect(lines.single.format, 'flv');
    });

    test('FLV 全灭时以 HLS 兑底', () {
      final lines = appendHlsFallbackLine(
        const <DouyuLineDraft>[],
        'https://a.douyucdn.cn/1.m3u8',
      );
      expect(lines, hasLength(1));
      expect(lines.single.name, 'HLS');
      expect(lines.single.format, 'hls');
    });

    test('无 HLS 时原样返回', () {
      final lines = [
        const DouyuLineDraft(name: '线路1 FLV', url: 'https://a.douyucdn.cn/1.flv', format: 'flv'),
      ];
      expect(identical(appendHlsFallbackLine(lines, ''), lines), isTrue);
    });
  });

  group('douyuPlaybackHeaders', () {
    test('Referer 带房间号,并带 UA 与匿名 did Cookie', () {
      final headers = douyuPlaybackHeaders('9527');
      expect(headers['referer'], 'https://www.douyu.com/9527');
      expect(headers['origin'], 'https://www.douyu.com');
      expect(headers['user-agent'], contains('Chrome/'));
      expect(headers['cookie'], contains('dy_did=$kDouyuDefaultDid'));
    });

    test('空房间号回退站点根 Referer', () {
      expect(douyuPlaybackHeaders('')['referer'], 'https://www.douyu.com/');
    });
  });
}
