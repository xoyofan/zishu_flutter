/// format_online 数值解析单测:展示格式化与排序解析(合法零 vs 缺失)。
///
/// 关键契约(审阅 P2):
/// - [tryParseOnlineCount]:合法数值(**含 0**)→ int;空串/null/不可解析 → null。
/// - [parseOnlineCount]:兼容口径不变,合法零与非法/空串一律回 0。
library;

import 'package:live_parser/src/utils/format_online.dart';
import 'package:test/test.dart';

void main() {
  group('tryParseOnlineCount', () {
    test('合法数值(含 万/千/逗号/plain)返回整数', () {
      expect(tryParseOnlineCount('1.2万'), 12000);
      expect(tryParseOnlineCount('3.4千'), 3400);
      expect(tryParseOnlineCount('1,234'), 1234);
      expect(tryParseOnlineCount('8921'), 8921);
      expect(tryParseOnlineCount('5.0w'), 50000);
    });

    test('合法零返回 0,不是 null(本地可原样恢复 online="0")', () {
      expect(tryParseOnlineCount('0'), 0);
      expect(tryParseOnlineCount('0.0万'), 0);
      expect(tryParseOnlineCount(0), 0);
      expect(tryParseOnlineCount(' 0 '), 0);
    });

    test('空串/null/不可解析返回 null(缺失必须能与合法零区分)', () {
      expect(tryParseOnlineCount(''), isNull);
      expect(tryParseOnlineCount('   '), isNull);
      expect(tryParseOnlineCount(null), isNull);
      expect(tryParseOnlineCount('人气'), isNull);
      expect(tryParseOnlineCount('—'), isNull);
      expect(tryParseOnlineCount('12人'), isNull);
      expect(tryParseOnlineCount('1.2.3'), isNull);
    });
  });

  group('parseOnlineCount 兼容口径', () {
    test('合法零与非法/空串都回 0,既有调用点行为不变', () {
      expect(parseOnlineCount('0'), 0);
      expect(parseOnlineCount(''), 0);
      expect(parseOnlineCount(null), 0);
      expect(parseOnlineCount('人气'), 0);
    });

    test('有数值时与 tryParseOnlineCount 同源同结果', () {
      expect(parseOnlineCount('1.2万'), tryParseOnlineCount('1.2万'));
      expect(parseOnlineCount('1,234'), tryParseOnlineCount('1,234'));
      expect(parseOnlineCount('3.4千'), tryParseOnlineCount('3.4千'));
    });
  });
}
