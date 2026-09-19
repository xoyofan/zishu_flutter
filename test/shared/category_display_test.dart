/// 跨平台分类显示映射纯函数单测(移植自 SFVideoLive web 实现)。
///
/// 分组覆盖:按 key 命中、key alias 归一、按 cid 命中、按 name/alias 子串命中、
/// 「英雄联盟」不抢「英雄联盟手游」、douyin 特殊分支、douyu cid patch、
/// huya cid alias、无映射回落平台原名、displayCategoryGroupName 对
/// douyu/huya/bilibili/douyin 直接返回原名;另含**全量 328 条表**的规模断言
/// 与非热门分类双向命中样例(证明 displayCategoryName 第二层兜底池是全量表,
/// 而非 parser 侧仅服务 all 索引的 25 热门 key)。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zishu_flutter/src/shared/domain/category_display.dart';
import 'package:zishu_flutter/src/shared/domain/cross_categories_data.dart';

void main() {
  group('跨平台分类显示映射', () {
    test('按 key 命中:lol → 英雄联盟', () {
      final entry = findCrossCategoryByKey('lol');
      expect(entry, isNotNull);
      expect(entry!.name, '英雄联盟');
    });

    test('按 key 命中:huwai → 户外', () {
      expect(findCrossCategoryByKey('huwai')!.name, '户外');
    });

    test('key alias 归一:历史冗长 key "3" → jx3(剑网3)', () {
      expect(resolveCrossCategoryKey('3'), 'jx3');
      expect(findCrossCategoryByKey('3')!.name, '剑网3');
    });

    test('key alias 归一:ZJGAME/zjgame → host', () {
      expect(resolveCrossCategoryKey('ZJGAME'), 'host');
      expect(resolveCrossCategoryKey('zjgame'), 'host');
      expect(findCrossCategoryByKey('ZJGAME')!.name, '主机游戏');
    });

    test('crossCategoryKeysEqual:归一后相等', () {
      expect(crossCategoryKeysEqual('3', 'jx3'), isTrue);
      expect(crossCategoryKeysEqual('lol', 'lol'), isTrue);
    });

    test('crossCategoryKeysEqual:空或不同 key 不相等', () {
      expect(crossCategoryKeysEqual('', ''), isFalse);
      expect(crossCategoryKeysEqual('lol', 'huwai'), isFalse);
    });

    test('按 cid 命中:bilibili.cid=86 → 英雄联盟', () {
      final entry = matchCrossCategoryByCid('bilibili', '86');
      expect(entry, isNotNull);
      expect(entry!.name, '英雄联盟');
    });

    test('按 cid 命中:huya.cid=2165 → 户外', () {
      expect(matchCrossCategoryByCid('huya', '2165')!.name, '户外');
    });

    test('huya cid alias:1964 → host(主机游戏)', () {
      expect(matchCrossCategoryByCid('huya', '1964')!.key, 'host');
      expect(matchCrossCategoryByCid('huya', '1964')!.name, '主机游戏');
    });

    test('huya cid alias:100032 → host(主机游戏)', () {
      expect(matchCrossCategoryByCid('huya', '100032')!.key, 'host');
    });

    test('douyu cid patch:dnf → douyu cid 校正为 40', () {
      expect(findCrossCategoryByKey('dnf')!.douyu, '40');
      expect(douyuCidForCrossKey('dnf'), '40');
    });

    test('douyuCidForCrossKey / huyaCidForCrossKey 回落到平台 cid', () {
      expect(douyuCidForCrossKey('lol'), '1');
      expect(huyaCidForCrossKey('lol'), '1');
      expect(huyaCidForCrossKey('missing', '999'), '999');
    });

    test('按 name 命中:原生中文名「英雄联盟」→ 英雄联盟', () {
      final entry = matchCrossCategoryByName('英雄联盟');
      expect(entry, isNotNull);
      expect(entry!.key, 'lol');
    });

    test('按 alias 子串命中:league of legends → 英雄联盟', () {
      final entry = matchCrossCategoryByName('league of legends');
      expect(entry, isNotNull);
      expect(entry!.key, 'lol');
    });

    test('英雄联盟不抢英雄联盟手游:输入「英雄联盟手游」命中独立手游条目', () {
      final mobile = matchCrossCategoryByName('英雄联盟手游');
      expect(mobile, isNotNull);
      expect(mobile!.key, isNot('lol'));
      expect(mobile.name, '英雄联盟手游');
    });

    test('英雄联盟不抢英雄联盟手游:输入「英雄联盟」命中 lol 而非手游', () {
      final entry = matchCrossCategoryByName('英雄联盟');
      expect(entry!.key, 'lol');
    });

    test('douyin 特殊分支:中文名命中映射则返回中文名', () {
      expect(displayCategoryName('douyin', '英雄联盟'), '英雄联盟');
    });

    test('douyin 特殊分支:平台原文(非中文)不强行映射,保留原名', () {
      expect(displayCategoryName('douyin', 'lol'), 'lol');
    });

    test('无映射回落平台原名:bilibili 未知分类返回原串', () {
      expect(displayCategoryName('bilibili', '杂项分类XYZ'), '杂项分类XYZ');
      expect(displayCategoryName('bilibili', ''), '');
    });

    test('displayCategoryName:huya cid=1 配合原生名 lol → 英雄联盟', () {
      expect(displayCategoryName('huya', 'lol', '1'), '英雄联盟');
    });

    test('crossKeyForPlatformCategory:bilibili cid=86 → lol', () {
      expect(crossKeyForPlatformCategory('bilibili', '86', ''), 'lol');
    });

    test('crossKeyForPlatformCategory:无 site/无 cid 无 name 返回空', () {
      expect(crossKeyForPlatformCategory('', '', ''), '');
      expect(crossKeyForPlatformCategory('bilibili', '', ''), '');
    });

    test('formatCategoryHeaderLabel:跨平台 key huwai → 中文「户外」', () {
      expect(formatCategoryHeaderLabel('huya', 'huwai'), '户外');
    });

    test('formatCategoryHeaderLabel:原生中文名原样保留', () {
      expect(formatCategoryHeaderLabel('bilibili', '英雄联盟'), '英雄联盟');
    });

    test('roomCategoryLabel:虎牙原生名 lol → 英雄联盟', () {
      expect(
        roomCategoryLabel('huya', nativeCategory: 'lol', cid: '1'),
        '英雄联盟',
      );
    });

    test('roomCategoryLabel:无原生名时回落空(与 web 一致)', () {
      expect(roomCategoryLabel('bilibili', nativeCategory: '', cid: '86'), '');
    });

    test('displayCategoryGroupName:抖音/斗鱼/虎牙/哔哩哔哩 直接返回平台原名', () {
      expect(displayCategoryGroupName('douyu', '英雄联盟'), '英雄联盟');
      expect(displayCategoryGroupName('huya', 'lol'), 'lol');
      expect(displayCategoryGroupName('bilibili', '英雄联盟'), '英雄联盟');
      expect(displayCategoryGroupName('douyin', 'lol'), 'lol');
    });

    test('displayCategoryGroupName:其余平台走跨平台映射', () {
      expect(displayCategoryGroupName('twitch', 'lol'), '英雄联盟');
    });

    test('displayCategoryName:全平台(all)恒等返回,不做二次映射', () {
      // web 渲染全平台分类列表时从不以 all 调用 displayCategoryName,
      // 索引项 name 已是 canonical 中文名。
      expect(displayCategoryName('all', '英雄联盟', 'lol'), '英雄联盟');
      expect(displayCategoryName('all', '户外', 'huwai'), '户外');
      expect(displayCategoryName('all', '体育', 'sports'), '体育');
    });

    test('回归:「体育」是「户外」的别名,但 all 下不被抢走', () {
      // 平台站仍按别名映射(既有语义不变)。
      expect(displayCategoryName('twitch', '体育'), '户外');
      // 全平台索引恒等 → 侧栏不再出现两个「户外」、「体育」不消失。
      expect(displayCategoryName('all', '体育'), '体育');
      expect(displayCategoryName('all', '体育', 'sports'), '体育');
    });

    test('分组条目:抖音分区 cid 命中 group-danji(单机)', () {
      final entry = matchCrossCategoryByCid('douyin', '1011136');
      expect(entry, isNotNull);
      expect(entry!.key, 'group-danji');
      expect(entry.isGroup, isTrue);
    });

    test('aliasMatchesName:短别名不误抢,长别名可子串', () {
      expect(aliasMatchesName('英雄联盟', '英雄'), isFalse);
      expect(aliasMatchesName('英雄联盟手游', '英雄联盟手游'), isTrue);
      // 别名归一后与输入完全一致 → 命中。
      expect(aliasMatchesName('leagueoflegends', 'league of legends'), isTrue);
      // 短输入(>=4 才允许 a 包含 name)不误抢。
      expect(aliasMatchesName('abc', 'abcdefgh'), isFalse);
    });
  });

  group('全量 cross 表(displayCategoryName 第二层兜底池,328 条)', () {
    // 与 web `hotCrossCategories.js` / `tool/sync_cross_map.dart` 的
    // 25 热门 key 同源;仅用于断言「非热门条目也在兜底池内」。
    const hotKeys = <String>{
      'lol', 'sjz', 'jx3', 'wzry', 'hpjy', 'cs2', 'dota2', 'cf', 'yjwj', 'ys',
      'bhxy', 'aqtw', 'tft', 'hs', 'valorant', 'dnf', 'dzpd', 'dwrg', 'hmwk',
      'jcc', 'jql', 'wudao', 'huwai', 'xingxiu', 'yanzhi',
    };

    test('规模量级:全量表 >= 328 条(若被换成 25 热门表则此断言失败)', () {
      expect(kCrossCategories.length, greaterThanOrEqualTo(328));
    });

    test('key 无重复,非热门条目 >= 300', () {
      final keys = kCrossCategories.map((e) => e.key).toSet();
      expect(keys.length, kCrossCategories.length);
      final nonHot =
          kCrossCategories.where((e) => !hotKeys.contains(e.key)).length;
      expect(nonHot, greaterThanOrEqualTo(300));
    });

    // 以下样例均抽自 web 真源 cross-categories.json 的**非热门**条目,
    // 每个 key 验证「双向」:平台原名/别名 → canonical 中文名;cid → key。
    test('非热门样例均为非 25 热门 key,且都在全量表内', () {
      const samples = <String>[
        'gretro_00040008',
        '14',
        'g3406_5801_1010087_555_elden-ring_00040173',
        'g1887_639_albion-online',
        'g2282_1877_632_black-desert_00040105',
      ];
      for (final key in samples) {
        expect(hotKeys.contains(key), isFalse,
            reason: '样例 $key 应为非热门条目');
        expect(findCrossCategoryByKey(key), isNotNull,
            reason: '样例 $key 应在全量表中');
      }
    });

    test('非热门双向:复古游戏(twitch "Retro")', () {
      expect(displayCategoryName('twitch', 'Retro'), '复古游戏');
      expect(matchCrossCategoryByCid('twitch', 'retro')!.key, 'gretro_00040008');
      expect(
        crossKeyForPlatformCategory('twitch', 'retro', 'Retro'),
        'gretro_00040008',
      );
    });

    test('非热门双向:最终幻想14(douyu 41 / bilibili 102 / 英文别名)', () {
      expect(matchCrossCategoryByName('FINAL FANTASY XIV ONLINE')!.key, '14');
      expect(matchCrossCategoryByCid('douyu', '41')!.key, '14');
      expect(matchCrossCategoryByCid('bilibili', '102')!.key, '14');
    });

    test('非热门双向:艾尔登法环(twitch "ELDEN RING")房间角标', () {
      expect(
        roomCategoryLabel('twitch', nativeCategory: 'Elden Ring',
            cid: 'elden-ring'),
        '艾尔登法环',
      );
      expect(displayCategoryName('twitch', 'ELDEN RING'), '艾尔登法环');
    });

    test('非热门双向:阿尔比恩(twitch "Albion Online")', () {
      expect(
        roomCategoryLabel('twitch', nativeCategory: 'Albion Online'),
        '阿尔比恩',
      );
      expect(
        matchCrossCategoryByCid('twitch', 'albion-online')!.key,
        'g1887_639_albion-online',
      );
    });

    test('非热门双向:黑色沙漠(bilibili cid 632 / 别名 Black Desert)', () {
      expect(displayCategoryName('bilibili', 'Black Desert', '632'), '黑色沙漠');
      expect(matchCrossCategoryByCid('bilibili', '632')!.name, '黑色沙漠');
      expect(matchCrossCategoryByName('black desert')!.key,
          'g2282_1877_632_black-desert_00040105');
    });
  });
}
