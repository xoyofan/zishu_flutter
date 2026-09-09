import 'package:live_parser/src/platforms/iptv/playlist.dart';
import 'package:test/test.dart';

const _sampleM3U = '''
#EXTM3U
#EXTINF:-1 tvg-id="CCTV1.cn" tvg-name="CCTV1" tvg-logo="https://img/cctv1.png" group-title="News",CCTV-1 综合 (1080p)
https://example.com/cctv1.m3u8
#EXTINF:-1 tvg-id="CCTV5.cn@HD" group-title="Sports",CCTV-5 体育
https://example.com/cctv5.ts
#EXTINF:-1 tvg-logo='https://img/m.png',Movie Channel [Geo-blocked]
#EXTGRP:Movies
https://example.com/movie.flv
#EXTINF:-1 group-title=Documentary,Discovery not 24/7
https://example.com/disc.ts
#EXTINF:-1,Fallback Name
https://example.com/fallback.m3u8
https://example.com/cctv1.m3u8
# comment line
#EXTINF:-1 tvg-id="tv.hk",香港台
rtmp://not-http/stream
''';

void main() {
  group('parseM3U', () {
    final channels = parseM3U(_sampleM3U);

    test('解析条目数与 URL 去重', () {
      // 5 条有效(rtmp 非法丢弃,重复 URL 去重)
      expect(channels, hasLength(5));
      expect(channels.map((c) => c.name).toList(), [
        'CCTV-1 综合 (1080p)',
        'CCTV-5 体育',
        'Movie Channel [Geo-blocked]',
        'Discovery not 24/7',
        'Fallback Name',
      ]);
    });

    test('id:tvg-id 优先,其次净化频道名', () {
      expect(channels[0].id, 'CCTV1.cn');
      expect(channels[3].id, 'discovery-not-24-7');
    });

    test('属性解析:双引号/单引号/无引号', () {
      expect(channels[0].logo, 'https://img/cctv1.png');
      expect(channels[2].logo, 'https://img/m.png');
      expect(channels[2].group, 'Movies', reason: 'parseM3U 透传原始分组;中文映射在仓库 tagged 层');
      expect(channels[3].group, 'Documentary', reason: '无引号 group-title');
    });

    test('#EXTGRP 兜底分组', () {
      expect(channels[2].group, 'Movies', reason: 'EXTINF 无 group-title 时用 #EXTGRP(原始透传)');
      expect(channels[0].group, 'News', reason: 'group-title 优先于 EXTGRP');
    });

    test('清晰度/地区/标记推导', () {
      expect(channels[0].quality, '1080p');
      expect(channels[1].quality, '高清', reason: 'tvg-id @HD 尾缀');
      expect(channels[0].country, '中国');
      expect(channels[0].geoBlocked, isFalse);
      expect(channels[2].geoBlocked, isTrue);
      expect(channels[3].not247, isTrue);
    });

    test('格式识别', () {
      expect(channelFormat('https://a/cctv1.m3u8'), 'hls');
      expect(channelFormat('https://a/movie.flv'), 'flv');
      expect(channelFormat('https://a/cctv5.ts'), 'ts');
    });
  });

  group('channelSlug', () {
    test('非法字符折叠为 - 并小写', () {
      expect(channelSlug('CCTV-1 综合!'), 'cctv-1-综合');
      expect(channelSlug('!!!'), 'channel');
    });
  });

  group('iptvGroupZh', () {
    test('已知英文分组中文化,未知透传,空为未分组', () {
      expect(iptvGroupZh('Sports'), '体育');
      expect(iptvGroupZh('央视'), '央视');
      expect(iptvGroupZh(''), '未分组');
    });
  });

  group('assertSafePlaylistUrl', () {
    test('公网 http/https 通过', () {
      expect(assertSafePlaylistUrl('https://example.com/list.m3u').host, 'example.com');
      expect(assertSafePlaylistUrl('http://iptv.example.org/a').host, 'iptv.example.org');
    });

    test('内网/保留地址拒绝', () {
      for (final url in [
        'http://localhost/list.m3u',
        'http://127.0.0.1/list.m3u',
        'http://10.1.2.3/list.m3u',
        'http://192.168.1.1/list.m3u',
        'http://172.16.0.9/list.m3u',
        'file:///etc/passwd',
        'ftp://example.com/list.m3u',
      ]) {
        expect(
          () => assertSafePlaylistUrl(url),
          throwsA(isA<IptvSsrfException>()),
          reason: url,
        );
      }
    });
  });
}
