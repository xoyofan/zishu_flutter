/// 虎牙**房间级**粉丝牌资源(`wupui/getResourceInfo`)的解码与 URL 拼装。
///
/// 真源 = 虎牙官网自己的前端(main3 包,2026-09-26 取证):
/// - 请求:`assets/modules/roomCustomBadge/index.ts` 的
///   `send("wupui", "getResourceInfo", {tUserId, sScene:"web", lPid}, Rsp)`。
/// - 结构体字段号:官网 `assets/modules/taf/structs/ResourceManagerServant.js`
///   里的 Tars 生成代码(**逐字段核对**,非推断):
///   ```js
///   GetResourceInfoReq { 0: UserId tUserId, 1: string sScene,
///                        2: string sVersion, 3: int64 lPid }
///   GetResourceInfoRsp { 0: vector<UniformResourceInfo> vResource,
///                        1: string sVersion, 2: int32 iRetCode,
///                        3: string sMsg, 4: int32 iAllResource }
///   UniformResourceInfo { 0: int32 iBizType,
///                         1: vector<UniformResourceItem> vItem,
///                         2: vector<string> vDeletedId }
///   UniformResourceItem { 0: string sId, 1: int32 iType,
///                         2: vector<byte> vData, 3: int32 iLoadType }
///   ```
///   官网 `assets/modules/taf/structs/gameLiveBase.js`:
///   ```js
///   CommonFansBadgeSplitResource { 0: int32 iMaxBadgeLevel,
///                                 1: CommonFansBadgeSplitCommResource tCommonBadge,
///                                 2: CustomFansBadgeCommResource tCustomBadgeComm }
///   CommonFansBadgeSplitCommResource { 0: string sFloorUrl,
///                                     1: string sIdentitySuffixUrl,
///                                     2: string sAppZipUrl }
///   ```
/// - 枚举 `assets/modules/taf/structs/ServerCommon.js`:
///   `EUniformResourceBiz_CommonFansBadgeSplit = 14`、
///   `EUniformResourceDataType_CommonFansBadgeSplit = 14`。
/// - URL 拼装:`CustomFansBadge.getNormalBadgeIconUrl`(同 index.ts):
///   ```js
///   p = tCommonBadge?.sFloorUrl || conf.LT   // LT = webui/fansBadge/3/<size>/<dark>/<level>.name
///   g = tCommonBadge?.sIdentitySuffixUrl || conf.M$  // M$ = webui/fansBadge/3/v2/<identity>.png
///   T = size<=2 ? 2 : size
///   floorUrl = p.replace(/<identity>/, sfid||type).replace(/<dark>/, grey?1:0)
///               .replace(/<level>/, level).replace(/<size>/, T).replace(/<ua>/, ua)
///               .replace(/\.name$/, level>=21 && supportWebp ? ".webp" : ".png")
///   identityUrl = g.replace(/<identity>/, sfid||type).replace(/<dark>/, grey?1:0)
///                  .replace(/<ua>/, ua).replace(/\.name$/, ".png")
///   ```
///
/// 2026-09-26 实测(房间 333003 / 9999,探针见
/// `tool/_probe_huya_resource_info.dart`):
/// - 只发 `{tUserId, sScene:"web"}` 即返回完整 7 类资源(915450B),
///   加任意 `lPid` 候选(tag 3/4/6)响应字节**完全一致**;两个不同房间
///   (uid 2367547387 / 1339475571)返回字节亦完全一致 → `CommonFansBadgeSplit`
///   的底图模板是**全局**的,不含房间专属 hash。故本实现**不发 lPid**,
///   避免把未探明的字段号写成既成事实。
/// - 实测模板:`.../web_admin_badgeDefaultFloorUrl/{hash}/<size>_<ua>_<dark>_<level>.name`
///   与 `.../web_admin_badgeDefaultIdentityUrl/{hash}/<ua>_<dark>_<identity>.name`;
///   `2_3_0_15.png`、`2_3_1_15.png`、`3_3_0_21.webp`、`2_3_0_52.webp` 均 200。
/// - `sScene` 取值决定响应规模(实测 web=915450B / pc=914616B / h5=73994B,
///   未知值返回 22B 空包);官网用 `"web"`,本实现同。
library;

