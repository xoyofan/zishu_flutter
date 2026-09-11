import 'package:live_parser/src/platforms/douyin/ab_sign.dart';
import 'package:test/test.dart';

void main() {
  group('抖音 a_bogus', () {
    test('固定时间戳 golden(与 SFVideoLive TS 实现逐位一致)', () {
      const query =
          'aid=6383&app_name=douyin_web&live_id=1&device_platform=web'
          '&language=zh-CN&enter_from=web_live&cookie_enabled=true'
          '&screen_width=1920&screen_height=1080&browser_language=zh-CN'
          '&browser_platform=Win32&browser_name=Chrome'
          '&browser_version=141.0.0.0&web_rid=123456'
          '&is_need_double_stream=false&msToken=abcdefghijklmnopqrstuvwxyz';
      const ua =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';

      expect(
        douyinAbSign(query, ua, timestamp: 1700000000000),
        'E7mhBmg6mEVNgf6X56KLfY3q6Ar3Y19I0HViMD2faV3vqL39HMYD9exoIBGvXKW'
        'jwG/-IeYjy4hbO3xprQAjM36UHWwEUdQ2mgWkKl5Q5I0j53iruyRDntmF4vj3SFl'
        'm5XNAEOk0y75rKb70Woqe-vIlO62-zo0/96Y=',
      );
    });

    test('不同时间戳产出不同签名', () {
      const query = 'aid=6383&web_rid=123456';
      const ua = 'Mozilla/5.0';
      final first = douyinAbSign(query, ua, timestamp: 1700000000000);
      final second = douyinAbSign(query, ua, timestamp: 1700000001000);
      expect(first, isNot(second));
      expect(first, endsWith('='));
    });
  });
}
