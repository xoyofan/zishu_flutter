/// 跨平台分类显示映射纯函数单测(移植自 SFVideoLive web 实现)。
///
/// 分组覆盖:按 key 命中、key alias 归一、按 cid 命中、按 name/alias 子串命中、
/// 「英雄联盟」不抢「英雄联盟手游」、douyin 特殊分支、douyu cid patch、
/// huya cid alias、无映射回落平台原名、displayCategoryGroupName 对
/// douyu/huya/bilibili/douyin 直接返回原名。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zishu_flutter/src/shared/domain/category_display.dart';

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
}