import 'dart:typed_data';

import 'huya_chat_badges.dart';
import 'tars_codec.dart';
import 'tars_exception.dart';

/// `EUniformResourceBiz_CommonFansBadgeSplit`(ServerCommon.js)。
const int kHuyaResourceBizCommonFansBadgeSplit = 14;

/// `EUniformResourceDataType_CommonFansBadgeSplit`(ServerCommon.js)。
const int kHuyaResourceDataTypeCommonFansBadgeSplit = 14;

/// 定制粉丝牌资源(实测 bizType=12,官方枚举名未确证,按模板形状锚定:
/// tag2 三串与 `@huyafed/custom-badge` 的 `sLevelUrl/sSFUrl/sFloorAstrict`
/// 逐位吻合,见 `HuyaFansBadgeResource.custom*` 注释)。
const int kHuyaResourceBizCustomFansBadgeSplit = 12;

const int kHuyaResourceDataTypeCustomFansBadgeSplit = 12;

/// 粉丝牌尺寸缺省值:官网 `fans-icon` 的 `size` 默认 2 且钳制
/// `size<=2 ? 2 : size`(`CustomBadge.getAssets` 同样默认 2)。
const int kHuyaFansBadgeDefaultSize = 2;

/// 房间级粉丝牌资源:只保留通用牌(`tCommonBadge`)的三个 URL 与最高等级。
///
/// 空 [floorUrlTemplate] = 该房间(实为全局)未取到资源,调用方**必须降级**,
/// 不得自造底图。
class HuyaFansBadgeResource {
  const HuyaFansBadgeResource({
    required this.floorUrlTemplate,
    required this.identityTemplate,
    required this.maxBadgeLevel,
    this.customFloorTemplate = '',
    this.customLevelUrlTemplate = '',
  });

  /// `tCommonBadge.sFloorUrl`(含 `<identity>/<dark>/<level>/<size>/<ua>`)。
  final String floorUrlTemplate;

  /// `tCommonBadge.sIdentitySuffixUrl`(含 `<identity>/<dark>/<ua>`)。
  final String identityTemplate;

  /// `iMaxBadgeLevel`(实测 52;0 = 未取到)。
  final int maxBadgeLevel;

  /// **定制粉丝牌底图**模板(实测 biz12 tag2.tag2,官网
  /// `@huyafed/custom-badge` 的 `sFloorAstrict`):
  /// `.../web_admin_badgeNewFloorResource/{hash}/<size>_<ua>_<status>_<sfmark>_<level>.webp`。
  /// 空 = 该资源未下发,定制牌降级用 [floorUrlTemplate](通用底图)。
  final String customFloorTemplate;

  /// **定制粉丝牌等级数字图**模板(实测 biz12 tag2.tag0,官网 `sLevelUrl`):
  /// `.../web_admin_badgeAppLevelResource/{hash}/<ua>_<level>.png`。
  /// NewFloor 是空底框,等级数字必须用本图叠加(官网 `<img class=Lv>`)。
  final String customLevelUrlTemplate;

  /// 能否拼出官方底图(模板非空且含 `<level>` 占位符)。
  bool get hasFloorTemplate =>
      floorUrlTemplate.isNotEmpty &&
      (floorUrlTemplate.contains('<level>') ||
          floorUrlTemplate.contains('&lt;level&gt;'));

  /// 官方身份后缀图 URL(空模板 → 空串,调用方回落官网硬编码常量)。
  String identityUrl(int identity, {int dark = 0}) => huyaFansIdentityUrl(
    identity,
    template: identityTemplate.isEmpty
        ? kHuyaFansIdentityUrlTemplate
        : identityTemplate,
    dark: dark,
    ua: kHuyaFansBadgeUa,
  );
}

