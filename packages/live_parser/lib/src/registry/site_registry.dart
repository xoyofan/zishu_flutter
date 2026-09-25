/// 站点注册表构建:聚合各平台实现,宿主(Windows app / Dart server)从这里取接口。
library;

import 'package:http/http.dart' as http;

import '../contracts/contracts.dart';
import '../cross/cross_browse.dart';
import '../platforms/bilibili/bilibili_site.dart';
import '../platforms/douyin/douyin_site.dart';
import '../platforms/douyin/room_api.dart';
import '../platforms/douyu/douyu_site.dart';
import '../platforms/huya/huya_site.dart';
import '../platforms/kuaishou/kuaishou_site.dart';
import '../platforms/soop/soop_site.dart';
import '../platforms/twitch/twitch_site.dart';
import '../platforms/youtube/youtube_site.dart';
import '../platforms/yy/yy_site.dart';

/// 构建默认注册表。平台实现按 P1-P7 顺序在此 register。
///
/// 每个注册项同时以 [LiveSite] 薄适配暴露:`registry.site(id)` 返回统一
/// 站点外观(resolveRoom → RoomRecord,可空部件按内层真实能力判定),
/// 旧 `registry[id]` 注册项视图保留到 Windows 切换。
SiteRegistry buildSiteRegistry({
  String douyinCookie = '',
  http.Client? douyinHttpClient,
}) {
  final registry = SiteRegistry();
  final douyinClient = DouyinClient(
    httpClient: douyinHttpClient,
    cookieOverride: douyinCookie,
  );
  registry.register(buildDouyuRegistration());
  registry.register(buildHuyaRegistration());
  registry.register(buildBilibiliRegistration());
  registry.register(buildTwitchRegistration());
  registry.register(buildYyRegistration());
  registry.register(buildSoopRegistration());
  registry.register(buildKuaishouRegistration());
  registry.register(buildDouyinRegistration(client: douyinClient));
  registry.register(buildYoutubeRegistration());
  // 全平台聚合默认只聚合前三站(斗鱼/虎牙/B站);Twitch 等海外站点由宿主按需加入。
  // 全平台聚合放最后:它引用同一 registry 实例,此前的站点都会参与聚合。
  registry.register(buildCrossRegistration(registry: registry));
  return registry;
}
