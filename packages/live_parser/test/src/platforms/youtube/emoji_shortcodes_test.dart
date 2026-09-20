import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  group('YouTube emoji 短代码替换', () {
    test('真机证据短代码归一为 Unicode emoji', () {
      // 2026-09-20 Windows 真机弹幕证据:「:crossed_flags:」「:grinning_face_with_sweat:」。
      expect(replaceYoutubeEmojiShortcodes(':crossed_flags:'), '🎌');
      expect(replaceYoutubeEmojiShortcodes(':grinning_face_with_sweat:'), '😅');
      expect(replaceYoutubeEmojiShortcodes(':joy:'), '😂');
    });

    test('gemoji 主表与 CLDR 补充表均命中', () {
      // gemoji 主表别名。
      expect(replaceYoutubeEmojiShortcodes(':sweat_smile:'), '😅');
      expect(replaceYoutubeEmojiShortcodes(':crossed_fingers:'), '🤞');
      // CLDR 补充表(YouTube 实际使用的短名,gemoji 缺口)。
      expect(replaceYoutubeEmojiShortcodes(':thumbs_up:'), '👍');
      expect(replaceYoutubeEmojiShortcodes(':folded_hands:'), '🙏');
      expect(replaceYoutubeEmojiShortcodes(':red_heart:'), '❤️');
      expect(replaceYoutubeEmojiShortcodes(':hundred_points:'), '💯');
      expect(replaceYoutubeEmojiShortcodes(':party_popper:'), '🎉');
    });

    test('未知名与无关文本原样保留(数据诚实,不伪造)', () {
      expect(
        replaceYoutubeEmojiShortcodes(':totally_unknown_code:'),
        ':totally_unknown_code:',
      );
      // 半角冒号但不在词法内(如颜文字)不动。
      expect(replaceYoutubeEmojiShortcodes('你好:)'), '你好:)');
      // 时间类字面量(:30 不在表内)不动。
      expect(replaceYoutubeEmojiShortcodes('时间 12:30:45'), '时间 12:30:45');
      // 无冒号文本原样。
      expect(replaceYoutubeEmojiShortcodes('普通弹幕文本'), '普通弹幕文本');
    });

    test('混合文本只替换表内短代码,前后文保留', () {
      expect(replaceYoutubeEmojiShortcodes('前:joy:后'), '前😂后');
      expect(
        replaceYoutubeEmojiShortcodes(':thumbs_up::thumbs_up:'),
        '👍👍',
      );
    });

    test('映射表规模:主表全量 + 补充表高频,两表键不相交', () {
      expect(kYoutubeEmojiShortcodes.length, greaterThan(1000));
      expect(
        kYoutubeEmojiCldrShortcodes.length,
        inInclusiveRange(100, 300),
        reason: 'CLDR 补充表定位为高频聊天表情缺口集',
      );
      expect(
        kYoutubeEmojiShortcodes.keys
            .toSet()
            .intersection(kYoutubeEmojiCldrShortcodes.keys.toSet()),
        isEmpty,
        reason: '补充表只收 gemoji 主表缺口,查找顺序主表优先',
      );
      // 证据短代码必须在某张表内。
      expect(
        kYoutubeEmojiShortcodes.containsKey('crossed_flags') ||
            kYoutubeEmojiCldrShortcodes.containsKey('crossed_flags'),
        isTrue,
      );
    });
  });
}