/// 纯函数:按官网 `getNormalBadgeIconUrl` 的 floorUrl 分支拼官方底图。
///
/// [dark] 对应官网 `grey`(协议 `BadgeInfo.iExtinguished@26`,1 = 熄灭)、
/// [identity] 对应 `sfid || type`(协议 `tExternal.iFansIdentity@25` 优先,
/// 否则 `iBadgeType@17`)、[size] 对应 `tExternal.iBadgeSize@25` 并被官网钳制为
/// `max(size, 2)`。`.name` 结尾按 `level>=21` 换 `.webp`(其余 `.png`)——
/// 官网额外要求 `supportWebp`,桌面端恒真,与 `ua=3` 同源。
///
/// 模板为空 / 无 `<level>` 占位符 → 返回 ''(调用方降级,禁止自造底图)。
String huyaFansBadgeFloorUrl({
  required String template,
  required int level,
  int identity = 0,
  int size = 2,
  int dark = 0,
  bool supportWebp = true,
  int ua = kHuyaFansBadgeUa,
}) {
  if (level <= 0 ||
      (!template.contains('<level>') && !template.contains('&lt;level&gt;'))) {
    return '';
  }
  final safeSize = size <= 2 ? 2 : size;
  var url = template;
  void fill(String tag, String value) {
    url = url
        .replaceAll(tag, value)
        .replaceAll('&lt;${tag.substring(1, tag.length - 1)}&gt;', value);
  }

  fill('<identity>', '$identity');
  fill('<dark>', '${dark > 0 ? 1 : 0}');
  fill('<level>', '$level');
  fill('<size>', '$safeSize');
  fill('<ua>', '$ua');
  final extension = level >= 21 && supportWebp ? '.webp' : '.png';
  return url.replaceFirst(RegExp(r'\.name$'), extension);
}

/// 解析 `getResourceInfo` 响应的 `tRsp` 字节(泛型资源包)。
///
/// 结构不符 / 缺 `CommonFansBadgeSplit` → 返回 null(调用方降级,不伪造)。
/// biz14(通用粉丝牌)与 biz12(定制粉丝牌模板)合并产出;只抛
/// [TarsDecodeException] 之外的错误不做处理:内部已逐层 try 包裹。
HuyaFansBadgeResource? parseHuyaResourceInfoResponse(Uint8List tRsp) {
  HuyaFansBadgeResource? common;
  ({String floor, String level})? custom;
  void visit(Uint8List tRsp) {
    TarsReader(tRsp).readStruct(0, (rsp) {
      rsp.readStructList(0, (item) {
        final bizType = item.readInt(0);
        var payload = Uint8List(0);
        item.readStructList(1, (entry) {
          final dataType = entry.readInt(1);
          if (dataType == kHuyaResourceDataTypeCommonFansBadgeSplit ||
              dataType == kHuyaResourceDataTypeCustomFansBadgeSplit) {
            payload = entry.readBytes(2);
          }
        });
        if (payload.isEmpty) return;
        if (bizType == kHuyaResourceBizCommonFansBadgeSplit) {
          common = _parseCommonFansBadgeSplit(payload);
        } else if (bizType == kHuyaResourceBizCustomFansBadgeSplit) {
          custom = _parseCustomFansBadgeSplit(payload);
        }
      });
    });
  }

  try {
    visit(tRsp);
  } on TarsDecodeException {
    return null;
  }
  if (common == null && custom == null) return null;
  return HuyaFansBadgeResource(
    floorUrlTemplate: common?.floorUrlTemplate ?? '',
    identityTemplate: common?.identityTemplate ?? '',
    maxBadgeLevel: common?.maxBadgeLevel ?? 0,
    customFloorTemplate: custom?.floor ?? '',
    customLevelUrlTemplate: custom?.level ?? '',
  );
}

/// `CommonFansBadgeSplitResource` → 只留 `tCommonBadge` 的三个 URL。
HuyaFansBadgeResource? _parseCommonFansBadgeSplit(Uint8List bytes) {
  String floor = '';
  String identity = '';
  var maxLevel = 0;
  try {
    TarsReader(bytes).readStruct(0, (r) {
      maxLevel = r.readInt(0);
      r.readStruct(1, (common) {
        floor = common.readString(0);
        identity = common.readString(1);
      });
    });
  } on TarsDecodeException {
    return null;
  }
  if (floor.isEmpty && identity.isEmpty) return null;
  return HuyaFansBadgeResource(
    floorUrlTemplate: floor,
    identityTemplate: identity,
    maxBadgeLevel: maxLevel,
  );
}

