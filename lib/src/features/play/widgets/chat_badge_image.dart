library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Web `SideChatTab.vue` 对徽章/等级/表情图片的统一增强:
/// brightness(1.14) contrast(1.08) saturate(1.1)。Flutter 端用等价
/// 4×5 ColorFilter matrix,避免每个平台重复写滤镜。
const ColorFilter chatWebImageFilter = ColorFilter.matrix(<double>[
  1.328145, -0.088055, -0.008889, 0, -0.1156,
  -0.026175, 1.266265, -0.008889, 0, -0.1156,
  -0.026175, -0.088055, 1.345431, 0, -0.1156,
  0, 0, 0, 1, 0,
]);

/// 聊天徽章本地图片:SFVideoLive `web/public/assets/badges/` 官方素材渲染。
///
/// 路径规则与消费侧对齐 web:
/// - 资产清单:`assets/badges/manifest.json`(honorMax/fansMax/vipEmblems 等,
///   与 web `platformBadgeStatic.ts` 的 `BADGE_STATIC_MANIFEST` 常量一致);
/// - 静态路径映射:web `apps/web/src/utils/badges/platformBadgeStatic.ts`
///   (`badgeStaticUrl(site, kind, level)` 同款分段与上限校验);
/// - 站点分支:web `ChatFanBadge.vue` / `ChatUserLevelBadge.vue`(本地图优先,
///   失败/缺失回落调用方文字态)。
///
/// 本组件只消费打包资产(无网络、无平台依赖);gif 素材若入包,
/// [Image.asset] 原生支持帧动画(当前资产清单无 gif)。

/// 徽章类别:fans=粉丝牌(团牌),userLevel=用户等级(荣誉/消费等级)。
enum ChatBadgeKind { fans, userLevel }

/// 抖音粉丝牌本地图上限(web manifest douyin.fansMax)。
const int kDouyinFansMaxLevel = 20;

/// 抖音荣誉等级本地图上限(web manifest douyin.honorMax)。
const int kDouyinHonorMaxLevel = 75;

/// 抖音荣誉等级(honor)徽章素材的裁剪比例 = 内容区宽度 ÷ 素材高度。
///
/// 官方 `new_user_grade_level_v1_{lv}`(CDN)与本地 `douyin/honor/{lv}.png`
/// 同为 **96×48** 的「图标 + 数字」长胶囊:2026-09-26 逐像素实测 1/5/9/11/21/
/// 30/44/49/60/75 级,内容只占 **x 16..86**(图标起 16,两位数数字止 86),
/// 左右各留 16/10px 纯半透明背景。按原比例渲染(高 21 → 宽 42px)时背景拖出
/// 一条长尾 —— 用户报「粉丝徽章背景太宽」即指此。
///
/// 只保留内容区 + 左右各 3px 内边距 = 素材 76px 宽(高 21 时显示 33.25px)。
const double kDouyinHonorBadgeAspectRatio = 76 / 48;

/// 抖音 honor 横向裁切对齐:内容居中偏左(左留白 16 > 右留白 10),
/// `Alignment.x = 0.2` 即左裁 12px、右裁 8px。
const Alignment kDouyinHonorBadgeCropAlignment = Alignment(0.2, 0);

/// 斗鱼粉丝牌本地图上限(web manifest douyu.fansMax)。
const int kDouyuFansMaxLevel = 50;

