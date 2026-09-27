/// 抖音表情名 → Unicode 等价(离线可渲染、两端通用)。
///
/// 抖音聊天里表情有两种形态:
/// 1. 富文本 image piece(双端 protobuf):解析层 `_parseTextPiece` 已转成
///    emoji 段并带 CDN 图 url;图加载失败时的兜底文案用本表映射的 Unicode,
///    避免回退成 `[赞]` 这样的裸括号码。
/// 2. 纯文本裸括号码 `[赞]`:出现在 #3/#5 兜底文本里,解析层此前原样当文字。
///    [parseDouyinBracketEmoji] 用本表把命中项转成 emoji 段。
///
/// 自定义 sticker(无 Unicode 对应)经 [kDouyinEmojiImage] 还原抖音原版贴图
/// (UI 优先渲染 url,图失败回退 `[name]` 文本,与 web DanmakuRichText 一致)。
library;

import 'emoji_image_data.dart';
import '../../models/models.dart';

/// 抖音表情名 → Unicode 字形。覆盖高频、语义明确可映射到标准 emoji 的集合;
/// 别名/变体(如 `胜利`/`耶` 同指 ✌️)直接并到同一字形。
const Map<String, String> kDouyinEmojiUnicode = <String, String>{
  '赞': '👍',
  '强': '💪',
  '耶': '✌️',
  '胜利': '✌️',
  '玫瑰': '🌹',
  '爱心': '❤️',
  '心碎': '💔',
  '火': '🔥',
  '太阳': '🌞',
  '月亮': '🌙',
  '星星': '⭐',
  '哭': '😭',
  '流泪': '😢',
  '笑': '😄',
  '大笑': '😆',
  '笑哭': '😂',
  '呲牙': '😁',
  '流汗': '😅',
  '生气': '😡',
  '愤怒': '😡',
  '惊': '😲',
  '惊恐': '😱',
  '闭嘴': '🤫',
  '思考': '🤔',
  '哈欠': '🥱',
  '睡': '😴',
  '飞吻': '😘',
  '亲': '😘',
  '色': '😍',
  '衰': '😞',
  '失望': '😞',
  '吐': '🤮',
  '得意': '😎',
  '拥抱': '🤗',
  '抱拳': '🙏',
  '礼物': '🎁',
  '红包': '🧧',
  '福': '🧧',
  '发': '🧧',
  '蛋糕': '🍰',
  '啤酒': '🍺',
  '咖啡': '☕',
  '茶': '🍵',
  '西瓜': '🍉',
  '猪头': '🐷',
  '饭': '🍚',
  '庆祝': '🎉',
  '鼓掌': '👏',
  '握手': '🤝',
  '比心': '🤟',
  'OK': '👌',
  '乒乓': '🏓',
  '闪电': '⚡',
  '难过': '🙁',
  '无语': '😶',
  '害羞': '☺️',
  '坏笑': '😏',
  '抓狂': '😣',
  '音乐': '🎵',
};

/// 抖音表情名 → 渲染用 Unicode;未收录返回 null(保留原 `[name]` 文本)。
String? douyinEmojiUnicode(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  return kDouyinEmojiUnicode[trimmed];
}

/// 把纯文本里的 `[name]` 裸括号表情码转成 emoji 段;命中的名字优先挂原版
/// 贴图 URL([kDouyinEmojiImage],web douyinEmoji.ts resolveEmojiUrl 同语义),
/// 其次用 Unicode 字形([kDouyinEmojiUnicode])离线渲染;两表都未命中的保留
/// 原样。返回更新后的正文与段列表(无命中段时 segments 空)。
///
/// 只作用于纯文本路径(segments 为空),富文本 image piece 由 `_parseTextPiece`
/// 处理,两者互不重复。
///
/// 段列表同时包含相邻文本段(相邻文本合并),保证 UI 按序渲染时不丢字;
/// 仅当至少命中一个表情时才产出非空 segments,否则退回纯文本契约(segments
/// 空,UI 直接渲染 `text`),避免把 `[连麦]` 这类未收录码误当成富文本。
({String text, List<DanmakuSegment> segments}) parseDouyinBracketEmoji(
  String raw,
) {
  if (raw.isEmpty) return (text: raw, segments: const []);
  final segments = <DanmakuSegment>[];
  final buffer = StringBuffer(); // 合并后的正文(兜底用)
  final textRun = StringBuffer(); // 当前文本段累积
  var last = 0;
  var matched = false;
  final re = RegExp(r'\[([^\[\]\n]{1,12})\]');

  void flushText() {
    if (textRun.isNotEmpty) {
      segments.add(DanmakuSegment.text(textRun.toString()));
      textRun.clear();
    }
  }

  for (final m in re.allMatches(raw)) {
    if (m.start > last) {
      final between = raw.substring(last, m.start);
      buffer.write(between);
      textRun.write(between);
    }
    final name = m.group(1)!;
    final unicode = douyinEmojiUnicode(name);
    final imageUrl = douyinEmojiImage(name);
    if (unicode != null || imageUrl != null) {
      flushText();
      // 段文本:Unicode 优先(离线可渲染、图片失败兜底),否则保留 [名] 字面。
      final segmentText = unicode ?? m.group(0)!;
      segments.add(
        DanmakuSegment.emoji(
          text: segmentText,
          url: imageUrl ?? '',
          name: name,
        ),
      );
      buffer.write(segmentText);
      matched = true;
    } else {
      // 未收录:保留裸括号码字面,仅进正文(不进 segments)。
      final literal = m.group(0)!;
      buffer.write(literal);
      textRun.write(literal);
    }
    last = m.end;
  }
  if (last < raw.length) {
    final tail = raw.substring(last);
    buffer.write(tail);
    textRun.write(tail);
  }
  flushText();

  final joined = buffer.toString();
  if (!matched) {
    return (text: joined, segments: const []);
  }
  return (text: joined, segments: List.unmodifiable(segments));
}