/// 定制粉丝牌模板包(实测 biz12,2026-09-27 房间 518518 探针):
/// ```
/// { 0: int iMaxBadgeLevel,
///   1: struct{0 str sFloorUrl(NewIdentity…<size>_<ua>_<identity>_<dark>_<level>),
///             1 str zip},
///   2: struct{0 str sLevelUrl (AppLevel…<ua>_<level>.png)   ← 等级数字图
///             1 str sSFUrl     (NewSf…<size>_<ua>_<sfflag>.png)
///             2 str sFloorAstrict(NewFloor…<size>_<ua>_<status>_<sfmark>_<level>.webp)} }
/// ```
/// 与官网 `@huyafed/custom-badge` 的 `getAssets` 消费字段(sLevelUrl/sSFUrl/
/// sFloorAstrict)逐位吻合;只取定制牌要用的两串。
({String floor, String level})? _parseCustomFansBadgeSplit(Uint8List bytes) {
  String floor = '';
  String level = '';
  try {
    TarsReader(bytes).readStruct(0, (r) {
      r.readStruct(2, (customComm) {
        level = customComm.readString(0);
        customComm.readString(1);
        floor = customComm.readString(2);
      });
    });
  } on TarsDecodeException {
    return null;
  }
  if (floor.isEmpty && level.isEmpty) return null;
  return (floor: floor, level: level);
}

/// 纯函数:按官网 `CustomBadge.getAssets` 的 `sFloorAstrict` 分支拼
/// **定制粉丝牌底图**(NewFloor 空底框,等级数字与团名由 UI 叠加)。
///
/// [sfMark] = `tSuperFansInfo.iSFFlag > 0 ? 1 : 0`;[status] 官网由
/// `tFloorControl.iSFEffectLevel` 与等级比较得出(2 = 特效档),定制包未
/// 下发 per-badge 控制时官网实测特技牌恒 2,非超粉恒 1 —— 以 [status]
/// 显式传入。模板缺 `<status>` 占位符视为不可用 → 返回 ''(调用方降级)。
String huyaCustomBadgeFloorUrl({
  required String template,
  required int level,
  int size = kHuyaFansBadgeDefaultSize,
  int ua = kHuyaFansBadgeUa,
  int sfMark = 0,
  int status = 1,
}) {
  if (level <= 0 || !template.contains('<status>')) return '';
  final safeSize = size <= 2 ? 2 : size;
  return template
      .replaceAll('<size>', '$safeSize')
      .replaceAll('&lt;size&gt;', '$safeSize')
      .replaceAll('<ua>', '$ua')
      .replaceAll('&lt;ua&gt;', '$ua')
      .replaceAll('<status>', '${status > 0 ? status : 1}')
      .replaceAll('&lt;status&gt;', '${status > 0 ? status : 1}')
      .replaceAll('<sfmark>', '${sfMark > 0 ? 1 : 0}')
      .replaceAll('&lt;sfmark&gt;', '${sfMark > 0 ? 1 : 0}')
      .replaceAll('<level>', '$level')
      .replaceAll('&lt;level&gt;', '$level');
}

/// 纯函数:定制粉丝牌**等级数字图**(AppLevel `<ua>_<level>.png`)。
/// NewFloor 底框不含数字,官网以独立 `<img class=Lv>` 叠加;模板为空 /
/// 等级非法 → ''(不叠加)。
String huyaCustomBadgeLevelUrl({
  required String template,
  required int level,
  int ua = kHuyaFansBadgeUa,
}) {
  if (level <= 0 || !template.contains('<level>')) return '';
  return template
      .replaceAll('<ua>', '$ua')
      .replaceAll('&lt;ua&gt;', '$ua')
      .replaceAll('<level>', '$level')
      .replaceAll('&lt;level&gt;', '$level');
}