/// 按 web `platformBadgeStatic.ts` 规则解析徽章本地资产路径。
///
/// 返回 '' = 该站/类/档位无本地图(调用方应直接走文字态兜底):
/// - douyin fans `assets/badges/douyin/fans/{1..20}.png`(img-only 站);
/// - douyin userLevel `assets/badges/douyin/honor/{1..75}.png`;
/// - douyu fans `assets/badges/douyu/fans/{1..50}.png`(等级绘在官方 PNG 内);
/// - douyu userLevel:斗鱼消费等级 CDN 全 404,web 强制文字 → 恒 '';
/// - huya fans:粉丝牌不使用 v2 emblem(web `huyaFansBadgeStaticUrl` 已废弃)→ '';
/// - huya userLevel `assets/badges/huya/vip/v2/{identity}.png`
///   (消费/VIP emblem,7 档 identity 映射见 [_huyaVipEmblemIdentity]);
/// - bilibili:wealth 本轮不接入;粉丝牌边框走 [bilibiliMedalFrameAssetPath]。
String badgeAssetPath({
  required String site,
  required ChatBadgeKind kind,
  required int level,
}) {
  switch (site) {
    case 'douyin':
      return kind == ChatBadgeKind.fans
          ? _numberedPath('douyin/fans', level, kDouyinFansMaxLevel)
          : _numberedPath('douyin/honor', level, kDouyinHonorMaxLevel);
    case 'douyu':
      if (kind != ChatBadgeKind.fans) return '';
      return _numberedPath('douyu/fans', level, kDouyuFansMaxLevel);
    case 'huya':
      if (kind != ChatBadgeKind.userLevel) return '';
      return 'assets/badges/huya/vip/v2/${_huyaVipEmblemIdentity(level)}.png';
    default:
      return '';
  }
}

/// B 站粉丝牌官方边框图(web `bilibiliMedalFrameStaticUrl`;无协议渐变色时
/// 作底图、团名/等级文字叠层)。
String bilibiliMedalFrameAssetPath() =>
    'assets/badges/bilibili/medal-frame.png';

/// `assets/badges/{dir}/{level}.png`,档位越界返回 ''。
String _numberedPath(String dir, int level, int max) {
  if (level <= 0 || level > max) return '';
  return 'assets/badges/$dir/$level.png';
}

/// 虎牙消费/VIP 等级 → v2 emblem identity
/// (web `resolveHuyaVipEmblemIdentity`:7 档,与官网 VIP 图标一致)。
int _huyaVipEmblemIdentity(int level) {
  final lv = level < 1 ? 1 : level;
  if (lv <= 4) return 1;
  if (lv <= 7) return 2;
  if (lv <= 10) return 3;
  if (lv <= 13) return 4;
  if (lv <= 16) return 11;
  if (lv <= 19) return 12;
  return 13;
}

/// 聊天行徽章本地图:解析失败/无资产 → `SizedBox.shrink` + [onFail]
/// (调用方回落既有文字态);尺寸(高度)由调用方给定。
///
/// 默认 fit 按 kind 给定(web 全部 `object-fit: contain`,此处按 kind 显式
/// 分支,方形素材可改 cover):fans/userLevel 均为 contain;对齐 web
/// `object-position: left center` 左对齐,避免宽牌在窄位里居中裁切。
class ChatBadgeImage extends StatefulWidget {
  const ChatBadgeImage({
    super.key,
    required this.site,
    required this.kind,
    required this.level,
    required this.height,
    this.name,
    this.fit,
    this.src = '',
    this.assetPathOverride,
    this.useDiskCache = true,
    this.maxAspectRatio,
    this.cropAlignment = Alignment.center,
    this.onFail,
  });

  final String site;
  final ChatBadgeKind kind;
  final int level;

  /// 预留:带牌名模板(如虎牙 `3/{size}/{dark}/{level}.{name}`)未来若改为
  /// 本地整牌可消费;当前路径规则未用到。
  final String? name;

  /// 渲染高度(调用方按 web 徽章高 1.15-1.48em @14px ≈ 16-21px 给定)。
  final double height;

  /// 覆写默认 fit(默认 fans/userLevel 均 contain)。
  final BoxFit? fit;

  /// 协议/平台直接下发的远程图 URL,优先于本地静态资源。
  final String src;

  /// 显式资产路径；用于 Bilibili medal-frame 等不走等级编号的固定素材。
  final String? assetPathOverride;

  /// 是否使用磁盘缓存；房间定制徽章可关闭,避免 URL 复用旧图。
  final bool useDiskCache;

  /// 宽度上限 = `height × maxAspectRatio`；null = 不限宽(按素材自身比例)。
  ///
  /// 官方素材常把「徽章内容」画在一张更宽的长胶囊里(左右各留一段纯背景,
  /// 如抖音 honor 是 96×48、内容只占 x 16..86)。按原比例渲染时背景会拖出
  /// 一条长尾,视觉上「背景太宽」。给定上限后改用 [BoxFit.cover] 横向裁掉
  /// 超出部分,保留哪一段由 [cropAlignment] 决定。
  final double? maxAspectRatio;

