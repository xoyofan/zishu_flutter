/// 翻译服务的 riverpod 接线:引擎组构建 + 协调器单例 + 文本译文 provider。
///
/// HTTP 用项目已有的 dio(与 `DataServerApi` 同款依赖),fetcher 注入进
/// 纯 Dart 协调器;公共实例不可用时静默回退原文,不打扰 UI。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show UpstreamProxy;

import '../../../features/follow/application/settings_provider.dart';
import 'translation_coordinator.dart';

/// 内置公共实例(志愿者维护,可能失效;设置里可换自建地址):
/// - Lingva:Garuda Linux 与 lunar.icu 社区实例(底层 Google 引擎);
/// - SimplyTranslate:官方实例。
const List<String> kDefaultLingvaBases = [
  'https://lingva.garudalinux.org',
  'https://lingva.lunar.icu',
];
const List<String> kDefaultSimplyTranslateBases = [
  'https://simplytranslate.org',
  'https://translate.jae.fi',
];

/// 翻译专用 fetcher:每次请求独立 HttpClient(低频调用,简单可靠)。
///
/// **必须走上游代理**(BUG 修复 2026-09-20:公共翻译实例
/// lingva/simplytranslate 在直连不可达的网络下全部超时,弹幕永远回退
/// 原文)—— 与解析/弹幕同款消费 [UpstreamProxy]:宿主启动时探测的
/// 系统代理/环境变量在此复用。超时快失败,回退原文。
Future<Object?> _dioFetcher(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  if (UpstreamProxy.enabled) {
    client.findProxy = (uri) => UpstreamProxy.findProxyValue;
  }
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Object?;
  } finally {
    client.close(force: true);
  }
}

/// 引擎组:自定义实例地址(设置项)优先,同时按两种 API 形态探测;
/// 未配置时走内置公共实例,Lingva 在前(响应快)、SimplyTranslate 兜底。
List<TranslationEngine> buildTranslationEngines(String endpoint) {
  final custom = endpoint.trim();
  if (custom.isNotEmpty) {
    return [
      SimplyTranslateEngine(bases: [custom], fetcher: _dioFetcher),
      LingvaEngine(bases: [custom], fetcher: _dioFetcher),
    ];
  }
  return [
    // 首选:Google 网页翻译端点(走上游代理;志愿者实例近年大面积失效)。
    GoogleWebEngine(fetcher: _dioFetcher),
    LingvaEngine(bases: kDefaultLingvaBases, fetcher: _dioFetcher),
    SimplyTranslateEngine(
      bases: kDefaultSimplyTranslateBases,
      fetcher: _dioFetcher,
    ),
  ];
}

/// 翻译协调器(应用级)。跟随自定义实例地址设置:变更时重建协调器
/// (内存缓存随之清空,一次性代价)。
final translationCoordinatorProvider = Provider<TranslationCoordinator>((ref) {
  final endpoint = ref.watch(
    settingsProvider.select((s) => s.translationEndpoint),
  );
  final coordinator = TranslationCoordinator(
    engines: buildTranslationEngines(endpoint),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// 单段文本 → 中文译文(autoDispose:聊天行销毁后释放侦听;译文本体
/// 缓存在协调器,行重建不触发重复请求)。
///
/// 关闭开关 / 文本已是中文 / 翻译失败时恒等于原文;加载中也先显示原文。
final translatedTextProvider = FutureProvider.autoDispose
    .family<String, String>((ref, text) {
      final enabled = ref.watch(
        settingsProvider.select((s) => s.translationEnabled),
      );
      if (!enabled || !needsChineseTranslation(text)) {
        return Future.value(text);
      }
      return ref.watch(translationCoordinatorProvider).translate(text);
    });

/// 主播名 → 中文(仅韩文/日文名翻,英文与中文名原样,见
/// [needsNameTranslation])。整体一名一次请求,与正文分段无关。
final translatedAnchorNameProvider = FutureProvider.autoDispose
    .family<String, String>((ref, name) {
      final enabled = ref.watch(
        settingsProvider.select((s) => s.translationEnabled),
      );
      if (!enabled || !needsNameTranslation(name)) {
        return Future.value(name);
      }
      return ref.watch(translationCoordinatorProvider).translate(name);
    });
