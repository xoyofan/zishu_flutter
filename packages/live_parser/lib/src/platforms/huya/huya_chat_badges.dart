/// 虎牙聊天徽章的**纯 URL 构造**:消费等级牌 + 粉丝牌身份图标。
///
/// 真源 = 虎牙官网自己的前端(main3 包,2026-09-26 取证):
/// - `components/ConsumeLevelBadge/index.tsx`
///   ```js
///   o = e<10?1 : e<20?10 : e<30?20 : e<40?30 : e<45?40 : e<50?45
///            : e<60?50 : 60;                 // 消费等级分档
///   l = iIsPolished===1 ? "light" : "gray"; // 音色
///   c = iBadgeStyle===E_STYLE_NORMAL ? o : "hide";
///   d = "https://diy-assets.msstatic.com/consumeLevelBadgeV2/" + c + "/" + l + ".png";
///   // 渲染守卫:iLevel===0 && iBadgeStyle===E_STYLE_NORMAL → 不渲染
///   ```
///   官方图 90x40(@2x 素材) = 等效 45x20 CSS px。
///   枚举 `E_STYLE_NORMAL` 所在 chunk 未取到,取值 **0 属推断**:由本仓库
///   既有 `iBadgeStyle` 语义(0 = 常规样式)+ UI 契约测试(常规样式走官方图)
///   共同佐证;非 0 一律按 `hide` 目录取值(实测 `hide/light|gray` 均 200)。
/// - `widget/fans-icon/fans-icon.ts` 的身份后缀图 + `assets/modules/conf`
///   常量 `C = "https://diy-assets.msstatic.com/webui/fansBadge/3/v2/<identity>.png"`
///   (官网硬编码兜底;`identity` 取 `EFansIdentity` 枚举值
///   0/1/2/3/4/11/12/13,7 档实测全部 200)。
///
/// 粉丝牌**底图**不在本文件:它必须来自房间级资源 `wupui/getResourceInfo`
/// 下发的模板,见 `huya_fans_badge_resource.dart`。
library;

/// 消费等级官方图等效宽(90x40 @2x 素材)。
const double kHuyaConsumeLevelBadgeWidth = 45;

/// 消费等级官方图等效高(90x40 @2x 素材)。
const double kHuyaConsumeLevelBadgeHeight = 20;

/// 官网 `EConsumeLevelBadgeStyle.E_STYLE_NORMAL`(推断值,见文件头说明)。
const int kHuyaConsumeLevelStyleNormal = 0;

const String _kConsumeLevelBase =
    'https://diy-assets.msstatic.com/consumeLevelBadgeV2';

/// 消费等级 → 官方图分档目录(官网 `ConsumeLevelBadge/index.tsx` 的 `o`)。
///
/// 实测 8 档(1/10/20/30/40/45/50/60)× light/gray 共 16 个 URL 全部 200。
int huyaConsumeLevelTier(int level) {
  if (level < 10) return 1;
  if (level < 20) return 10;
  if (level < 30) return 20;
  if (level < 40) return 30;
  if (level < 45) return 40;
  if (level < 50) return 45;
  if (level < 60) return 50;
  return 60;
}

/// 消费等级牌官方图 URL;官网判定「不渲染」时返回 ''。
///
/// [level] = `ConsumeLevelBadgeInfo.iLevel`(tag 1)、[badgeStyle] =
/// `iBadgeStyle`(tag 2)、[isPolished] = `iIsPolished`(tag 3)。
String huyaConsumeLevelBadgeUrl({
  required int level,
  int badgeStyle = 0,
  int isPolished = 0,
}) {
  if (level < 0) return '';
  // 官网渲染守卫:`iLevel===0 && iBadgeStyle===E_STYLE_NORMAL` 不渲染。
  if (level == 0 && badgeStyle == kHuyaConsumeLevelStyleNormal) return '';
  final variant = badgeStyle == kHuyaConsumeLevelStyleNormal
      ? '${huyaConsumeLevelTier(level)}'
      : 'hide';
  final tone = isPolished == 1 ? 'light' : 'gray';
  return '$_kConsumeLevelBase/$variant/$tone.png';
}

/// 粉丝牌**身份后缀图**的官网硬编码模板(`assets/modules/conf` 常量 `C`)。
///
/// 优先用房间级资源下发的 `sIdentitySuffixUrl`(同一算法,见
/// [huyaFansIdentityUrl] 的 `template` 参数);本常量只在拿不到资源时兜底。
const String kHuyaFansIdentityUrlTemplate =
    'https://diy-assets.msstatic.com/webui/fansBadge/3/v2/<identity>.png';

/// 身份图标 URL:只替换 `<identity>` 一个占位符(官网兜底模板无其余占位符)。
///
/// 房间级资源模板含 `<ua>/<dark>/<identity>` 三个占位符,按官网
/// `getNormalBadgeIconUrl` 的 identityUrl 分支替换:`<identity>` 取
/// `sfid || type`、`<dark>` 取 `grey?1:0`、`<ua>` 固定 3(webp 支持),
/// 结尾 `.name` 一律换 `.png`(该分支官网不产出 webp)。
String huyaFansIdentityUrl(
  int identity, {
  String template = kHuyaFansIdentityUrlTemplate,
  int dark = 0,
  int ua = kHuyaFansBadgeUa,
}) {
  if (identity <= 0 || template.isEmpty) return '';
  final uaPart = template.contains('<ua>');
  final darkPart = template.contains('<dark>');
  var url = template
      .replaceAll('<identity>', '$identity')
      .replaceAll('&lt;identity&gt;', '$identity');
  if (darkPart) {
    url = url
        .replaceAll('<dark>', '${dark > 0 ? 1 : 0}')
        .replaceAll('&lt;dark&gt;', '${dark > 0 ? 1 : 0}');
  }
  if (uaPart) {
    url = url
        .replaceAll('<ua>', '$ua')
        .replaceAll('&lt;ua&gt;', '$ua');
  }
  return url.replaceFirst(RegExp(r'\.name$'), '.png');
}

/// `<ua>` 取值:官网 `y = {ua:3, supportWebp:isSupportWebp()}`,3 = 支持 webp。
const int kHuyaFansBadgeUa = 3;

/// 消费等级 → 粉丝牌身份档位(7 档)。
///
/// **这是本仓库既有口径**(web `fanBadges/huya.ts` 的
/// `resolveHuyaVipEmblemIdentity`,与 `huya_wup.dart` 文件头同一映射):
/// ≤4→1、≤7→2、≤10→3、≤13→4、≤16→11、≤19→12、其余 13。
///
/// 仅在协议**没有**下发 `tExternal.iFansIdentity` 时兜底 —— 真实语义由
/// 粉丝团配置决定,协议有值时以协议为准。
int huyaFansIdentityFallback(int level) {
  if (level <= 0) return 0;
  if (level <= 4) return 1;
  if (level <= 7) return 2;
  if (level <= 10) return 3;
  if (level <= 13) return 4;
  if (level <= 16) return 11;
  if (level <= 19) return 12;
  return 13;
}