  /// 横向裁切时保留素材的哪一段([Alignment] 语义:左 = 保留最左)。
  ///
  /// 仅在 [maxAspectRatio] 非空时生效;默认居中。
  final Alignment cropAlignment;

  /// 加载失败/无资产回调(每个失败只回一次;输入变化后重置重试)。
  final VoidCallback? onFail;

  /// 解析后的资产路径('' = 无本地图);暴露给调用方/测试判定图片分支。
  String get assetPath =>
      assetPathOverride ?? badgeAssetPath(site: site, kind: kind, level: level);

  @override
  State<ChatBadgeImage> createState() => _ChatBadgeImageState();
}

class _ChatBadgeImageState extends State<ChatBadgeImage> {
  bool _failed = false;

  @override
  void didUpdateWidget(covariant ChatBadgeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        oldWidget.kind != widget.kind ||
        oldWidget.level != widget.level ||
        oldWidget.name != widget.name ||
        oldWidget.src != widget.src ||
        oldWidget.assetPathOverride != widget.assetPathOverride) {
      // 行复用换内容后允许重新尝试图片(资产确实缺失会在一帧内再次回落)。
      _failed = false;
    }
  }

  /// 失败收敛:置 shrink 并在帧尾回调(禁止 build/errorBuilder 内 setState)。
  void _reportFail() {
    if (_failed || !mounted) return;
    _failed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFail?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final localPath = widget.assetPath;
    // 限宽 = 要横向裁掉素材两侧多余背景:改用 cover + 指定对齐,
    // 宽度由 height × maxAspectRatio 决定(见 [maxAspectRatio])。
    final width = widget.maxAspectRatio == null
        ? null
        : widget.height * widget.maxAspectRatio!;
    final fit = width == null ? (widget.fit ?? _defaultFit(widget.kind)) : BoxFit.cover;
    final alignment = width == null
        ? Alignment.centerLeft
        : widget.cropAlignment;
    if (widget.src.isNotEmpty) {
      final Widget networkImage = widget.useDiskCache
          ? CachedNetworkImage(
              imageUrl: widget.src,
              cacheKey: widget.src,
              width: width,
              height: widget.height,
              fit: fit,
              alignment: alignment,
              filterQuality: FilterQuality.medium,
              placeholder: (_, _) =>
                  SizedBox(width: width, height: widget.height),
              errorWidget: (context, error, stackTrace) {
                if (localPath.isEmpty) {
                  _reportFail();
                  return const SizedBox.shrink();
                }
                return _assetImage(localPath, fit, width, alignment);
              },
            )
          : Image.network(
              widget.src,
              width: width,
              height: widget.height,
              fit: fit,
              alignment: alignment,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                if (localPath.isEmpty) {
                  _reportFail();
                  return const SizedBox.shrink();
                }
                return _assetImage(localPath, fit, width, alignment);
              },
            );
      return ColorFiltered(
        colorFilter: chatWebImageFilter,
        child: networkImage,
      );
    }
    if (localPath.isEmpty) {
      // 无资产:立即渲染 shrink(调用方经 onFail 回文字态)。
      _reportFail();
      return const SizedBox.shrink();
    }
    return _assetImage(localPath, fit, width, alignment);
  }

  Widget _assetImage(
    String path,
    BoxFit fit,
    double? width,
    Alignment alignment,
  ) => ColorFiltered(
    colorFilter: chatWebImageFilter,
    child: Image.asset(
      path,
      width: width,
      height: widget.height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        _reportFail();
        return const SizedBox.shrink();
      },
    ),
  );

  /// 按 kind 的默认 fit:两类素材均为官方整牌(内容含自身描边),contain
  /// 完整呈现;后续若有方形纯图标素材可在分支里改 cover。
  BoxFit _defaultFit(ChatBadgeKind kind) => switch (kind) {
    ChatBadgeKind.fans => BoxFit.contain,
    ChatBadgeKind.userLevel => BoxFit.contain,
  };
}
