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
}
