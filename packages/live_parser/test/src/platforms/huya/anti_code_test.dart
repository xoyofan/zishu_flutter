import 'package:live_parser/src/http/parser_http.dart';
import 'package:live_parser/src/platforms/huya/anti_code.dart';
import 'package:test/test.dart';

void main() {
  group('computeHuyaWsSecret 固定向量', () {
    test('固定输入产生固定 wsSecret', () {
      expect(
        computeHuyaWsSecret(
          fmPrefix: '1137',
          ctype: 'huya_webh5',
          streamName: '9527-2650134-5195-2650134-10057-A-0-1-image',
          uid: 1400000123456,
          seqId: 1400002525068,
          paramsT: 100,
          wsTime: '65f0a1b0',
        ),
        '9604c6b0245112d493a6ab4eae84743d',
      );
    });

    test('uid/seqId/wsTime 变化产生不同签名', () {
      final base = computeHuyaWsSecret(
        fmPrefix: '1137',
        ctype: 'huya_webh5',
        streamName: 's',
        uid: 1,
        seqId: 1,
        paramsT: 100,
        wsTime: '65f0a1b0',
      );
      final other = computeHuyaWsSecret(
        fmPrefix: '1137',
        ctype: 'huya_webh5',
        streamName: 's',
        uid: 1,
        seqId: 2,
        paramsT: 100,
        wsTime: '65f0a1b0',
      );
      expect(base, isNot(other));
    });
  });

  group('huyaFmPrefix', () {
    test('base64 解码取首段', () {
      expect(huyaFmPrefix('MTEzN194eXo='), '1137');
    });
  });

  group('buildHuyaAntiCode', () {
    const antiCode =
        'wsSecret=deadbeef&wsTime=65f0a1b0&fm=MTEzN194eXo=&ctype=huya_webh5&fs=bgct';

    test('生成完整签名 query', () {
      final result = buildHuyaAntiCode(antiCode, '9527-2650134-5195-2650134-10057-A-0-1-image');
      expect(result, contains('ctype=huya_webh5'));
      expect(result, contains('fs=bgct'));
      expect(result, contains('ver=1'));
      expect(result, contains('t=100'));
      expect(result, contains('sv=2403051612'));
      expect(result, contains('codec=264'));
      final wsSecret = RegExp(r'wsSecret=([0-9a-f]{32})').firstMatch(result)!;
      expect(wsSecret.group(1), hasLength(32));
      expect(result, contains(RegExp(r'wsTime=[0-9a-f]+')));
      expect(result, contains(RegExp(r'u=1400\d{9}')));
    });

    test('缺 fm/ctype/fs 抛 ParserHttpException', () {
      expect(
        () => buildHuyaAntiCode('wsSecret=deadbeef&wsTime=65f0a1b0', 's'),
        throwsA(isA<ParserHttpException>()),
      );
    });
  });

  group('wsTime 租约对齐服务端', () {
    // 上游 anti_code 自带 wsTime(实测 ≈ now+284s),而自造值 `(now+110624ms)`
    // 只有 ≈ now+110s —— 地址寿命被砍掉约 60%。CDN 以「wsTime 是否已过」判定
    // 有效性(过期一律 403、未来值放行),故沿用服务端值可显著拉长租约。
    const base = 'wsSecret=deadbeef&fm=MTEzN194eXo=&ctype=huya_webh5&fs=bgct';

    String wsTimeOf(String result) =>
        RegExp(r'wsTime=([0-9a-f]+)').firstMatch(result)!.group(1)!;

    int nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

    test('服务端 wsTime 更晚时直接沿用', () {
      expect(
        wsTimeOf(buildHuyaAntiCode('$base&wsTime=ffffffff', 's')),
        'ffffffff',
      );
    });

    test('缺 wsTime 时回退到自造值(且在未来)', () {
      final parsed = int.parse(wsTimeOf(buildHuyaAntiCode(base, 's')), radix: 16);
      expect(parsed, greaterThan(nowSeconds()));
    });

    test('服务端 wsTime 已过期时不采用过期值', () {
      // 直接用过期 wsTime 会让地址"一开场就 403",比自造值更糟。
      final parsed = int.parse(
        wsTimeOf(buildHuyaAntiCode('$base&wsTime=00000001', 's')),
        radix: 16,
      );
      expect(parsed, greaterThan(nowSeconds()));
    });

    test('wsTime 参与签名:换 wsTime 必须换 wsSecret', () {
      String secretOf(String wsTime) => computeHuyaWsSecret(
        fmPrefix: '1137',
        ctype: 'huya_webh5',
        streamName: 's',
        uid: 1,
        seqId: 1,
        paramsT: 100,
        wsTime: wsTime,
      );
      expect(secretOf('ffffffff'), isNot(secretOf('eeeeeeee')));
    });
  });
}
