import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

/// 全平台热门 25 key(对齐 web `HOT_CROSS_CATEGORY_KEYS`,顺序即展示顺序)。
/// 顺序必须与 `tool/sync_cross_map.dart` 的 `_kHotCrossCategoryKeys` 一致。
const List<String> _kHotKeys = [
  'lol',
  'sjz',
  'jx3',
  'wzry',
  'hpjy',
  'cs2',
  'dota2',
  'cf',
  'yjwj',
  'ys',
  'bhxy',
  'aqtw',
  'tft',
  'hs',
  'valorant',
  'dnf',
  'dzpd',
  'dwrg',
  'hmwk',
  'jcc',
  'jql',
  'wudao',
  'huwai',
  'xingxiu',
  'yanzhi',
];

/// 每个 HOT key 对应的 canonical 中文展示名(来自映射表 `name` 字段)。
const Map<String, String> _kHotNames = {
  'lol': '英雄联盟',
  'sjz': '三角洲行动',
  'jx3': '剑网3',
  'wzry': '王者荣耀',
  'hpjy': '和平精英',
  'cs2': 'CS2',
  'dota2': 'DOTA2',
  'cf': '穿越火线',
  'yjwj': '永劫无间',
  'ys': '原神',
  'bhxy': '崩坏：星穹铁道',
  'aqtw': '暗区突围',
  'tft': '云顶之弈',
  'hs': '炉石传说',
  'valorant': '无畏契约',
  'dnf': 'DNF',
  'dzpd': '蛋仔派对',
  'dwrg': '第五人格',
  'hmwk': '黑神话：悟空',
  'jcc': '金铲铲之战',
  'jql': '绝区零',
  'wudao': '舞蹈',
  'huwai': '户外',
  'xingxiu': '星秀',
  'yanzhi': '颜值',
};

void main() {
  group('normalizeCategoryName', () {
    test('小写并去除空格与分隔符', () {
      expect(normalizeCategoryName('League of Legends'), 'leagueoflegends');
      expect(normalizeCategoryName('英雄联盟 - 峡谷之巅'), '英雄联盟峡谷之巅');
      expect(normalizeCategoryName('DOTA2'), 'dota2');
    });
  });

  group('CrossCategory.matches', () {
    final lol = kDefaultCrossCategories.firstWhere((c) => c.key == 'lol');

    test('站点 cid 白名单命中(斗鱼 cid=1)', () {
      expect(lol.matches(site: 'douyu', cid: '1', categoryName: ''), isTrue);
      expect(lol.matches(site: 'douyu', cid: '999', categoryName: ''), isFalse);
    });

    test('分类名全等命中', () {
      expect(lol.matches(site: 'bilibili', cid: '86', categoryName: '英雄联盟'), isTrue);
      expect(lol.matches(site: 'bilibili', cid: '86', categoryName: 'LOL'), isTrue);
    });

    test('排除词优先生效:lol云顶之弈 不属于 LOL', () {
      expect(lol.matches(site: 'huya', cid: '5485', categoryName: 'lol云顶之弈'), isFalse);
    });

    test('空分类名且无 cid 白名单时不命中', () {
      expect(lol.matches(site: 'kuaishou', cid: '1', categoryName: ''), isFalse);
    });
  });

  group('CrossCatalog', () {
    const catalog = CrossCatalog();

    test('byKey 命中与未命中', () {
      expect(catalog.byKey('lol')?.name, '英雄联盟');
      expect(catalog.byKey('not-exist'), isNull);
      expect(catalog.byKey(null), isNull);
    });

    test('旧 key 经归一仍可命中(兼容旧 deeplink)', () {
      // 这些旧 cross key 已不在索引里,但 alias 归一后必须落到新 key。
      expect(catalog.byKey('wangzhe')?.name, '王者荣耀');
      expect(catalog.byKey('heping')?.name, '和平精英');
      expect(catalog.byKey('csgo')?.name, 'CS2');
      expect(catalog.byKey('genshin')?.name, '原神');
      expect(catalog.byKey('crossfire')?.name, '穿越火线');
      expect(catalog.byKey('outdoor')?.name, '户外');
      expect(catalog.byKey('chat')?.name, '星秀');
    });

    test('match 把 lol云顶之弈 归入 tft(云顶之弈),无畏契约归入 valorant', () {
      expect(
        catalog.match(site: 'huya', cid: '5485', categoryName: 'lol云顶之弈')?.key,
        'tft',
      );
      expect(
        catalog.match(site: 'huya', cid: '5937', categoryName: '无畏契约')?.key,
        'valorant',
      );
    });

    test('match 未知分类返回 null', () {
      expect(catalog.match(site: 'douyu', cid: '999999', categoryName: '某某新游'), isNull);
    });

    test('新 key 的站点 cid 命中(sjz 斗鱼4133 / dwrg 斗鱼356)', () {
      // cid 白名单优先于名称:用无关名称验证 cid 精确命中。
      expect(
        catalog.match(site: 'douyu', cid: '4133', categoryName: '无关名称')?.key,
        'sjz',
      );
      expect(
        catalog.match(site: 'huya', cid: '9449', categoryName: '三角洲行动')?.key,
        'sjz',
      );
      expect(
        catalog.match(site: 'douyu', cid: '356', categoryName: '第五人格')?.key,
        'dwrg',
      );
      expect(
        catalog.match(site: 'huya', cid: '3115', categoryName: '无关名称')?.key,
        'dwrg',
      );
    });

    test('toCategoryResult 输出全平台分类索引,cid 即 cross key', () {
      final result = catalog.toCategoryResult();
      expect(result.site, 'all');
      expect(result.groups, hasLength(1));
      final items = result.groups.single.items;
      expect(items.first.cid, 'lol');
      expect(items.map((e) => e.cid), containsAll(_kHotKeys));
      for (final item in items) {
        expect(item.cid, isNotEmpty);
        expect(item.name, isNotEmpty);
      }
    });

    /// 哨兵:防止将来漏 key 静默降级。
    ///
    /// 背景:`/all/category/<key>` 用 [CrossCatalog.byKey] 精确匹配;一旦某 key
    /// 从索引里漏掉,`category` 变 null → 该分类过滤被整体跳过,退化成「全平台不过滤
    /// 混排」——比空列表更危险(语义错误而非无结果)。本断言锁死键集、顺序与会展名,
    /// 任何偏离都会立刻红。
    test('全平台索引键集/顺序/展示名与 web HOT 25 key 完全一致', () {
      final items = catalog.toCategoryResult().groups.single.items;

      // 1) 数量与顺序必须完全等于 web HOT 列表(顺序即展示顺序)。
      expect(
        items.map((e) => e.cid).toList(),
        _kHotKeys,
        reason: '索引键集与顺序必须对齐 web HOT_CROSS_CATEGORY_KEYS,'
            '否则侧栏分类与 web 不一致,且顺序变化会改版式',
      );

      // 2) 每个 key 必须能被 byKey 命中(否则该分类的 /all/category/<key> 会静默不过滤)。
      // 3) 展示名必须来自映射表的 canonical 中文名(侧栏直接渲染 item.name)。
      for (final key in _kHotKeys) {
        final category = catalog.byKey(key);
        expect(
          category,
          isNotNull,
          reason: 'HOT key "$key" 必须能被 byKey 命中,'
              '否则 /all/category/$key 会退化成全平台不过滤混排',
        );
        expect(
          category!.name,
          _kHotNames[key],
          reason: 'key "$key" 的展示名必须来自映射表的 canonical 中文名',
        );
      }
    });
  });
}
