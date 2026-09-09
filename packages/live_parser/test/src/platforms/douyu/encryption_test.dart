import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/encryption.dart';
import 'package:test/test.dart';

const _fixedWhite = WhiteKey(
  key: 'aKey123',
  randStr: 'randStrXYZ',
  encTime: 1,
  encData: 'encDataToken',
  isSpecial: false,
);

const _fixedTs = 1700000000;

void main() {
  group('md5Hex', () {
    test('RFC 1321 固定向量', () {
      expect(md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
      expect(md5Hex(''), 'd41d8cd98f00b204e9800998ecf8427e');
    });
  });

  group('computeDouyuAuth 固定向量', () {
    test('普通白名单 encTime=1,salt = rid + ts', () {
      expect(
        computeDouyuAuth(rid: '9527', white: _fixedWhite, ts: _fixedTs),
        '841a0fdb5e50b6e8ab052a56dd38d03f',
      );
    });

    test('special 白名单 salt 为空,encTime=2', () {
      const special = WhiteKey(
        key: 'aKey123',
        randStr: 'randStrXYZ',
        encTime: 2,
        encData: 'encDataToken',
        isSpecial: true,
      );
      expect(
        computeDouyuAuth(rid: '9527', white: special, ts: _fixedTs),
        '337944119a4ba98ff01b4d5f46c4b228',
      );
    });

    test('encTime=0 不迭代', () {
      const zero = WhiteKey(
        key: 'aKey123',
        randStr: 'randStrXYZ',
        encTime: 0,
        encData: 'encDataToken',
        isSpecial: false,
      );
      expect(
        computeDouyuAuth(rid: '9527', white: zero, ts: _fixedTs),
        'a6bcd240d47843d13724e1773b9be083',
      );
    });

    test('不同 ts/rid 产生不同签名', () {
      final a = computeDouyuAuth(rid: '9527', white: _fixedWhite, ts: _fixedTs);
      final b = computeDouyuAuth(rid: '9527', white: _fixedWhite, ts: _fixedTs + 1);
      final c = computeDouyuAuth(rid: '9528', white: _fixedWhite, ts: _fixedTs);
      expect(a, isNot(b));
      expect(a, isNot(c));
    });
  });

  group('WhiteKeyCache', () {
    test('拉取解析 fixture 字段并缓存', () async {
      var requestCount = 0;
      final client = ParserHttp(
        client: _CountingClient((_) {
          requestCount++;
          return http.Response(
            '{"error":0,"data":{"key":"k","rand_str":"r","enc_time":2,'
            '"enc_data":"e","is_special":true}}',
            200,
          );
        }),
      );
      final cache = WhiteKeyCache(now: () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000));

      final first = await cache.fetch(client);
      expect(first.key, 'k');
      expect(first.randStr, 'r');
      expect(first.encTime, 2);
      expect(first.isSpecial, isTrue);

      final second = await cache.fetch(client);
      expect(identical(first, second), isTrue);
      expect(requestCount, 1);
    });

    test('TTL 过期后重新拉取', () async {
      var requestCount = 0;
      final client = ParserHttp(
        client: _CountingClient((_) {
          requestCount++;
          return http.Response(
            '{"error":0,"data":{"key":"k","rand_str":"r","enc_time":1,'
            '"enc_data":"e","is_special":false}}',
            200,
          );
        }),
      );
      var nowSec = 10 * 1000 * 1000;
      final cache = WhiteKeyCache(
        ttl: const Duration(seconds: 60),
        now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000),
      );

      await cache.fetch(client);
      expect(requestCount, 1);

      nowSec += 30;
      await cache.fetch(client);
      expect(requestCount, 1, reason: 'TTL 内命中缓存');

      nowSec += 31;
      await cache.fetch(client);
      expect(requestCount, 2, reason: '过期后重新请求');
    });

    test('上游 error 非 0 抛 ParserHttpException', () async {
      final client = ParserHttp(
        client: _CountingClient(
          (_) => http.Response('{"error":500,"msg":"denied"}', 200),
        ),
      );
      final cache = WhiteKeyCache(now: () => DateTime.fromMillisecondsSinceEpoch(0));
      await expectLater(cache.fetch(client), throwsA(isA<ParserHttpException>()));
    });
  });
}

class _CountingClient extends http.BaseClient {
  _CountingClient(this.handler);

  final http.Response Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = handler(request);
    final bytes = response.bodyBytes;
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
    );
  }
}
