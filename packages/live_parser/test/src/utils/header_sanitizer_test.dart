import 'package:live_parser/src/utils/header_sanitizer.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeHeaders', () {
    test('头名 trim + 小写归一', () {
      expect(sanitizeHeaders({' User-Agent ': 'x'}), {'user-agent': 'x'});
      expect(sanitizeHeaders({'REFERER': 'x'}), {'referer': 'x'});
      expect(sanitizeHeaders({'X-Youtube-Client-Name': '1'}), {
        'x-youtube-client-name': '1',
      });
    });

    test('非法头名丢弃(空格/冒号/空)', () {
      expect(
        sanitizeHeaders({'X Bad': 'v', 'a b': 'v', 'a:b': 'v', '': 'v'}),
        isEmpty,
      );
    });

    test('头值 CR/LF/NUL 替换为空格并 trim', () {
      expect(sanitizeHeaders({'a': 'v1\r\nv2\u0000v3'}), {'a': 'v1 v2 v3'});
      expect(sanitizeHeaders({'a': ' pad '}), {'a': 'pad'});
    });

    test('空值丢弃', () {
      expect(sanitizeHeaders({'a': '', 'b': '   ', 'c': '\r\n'}), isEmpty);
    });

    test('输出为不可变 Map', () {
      final headers = sanitizeHeaders({'a': 'b'});
      expect(() => headers['c'] = 'd', throwsUnsupportedError);
    });

    test('空输入返回空 Map', () {
      expect(sanitizeHeaders(const {}), isEmpty);
    });
  });

  group('sanitizeHeaderName / sanitizeHeaderValue', () {
    test('单独调用与整组归一语义一致', () {
      expect(sanitizeHeaderName(' Origin '), 'origin');
      expect(sanitizeHeaderName('bad name'), '');
      expect(sanitizeHeaderValue(' a\nb '), 'a b');
    });
  });
}
