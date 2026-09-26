// 斗鱼卡片左上角标 → 右上身份位 / 特色 chips 的归一契约。
//
// 字段来自 gapi/rknc/directory/mixListV1(2026-09-26 实测,
// 探针 tool/_probe_douyu_cards.dart):
// - icv3[i].cfgRich.text = 官网卡片左上角标文案(段位LV4 / 全站榜TOP3 …);
// - roomLabel = 特色标签数组(实测最长 6 字、单房最多 22 个)。
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/card_tags.dart';
import 'package:test/test.dart';

Map<String, dynamic> _rich(String text, {int cfgType = 2}) => {
  'cfgType': cfgType,
  'cfgRich': {
    'addr': 'https://sta-op.douyucdn.cn/dy-listicon/e49a.png',
    'backColor': '#7B90FD',
    'rightBackColor': '#5F77F3',
    'text': text,
    'fontColor': '#FFFFFF',
  },
  'iconId': '11736_0',
};

void main() {
  group('pickDouyuIdentityLabel(icv3 → 右上身份位)', () {
    test('取 icv3 里第一条有文案的角标', () {
      expect(
        pickDouyuIdentityLabel({
          'icv3': [_rich('段位LV4')],
        }),
        '段位LV4',
      );
    });

    test('榜单类文案整文保留(官网 12px 不截断,实测最宽 8 字)', () {
      expect(
        pickDouyuIdentityLabel({
          'icv3': [_rich('全站榜TOP10')],
        }),
        '全站榜TOP10',
      );
      expect(
        pickDouyuIdentityLabel({
          'icv3': [_rich('分区榜TOP1')],
        }),
        '分区榜TOP1',
      );
    });

    test('多条 icv3:跳过无文案项,取第一条有文案的', () {
      expect(
        pickDouyuIdentityLabel({
          'icv3': [
            {'cfgType': 1, 'cfgNormal': {'addr': 'https://x/y.png'}},
            _rich('百钻成就'),
          ],
        }),
        '百钻成就',
      );
    });

    test('无 icv3 / 空数组 / 纯空白文案 → null(右上不渲染)', () {
      expect(pickDouyuIdentityLabel(const {}), isNull);
      expect(pickDouyuIdentityLabel({'icv3': const []}), isNull);
      expect(pickDouyuIdentityLabel({'icv3': [_rich('  ')]}), isNull);
      expect(
        pickDouyuIdentityLabel({
          'icv3': 'not-a-list',
        }),
        isNull,
        reason: '上游类型异常不抛异常,降级为 null',
      );
    });

    test('超长文案按 10 字截断(实测最宽 8 字,10 为防御上限)', () {
      expect(
        pickDouyuIdentityLabel({
          'icv3': [_rich('一二三四五六七八九十十一')],
        }),
        '一二三四五六七八九十',
      );
    });
  });

  group('douyuCardChips(roomLabel → 封面下方 chips 行)', () {
    test('按原顺序编成 tag chip,不可点(无 filterCid)', () {
      final chips = douyuCardChips({
        'roomLabel': ['炉石金牌讲师', '天梯高玩'],
      });
      expect(chips.map((c) => c.name).toList(), ['炉石金牌讲师', '天梯高玩']);
      expect(chips.every((c) => c.kind == SiteChipKind.tag), isTrue);
      expect(chips.every((c) => !c.navigable), isTrue);
      expect(chips.first.id, 'dy:炉石金牌讲师', reason: 'id 需平台内唯一');
    });

    test('单房最多 3 个(实测上游可达 22 个,卡片 chips 行是单行)', () {
      final chips = douyuCardChips({
        'roomLabel': ['版本开发师', '打野专精', 'K头之王', '职业打野', '野区霸主'],
      });
      expect(chips.map((c) => c.name).toList(), [
        '版本开发师',
        '打野专精',
        'K头之王',
      ]);
    });

    test('同名去重 + 跳过空白项', () {
      final chips = douyuCardChips({
        'roomLabel': ['电竞软妹', '  ', '电竞软妹', '职业中单'],
      });
      expect(chips.map((c) => c.name).toList(), ['电竞软妹', '职业中单']);
    });

    test('无 roomLabel → 空 chips(不改 promoTag 兜底链路)', () {
      expect(douyuCardChips(const {}), isEmpty);
      expect(douyuCardChips({'roomLabel': const []}), isEmpty);
    });
  });
}
