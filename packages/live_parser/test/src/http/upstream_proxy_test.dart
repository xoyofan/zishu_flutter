/// 上游代理「按主机分流」单测。
///
/// 为什么必须分流(2026-09-21 实测,同机同网):
/// - Twitch / YouTube 直连不可达 → 必须代理;
/// - SOOP 直连可达,走代理反而慢一个数量级(单档 assign+aid:直连 554ms /
///   代理 31853ms;冷解析中位数 1090ms / 3497ms)。
/// 所以「全局挂代理」是错的:必须按目标主机决定 PROXY 还是 DIRECT。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => UpstreamProxy.configure('127.0.0.1:7897'));
  tearDown(() => UpstreamProxy.configure(null));

  group('needsProxy:必须代理的域', () {
    test('Twitch:GQL / usher / 播放 CDN / IRC 弹幕', () {
      expect(UpstreamProxy.needsProxy('gql.twitch.tv'), isTrue);
      expect(UpstreamProxy.needsProxy('usher.ttvnw.net'), isTrue);
      expect(UpstreamProxy.needsProxy('apn12.playlist.ttvnw.net'), isTrue);
      expect(UpstreamProxy.needsProxy('irc-ws.chat.twitch.tv'), isTrue);
    });

    test('YouTube:站点 / 媒体 / 图片 / InnerTube', () {
      expect(UpstreamProxy.needsProxy('www.youtube.com'), isTrue);
      expect(UpstreamProxy.needsProxy('manifest.googlevideo.com'), isTrue);
      expect(UpstreamProxy.needsProxy('i.ytimg.com'), isTrue);
      expect(UpstreamProxy.needsProxy('youtubei.googleapis.com'), isTrue);
    });

    test('翻译端点与模型源也在代理名单(否则功能不可用)', () {
      expect(UpstreamProxy.needsProxy('translate.googleapis.com'), isTrue);
      expect(UpstreamProxy.needsProxy('huggingface.co'), isTrue);
      expect(UpstreamProxy.needsProxy('us.aws.cdn.hf.co'), isTrue);
      expect(UpstreamProxy.needsProxy('lingva.garudalinux.org'), isTrue);
    });

    test('大小写不敏感', () {
      expect(UpstreamProxy.needsProxy('GQL.Twitch.TV'), isTrue);
      expect(UpstreamProxy.needsProxy('WWW.YouTube.COM'), isTrue);
    });
  });

  group('needsProxy:直连更快的域(不得误走代理)', () {
    test('SOOP / 国内平台', () {
      expect(UpstreamProxy.needsProxy('live.sooplive.co.kr'), isFalse);
      expect(UpstreamProxy.needsProxy('api-channel.sooplive.co.kr'), isFalse);
      expect(UpstreamProxy.needsProxy('www.douyu.com'), isFalse);
      expect(UpstreamProxy.needsProxy('al.hls.huya.com'), isFalse);
      expect(UpstreamProxy.needsProxy('api.live.bilibili.com'), isFalse);
      expect(UpstreamProxy.needsProxy('live.douyin.com'), isFalse);
      expect(UpstreamProxy.needsProxy('127.0.0.1'), isFalse);
    });

    test('后缀匹配不误伤相似域名(eviltwitch.tv 不等于 twitch.tv)', () {
      expect(UpstreamProxy.needsProxy('eviltwitch.tv'), isFalse);
      expect(UpstreamProxy.needsProxy('notyoutube.com'), isFalse);
      expect(UpstreamProxy.needsProxy('twitch.tv.evil.com'), isFalse);
    });

    test('未配置代理时一律直连(即使域名在名单内)', () {
      UpstreamProxy.configure(null);
      expect(UpstreamProxy.needsProxy('gql.twitch.tv'), isFalse);
    });
  });

  group('findProxyFor', () {
    test('命中名单给 PROXY,否则 DIRECT', () {
      expect(
        UpstreamProxy.findProxyFor(Uri.parse('https://gql.twitch.tv/gql')),
        'PROXY 127.0.0.1:7897',
      );
      expect(
        UpstreamProxy.findProxyFor(
          Uri.parse('https://live.sooplive.co.kr/api.php'),
        ),
        'DIRECT',
      );
    });
  });
}
