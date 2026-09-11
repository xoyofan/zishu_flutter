/// 站点注册表构建:聚合各平台实现,宿主(Windows app / Dart server)从这里取接口。
library;

import '../contracts/contracts.dart';
import '../cross/cross_browse.dart';
import '../platforms/bilibili/bilibili_site.dart';
import '../platforms/douyin/douyin_site.dart';
import '../platforms/douyu/douyu_site.dart';
import '../platforms/huya/huya_site.dart';
import '../platforms/iptv/iptv_site.dart';
import '../platforms/kuaishou/kuaishou_site.dart';
import '../platforms/soop/soop_site.dart';
import '../platforms/twitch/twitch_site.dart';
import '../platforms/youtube/youtube_site.dart';
import '../platforms/yy/yy_site.dart';

/// 构建默认注册表。平台实现按 P1-P7 顺序在此 register。
SiteRegistry buildSiteRegistry() {
  final registry = SiteRegistry();
  registry.register(buildDouyuRegistration());
  registry.register(buildHuyaRegistration());
  registry.register(buildBilibiliRegistration());
  // IPTV:播放列表源由宿主注入(远程 URL 或内联 M3U);此处注册空源占位,
  // 宿主构建注册表时使用 buildIptvRegistration(sources: [...]) 替换。
  registry.register(buildIptvRegistration(sources: const []));
  registry.register(buildTwitchRegistration());
  registry.register(buildYyRegistration());
  registry.register(buildSoopRegistration());
  registry.register(buildKuaishouRegistration());
  registry.register(buildDouyinRegistration());
  registry.register(buildYoutubeRegistration());
  // 全平台聚合默认只聚合前三站(斗鱼/虎牙/B站);Twitch 等海外站点由宿主按需加入。
  // 全平台聚合放最后:它引用同一 registry 实例,此前的站点都会参与聚合。
  registry.register(buildCrossRegistration(registry: registry));
  return registry;
}
