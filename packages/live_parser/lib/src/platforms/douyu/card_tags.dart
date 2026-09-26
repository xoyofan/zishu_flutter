/// 斗鱼卡片角标与特色标签:`icv3` → 封面右上身份位,`roomLabel` → chips 行。
///
/// 2026-09-26 实测(探针 `tool/_probe_douyu_cards.dart`,非推断):
/// - 列表接口 `gapi/rknc/directory/mixListV1`(官网 `window.$DATA.pagePath`
///   用的就是它)的条目带 `icv3`;旧 `gapi/rkc/directory/mixList` 无此字段,
///   故浏览列表改走 V1(字段名与其余取值不变,见 `browse.dart`)。
/// - `icv3[i].cfgRich.text` 即官网页面渲染的左上角标文案,取值域实测:
///   段位LV4/段位LV5/段位LV6、全站十大、全站冠军、全站亚军、全站榜TOP3/
///   TOP10、分区榜TOP1/TOP2/TOP3、分区冠军、分区季军、百钻成就。
///   实测每条都是 `cfgType=2` 富文本;官网按 12px 整文渲染不截断,最宽
///   「全站榜TOP10」8 字,故这里只留 10 字防御上限,不按 6 字砍。
/// - `roomLabel` 是特色标签数组(如「炉石金牌讲师」「5千贵宾」),官网渲染在
///   标题下的单行 18px 容器(`.DyLiveCardTitle-cardSubTitle`,实测
///   `overflow:hidden` + `white-space:nowrap`),放不下的直接裁掉。实测
///   单房最多 22 个、最长 6 字,故这里按 6 字截断并只取前 3 个。
library;

import '../../models/models.dart';
import 'json_utils.dart';
import 'promo_tag.dart';

/// 身份位文案防御上限(官网不截断,实测最宽 8 字)。
const int kDouyuIdentityMaxLen = 10;

/// 卡片 chips 行最多几个特色标签(官网单行容器放不下更多)。
const int kDouyuCardMaxChips = 3;

/// 封面右上身份位文案:icv3 里第一条有文案的角标;无则 null(不渲染)。
String? pickDouyuIdentityLabel(Map<String, dynamic> item) {
  for (final icon in jsonListOf(item['icv3'])) {
    final text = jsonText(jsonMapOf(jsonMapOf(icon)['cfgRich'])['text']).trim();
    if (text.isEmpty) continue;
    return truncatePromoTag(text, kDouyuIdentityMaxLen);
  }
  return null;
}

/// 封面下方 chips 行的特色标签:roomLabel 顺序取前 [kDouyuCardMaxChips] 个,
/// 同名去重。斗鱼标签不带分类 id,故 kind=tag 且不可点(filterCid 为空)。
List<SiteChip> douyuCardChips(Map<String, dynamic> item) {
  final chips = <SiteChip>[];
  final seen = <String>{};
  for (final raw in jsonListOf(item['roomLabel'])) {
    final name = jsonText(raw).trim();
    if (name.isEmpty || !seen.add(name)) continue;
    chips.add(
      SiteChip(
        id: 'dy:$name',
        name: truncatePromoTag(name),
        kind: SiteChipKind.tag,
      ),
    );
    if (chips.length >= kDouyuCardMaxChips) break;
  }
  return chips;
}
