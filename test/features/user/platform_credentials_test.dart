/// 平台凭证存储单测:按平台读写、持久化格式、重建恢复、清除与输入校验。
///
/// 不涉及 UI;后端注入 InMemorySharedPreferencesAsync,与生产使用同一套
/// SharedPreferencesAsync 读写路径。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/features/user/application/platform_credentials_provider.dart';
import 'package:zishu_flutter/src/features/user/domain/platform_credential.dart';

/// 轮询等待启动恢复完成(恢复挂在 build 的 microtask 上)。
Future<void> _awaitHydrated(ProviderContainer container) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (container.read(platformCredentialsProvider).hydrated) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('platformCredentialsProvider 未在限定轮次内完成 hydrated');
}

ProviderContainer _newContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

const String _kYoutubeKey = 'zishu.credentials.youtube';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  test('默认:全部未配置,credentialFor 不抛', () async {
    final container = _newContainer();
    await _awaitHydrated(container);

    final state = container.read(platformCredentialsProvider);
    expect(state.configuredSites, isEmpty);
    expect(state.credentialFor('youtube').isConfigured, isFalse);
    // 未知平台同样返回空快照(不抛、不 null)。
    expect(state.credentialFor('not_a_site').isConfigured, isFalse);
  });

  test('保存:内存态 + 脱敏摘要 + 落 JSON 键', () async {
    final container = _newContainer();
    await _awaitHydrated(container);

    const cookie = 'SID=abcdefghijklmn; HSID=zyxwvutsrqponm';
    final ok = await container
        .read(platformCredentialsProvider.notifier)
        .setCredential('youtube', cookie);
    expect(ok, isTrue);

    final credential = container
        .read(platformCredentialsProvider)
        .credentialFor('youtube');
    expect(credential.isConfigured, isTrue);
    expect(credential.value, cookie);
    expect(credential.updatedAt, isNotNull);
    expect(
      credential.maskedPreview.contains(cookie),
      isFalse,
      reason: '脱敏摘要不得整串回显',
    );
    expect(container.read(platformCredentialsProvider).configuredSites, {
      'youtube',
    });

    final raw = await SharedPreferencesAsync().getString(_kYoutubeKey);
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['value'], cookie);
    expect(decoded['updatedAt'], isA<int>());
  });

  test('重建容器:从本机恢复出已配置的凭证', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          _kYoutubeKey: jsonEncode({
            'value': 'SID=restored; HSID=value',
            'updatedAt': 1700000000000,
          }),
        });

    final container = _newContainer();
    await _awaitHydrated(container);

    final credential = container
        .read(platformCredentialsProvider)
        .credentialFor('youtube');
    expect(credential.value, 'SID=restored; HSID=value');
    expect(
      credential.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  });

  test('损坏的存储内容:跳过该键,不拖垮其它平台', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          _kYoutubeKey: '{ not json',
          'zishu.credentials.xhs': jsonEncode({
            'value': 'a1=abc; web_session=def',
          }),
        });

    final container = _newContainer();
    await _awaitHydrated(container);

    final state = container.read(platformCredentialsProvider);
    expect(state.credentialFor('youtube').isConfigured, isFalse);
    expect(state.credentialFor('xhs').isConfigured, isTrue);
  });

  test('空白值不写盘且返回 false', () async {
    final container = _newContainer();
    await _awaitHydrated(container);

    final ok = await container
        .read(platformCredentialsProvider.notifier)
        .setCredential('youtube', '   ');
    expect(ok, isFalse);
    expect(container.read(platformCredentialsProvider).configuredSites, isEmpty);
    expect(await SharedPreferencesAsync().getString(_kYoutubeKey), isNull);
  });

  test('清除:内存态回落未配置且键被删除', () async {
    final container = _newContainer();
    await _awaitHydrated(container);
    final notifier = container.read(platformCredentialsProvider.notifier);

    await notifier.setCredential('xhs', 'a1=abc; web_session=def');
    expect(
      await SharedPreferencesAsync().getString('zishu.credentials.xhs'),
      isNotNull,
    );

    await notifier.clearCredential('xhs');
    expect(
      container.read(platformCredentialsProvider).credentialFor('xhs').isConfigured,
      isFalse,
    );
    expect(
      await SharedPreferencesAsync().getString('zishu.credentials.xhs'),
      isNull,
    );
  });

  test('credentialSiteBrands:youtube/xhs 优先,且不含 all 聚合入口', () {
    final brands = credentialSiteBrands();
    expect(brands.map((brand) => brand.id).take(2), ['youtube', 'xhs']);
    expect(brands.any((brand) => brand.id == 'all'), isFalse);
    expect(brands.any((brand) => brand.id == 'youtube'), isTrue);
  });

  test('isParsingImplemented:小红书未接入,YouTube 已接入', () {
    expect(isParsingImplemented('youtube'), isTrue);
    expect(isParsingImplemented('xhs'), isFalse);
  });

  test('PlatformCredential:toJson/fromJson 往返 + 空值兜底', () {
    final credential = PlatformCredential(
      site: 'youtube',
      value: 'a=b',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final restored = PlatformCredential.fromJson('youtube', credential.toJson());
    expect(restored.value, 'a=b');
    expect(restored.updatedAt, credential.updatedAt);
    expect(restored.isConfigured, isTrue);
    expect(restored.maskedPreview, '已保存 3 字符');

    final empty = PlatformCredential.fromJson('youtube', const {});
    expect(empty.isConfigured, isFalse);
    expect(empty.maskedPreview, '');
  });
}
