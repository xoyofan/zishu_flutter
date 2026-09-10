import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  group('YY normalize', () {
    test('纯数字与房间页 URL', () {
      expect(normalizeYyRoomId('547800'), '547800');
      expect(normalizeYyRoomId('https://www.yy.com/547800?from=home'), '547800');
      expect(normalizeYyRoomId('yy.com/1414787909/1414787909/'), '1414787909');
      expect(httpsYyUrl('//img.yy.com/a.jpg'), 'https://img.yy.com/a.jpg');
      expect(httpsYyUrl('http://img.yy.com/a.jpg'), 'https://img.yy.com/a.jpg');
    });

    test('非 YY 地址拒绝', () {
      expect(
        () => normalizeYyRoomId('https://www.douyu.com/123'),
        throwsA(isA<ParserHttpException>()),
      );
    });
  });
}
