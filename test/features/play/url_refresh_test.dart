/// [urlTtlSeconds] 契约:从流 URL 的 expire 参数提取寿命,供预刷新排期。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/features/play/application/url_refresh.dart';

void main() {
  test('斗鱼实测样例:expire=300 提取为 300s', () {
    const url = 'https://stream-hefei-cmcc-39-145-3-183.edgesrv.com:8443'
        '/live/9999_4000.flv?wsAuth=abc&token=web-h5-0-9999-x'
        '&expire=300&did=1&fcdn=scdn';
    expect(urlTtlSeconds(url), 300);
  });

  test('无 expire 参数回退默认 300s', () {
    expect(urlTtlSeconds('https://hwa.douyucdn2.cn/live/9999.flv?token=x'), 300);
  });

  test('null/空串回退默认', () {
    expect(urlTtlSeconds(null), 300);
    expect(urlTtlSeconds(''), 300);
  });

  test('非法 expire 回退默认,不抛异常', () {
    expect(urlTtlSeconds('https://a.com/x.flv?expire=abc'), 300);
  });

  test('异常值夹取下限(防立刻触发)与上限(防永不再刷)', () {
    expect(urlTtlSeconds('https://a.com/x.flv?expire=0'), 30);
    expect(urlTtlSeconds('https://a.com/x.flv?expire=-5'), 30);
    expect(urlTtlSeconds('https://a.com/x.flv?expire=99999999'), 86400);
  });

  test('非 URL 文本回退默认,不抛异常', () {
    expect(urlTtlSeconds('not a url'), 300);
  });
}
