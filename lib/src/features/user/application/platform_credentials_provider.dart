/// 平台凭证状态层:按平台读写 + 本机持久化。
///
/// 存储:`SharedPreferencesAsync`,键 `zishu.credentials.<site>`,值 JSON
/// `{value, updatedAt}`(与 `features/follow/application/settings_provider.dart`
/// 同风格的异步 API + 静默降级)。恢复用 `getKeys` 扫前缀,平台增删不会丢数据。
///
/// 安全:值只落本机;**本文件不做任何日志输出**(含异常分支),避免 cookie
/// 串被写进日志/崩溃报告。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show buildSiteRegistry;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/presentation/platform_brands.dart';
import '../domain/platform_credential.dart';

/// 存储键前缀:`zishu.credentials.<site>`。
const String kCredentialKeyPrefix = 'zishu.credentials.';

/// 凭证页列出「需要登录态」的站点在前(顺序即展示优先级)。
///
/// 这两个是当前已知必须带登录态的站点:
/// - `youtube`:出口 IP 被 Google 反爬拦截时需要 cookie;
/// - `xhs`:直播列表需要 `a1` + `web_session`。
const List<String> kCredentialFirstSites = ['youtube', 'xhs'];

/// 平台是否已接入解析(live_parser 注册表里有实现)。
///
/// 用于给用户标注「该平台解析尚未接入」——例如小红书目前只有品牌与图标,
/// 注册表里没有实现;凭证可以先存,解析侧接入后即可直接消费。
bool isParsingImplemented(String site) => buildSiteRegistry()[site] != null;

/// 凭证页列出的平台(排除 `all` 聚合入口,保留品牌目录顺序)。
List<PlatformBrand> credentialSiteBrands() {
  final brands = [
    for (final brand in PlatformBrandCatalog.navPlatforms)
      if (brand.id != PlatformBrandCatalog.all.id) brand,
  ];
  brands.sort((a, b) {
    final ai = kCredentialFirstSites.indexOf(a.id);
    final bi = kCredentialFirstSites.indexOf(b.id);
    if (ai == -1 && bi == -1) return 0;
    if (ai == -1) return 1;
    if (bi == -1) return -1;
    return ai.compareTo(bi);
  });
  return brands;
}

/// 凭证状态:`site → 凭据`;[hydrated] 表示本机存储恢复是否完成。
class PlatformCredentialsState {
  const PlatformCredentialsState({
    this.bySite = const {},
    this.hydrated = false,
  });

  final Map<String, PlatformCredential> bySite;
  final bool hydrated;

  /// 取某平台凭据;未配置返回空快照(不抛)。
  PlatformCredential credentialFor(String site) =>
      bySite[site] ?? PlatformCredential(site: site);

  /// 已配置的平台集合。
  Set<String> get configuredSites => {
    for (final entry in bySite.entries)
      if (entry.value.isConfigured) entry.key,
  };

  PlatformCredentialsState copyWith({
    Map<String, PlatformCredential>? bySite,
    bool? hydrated,
  }) {
    return PlatformCredentialsState(
      bySite: bySite ?? this.bySite,
      hydrated: hydrated ?? this.hydrated,
    );
  }
}

final platformCredentialsProvider =
    NotifierProvider<PlatformCredentialsController, PlatformCredentialsState>(
      PlatformCredentialsController.new,
    );

class PlatformCredentialsController extends Notifier<PlatformCredentialsState> {
  @override
  PlatformCredentialsState build() {
    Future<void>.microtask(_restore);
    return const PlatformCredentialsState();
  }

  /// 从本机恢复:按前缀扫描键,单个键解析失败只跳过该键(不拖垮整页)。
  Future<void> _restore() async {
    try {
      final prefs = SharedPreferencesAsync();
      final keys = await prefs.getKeys();
      final restored = <String, PlatformCredential>{};
      for (final key in keys) {
        if (!key.startsWith(kCredentialKeyPrefix)) continue;
        final site = key.substring(kCredentialKeyPrefix.length);
        if (site.isEmpty) continue;
        try {
          final raw = await prefs.getString(key);
          if (raw == null || raw.isEmpty) continue;
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) continue;
          restored[site] = PlatformCredential.fromJson(site, decoded);
        } catch (_) {
          // 单个键损坏(手改/旧版格式):跳过它,不能让其余平台一起丢。
          continue;
        }
      }
      state = PlatformCredentialsState(bySite: restored, hydrated: true);
    } catch (_) {
      // 平台存储不可用(测试环境未设实现等):静默保留空状态,页面不崩。
      state = state.copyWith(hydrated: true);
    }
  }

  /// 保存某平台凭据(空白值视为无效,直接返回 false 且不写盘)。
  Future<bool> setCredential(String site, String value) async {
    final text = value.trim();
    if (text.isEmpty) return false;
    final credential = PlatformCredential(
      site: site,
      value: text,
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      bySite: {...state.bySite, site: credential},
      hydrated: true,
    );
    try {
      await SharedPreferencesAsync().setString(
        '$kCredentialKeyPrefix$site',
        jsonEncode(credential.toJson()),
      );
    } catch (_) {
      // 写盘失败:内存态仍生效,下次启动回退旧值。
    }
    return true;
  }

  /// 清除某平台凭据(键一并删除,避免残留旧值)。
  Future<void> clearCredential(String site) async {
    state = state.copyWith(
      bySite: {...state.bySite, site: PlatformCredential(site: site)},
      hydrated: true,
    );
    try {
      await SharedPreferencesAsync().remove('$kCredentialKeyPrefix$site');
    } catch (_) {
      // 同上:删除失败只影响下次启动的还原结果。
    }
  }
}
