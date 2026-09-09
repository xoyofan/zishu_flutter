import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

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

    test('站点 cid 白名单命中(斗鱼 cid2=1)', () {
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
      expect(catalog.byKey('wangzhe')?.name, '王者荣耀');
      expect(catalog.byKey('not-exist'), isNull);
      expect(catalog.byKey(null), isNull);
    });

    test('match 把云顶归入棋牌、无畏契约归入 valorant', () {
      expect(
        catalog.match(site: 'huya', cid: '5485', categoryName: 'lol云顶之弈')?.key,
        'chess',
      );
      expect(
        catalog.match(site: 'huya', cid: '5937', categoryName: '无畏契约')?.key,
        'valorant',
      );
    });

    test('match 未知分类返回 null', () {
      expect(catalog.match(site: 'douyu', cid: '999999', categoryName: '某某新游'), isNull);
    });

    test('toCategoryResult 输出全平台分类索引,cid 即 cross key', () {
      final result = catalog.toCategoryResult();
      expect(result.site, 'all');
      expect(result.groups, hasLength(1));
      final items = result.groups.single.items;
      expect(items.first.cid, 'lol');
      expect(items.map((e) => e.cid), containsAll(['lol', 'wangzhe', 'heping', 'chat']));
      for (final item in items) {
        expect(item.cid, isNotEmpty);
        expect(item.name, isNotEmpty);
      }
    });
  });
}
