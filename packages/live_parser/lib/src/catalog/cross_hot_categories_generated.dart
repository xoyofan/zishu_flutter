/// 本文件由 `tool/sync_cross_map.dart` 从
/// `assets/config/cross-categories.json` 自动生成,**请勿手改**。
///
/// 仅含全平台热门 25 key(对齐 web 的 `HOT_CROSS_CATEGORY_KEYS`,
/// 顺序即展示顺序)的基础匹配数据 `{key, name, aliases, siteCids}`;
/// 精细匹配规则(contains/excludes)由 `cross_catalog.dart` 的
/// `_kCrossHotOverlay` 按 key 覆盖。改 web 的 `hotCrossCategories.js`
/// 或 `assets/config/cross-categories.json` 后重跑本脚本。
library;

/// 全平台热门分类种子:可由 JSON 派生的最小匹配数据。
class HotCrossSeed {
  const HotCrossSeed({
    required this.key,
    required this.name,
    required this.aliases,
    required this.siteCids,
  });

  final String key;
  final String name;
  final List<String> aliases;
  final Map<String, List<String>> siteCids;
}

/// 25 个 HOT key(顺序即展示顺序,与 web 一致)。请勿手改;
/// 改 JSON 后重跑 `dart run tool/sync_cross_map.dart`。
const List<HotCrossSeed> kGeneratedHotCrossCategories = [
  HotCrossSeed(
    key: 'lol',
    name: '英雄联盟',
    aliases: ['英雄联盟', 'lol', 'league of legends', '英雄联盟赛事'],
    siteCids: {'douyu': ['1'], 'huya': ['1'], 'bilibili': ['86'], 'twitch': ['league-of-legends'], 'soop': ['00040019']},
  ),
  HotCrossSeed(
    key: 'sjz',
    name: '三角洲行动',
    aliases: ['三角洲行动', '三角洲', 'Delta Force'],
    siteCids: {'douyu': ['4133'], 'huya': ['9449'], 'bilibili': ['878'], 'twitch': ['delta-force-hawk-ops'], 'soop': ['00040250']},
  ),
  HotCrossSeed(
    key: 'jx3',
    name: '剑网3',
    aliases: ['剑网3', '剑网三'],
    siteCids: {'douyu': ['65'], 'huya': ['900'], 'bilibili': ['82']},
  ),
  HotCrossSeed(
    key: 'wzry',
    name: '王者荣耀',
    aliases: ['王者荣耀', '王者'],
    siteCids: {'douyu': ['181'], 'huya': ['2336'], 'bilibili': ['35']},
  ),
  HotCrossSeed(
    key: 'hpjy',
    name: '和平精英',
    aliases: ['和平精英', '吃鸡'],
    siteCids: {'douyu': ['270'], 'huya': ['3203'], 'bilibili': ['256']},
  ),
  HotCrossSeed(
    key: 'cs2',
    name: 'CS2',
    aliases: ['cs2', 'csgo', '反恐精英', 'counter-strike', 'cs:go', 'Counter-Strike 2'],
    siteCids: {'douyu': ['6'], 'huya': ['862'], 'bilibili': ['89'], 'soop': ['00040078']},
  ),
  HotCrossSeed(
    key: 'dota2',
    name: 'DOTA2',
    aliases: ['dota2', 'dota 2', '刀塔', '刀塔2'],
    siteCids: {'douyu': ['7'], 'huya': ['7'], 'bilibili': ['92'], 'twitch': ['dota-2'], 'soop': ['00040082']},
  ),
  HotCrossSeed(
    key: 'cf',
    name: '穿越火线',
    aliases: ['穿越火线', 'cf'],
    siteCids: {'douyu': ['4'], 'huya': ['4'], 'bilibili': ['88']},
  ),
  HotCrossSeed(
    key: 'yjwj',
    name: '永劫无间',
    aliases: ['永劫无间'],
    siteCids: {'douyu': ['1227'], 'huya': ['6219'], 'bilibili': ['666']},
  ),
  HotCrossSeed(
    key: 'ys',
    name: '原神',
    aliases: ['原神', 'Genshin Impact', 'Genshin'],
    siteCids: {'douyu': ['1223'], 'huya': ['5489'], 'bilibili': ['321'], 'twitch': ['genshin-impact'], 'soop': ['00360063']},
  ),
  HotCrossSeed(
    key: 'bhxy',
    name: '崩坏：星穹铁道',
    aliases: ['崩坏：星穹铁道'],
    siteCids: {'douyu': ['3379'], 'huya': ['7349'], 'bilibili': ['549']},
  ),
  HotCrossSeed(
    key: 'aqtw',
    name: '暗区突围',
    aliases: ['暗区突围'],
    siteCids: {'douyu': ['3133'], 'huya': ['7209'], 'bilibili': ['502']},
  ),
  HotCrossSeed(
    key: 'tft',
    name: '云顶之弈',
    aliases: ['云顶之弈', 'lol云顶之弈', 'tft', 'Teamfight Tactics'],
    siteCids: {'douyu': ['917'], 'huya': ['5485'], 'bilibili': ['260'], 'twitch': ['teamfight-tactics']},
  ),
  HotCrossSeed(
    key: 'hs',
    name: '炉石传说',
    aliases: ['炉石传说', '炉石', 'Hearthstone'],
    siteCids: {'douyu': ['393'], 'huya': ['393'], 'bilibili': ['91'], 'twitch': ['hearthstone'], 'soop': ['00040039']},
  ),
  HotCrossSeed(
    key: 'valorant',
    name: '无畏契约',
    aliases: ['无畏契约', 'valorant', '瓦罗兰特'],
    siteCids: {'douyu': ['5937'], 'huya': ['5937'], 'bilibili': ['329'], 'twitch': ['valorant'], 'soop': ['00040110']},
  ),
  HotCrossSeed(
    key: 'dnf',
    name: 'DNF',
    aliases: ['DNF', 'dnf', '地下城与勇士'],
    siteCids: {'douyu': ['40'], 'huya': ['2'], 'bilibili': ['78'], 'soop': ['00040004']},
  ),
  HotCrossSeed(
    key: 'dzpd',
    name: '蛋仔派对',
    aliases: ['蛋仔派对'],
    siteCids: {'douyu': ['3358'], 'huya': ['6909'], 'bilibili': ['571']},
  ),
  HotCrossSeed(
    key: 'dwrg',
    name: '第五人格',
    aliases: ['第五人格'],
    siteCids: {'douyu': ['356'], 'huya': ['3115'], 'bilibili': ['163']},
  ),
  HotCrossSeed(
    key: 'hmwk',
    name: '黑神话：悟空',
    aliases: ['黑神话：悟空'],
    siteCids: {'douyu': ['2075'], 'huya': ['6111'], 'bilibili': ['804']},
  ),
  HotCrossSeed(
    key: 'jcc',
    name: '金铲铲之战',
    aliases: ['金铲铲之战'],
    siteCids: {'douyu': ['2556'], 'huya': ['7185'], 'bilibili': ['514']},
  ),
  HotCrossSeed(
    key: 'jql',
    name: '绝区零',
    aliases: ['绝区零', 'Zenless Zone Zero'],
    siteCids: {'douyu': ['3671'], 'huya': ['7711'], 'bilibili': ['662'], 'twitch': ['zenless-zone-zero']},
  ),
  HotCrossSeed(
    key: 'wudao',
    name: '舞蹈',
    aliases: ['舞蹈', '舞见', '才艺'],
    siteCids: {'douyu': ['175'], 'huya': ['3793'], 'bilibili': ['207']},
  ),
  HotCrossSeed(
    key: 'huwai',
    name: '户外',
    aliases: ['户外', '运动', '生活', '旅游', '体育', 'IRL'],
    siteCids: {'douyu': ['124'], 'huya': ['2165'], 'bilibili': ['368'], 'twitch': ['irl']},
  ),
  HotCrossSeed(
    key: 'xingxiu',
    name: '星秀',
    aliases: ['星秀'],
    siteCids: {'douyu': ['1008'], 'huya': ['1663']},
  ),
  HotCrossSeed(
    key: 'yanzhi',
    name: '颜值',
    aliases: ['颜值', '颜值（横屏）'],
    siteCids: {'douyu': ['201'], 'huya': ['2168'], 'bilibili': ['145']},
  ),
];
