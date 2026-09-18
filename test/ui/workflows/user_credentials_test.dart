/// 「用户 / 平台凭证」页 workflow 测试:平台项渲染、粘贴保存 → 状态变已配置
/// (并落盘)、清除回落、输入校验、账号区匿名提示。
///
/// 宿主:ProviderScope + MaterialApp(ZishuTheme)+ Scaffold —— 真实路由下本页
/// 由 AppShell 提供 Scaffold,这里补等价宿主;authProvider 用替身固定匿名
/// (真实 AuthController 启动链会发网络请求,fake_async 测试环境禁止)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/user/application/platform_credentials_provider.dart';
import 'package:zishu_flutter/src/features/user/views/user_credentials_view.dart';
import 'package:zishu_flutter/src/shared/application/auth_provider.dart';

/// 登录态替身:固定匿名(不触发网络/存储)。
class _AnonymousAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(phase: AuthPhase.anonymous);
}

const Duration _kFrame = Duration(milliseconds: 50);

Future<void> _pumpFrames(WidgetTester tester, [int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// pump 凭证页并等待存储恢复完成(hydrated)。
Future<ProviderContainer> _pumpView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(_AnonymousAuthController.new)],
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: const Scaffold(body: UserCredentialsView()),
      ),
    ),
  );
  await _pumpFrames(tester, 2);

  final container = ProviderScope.containerOf(
    tester.element(find.byType(UserCredentialsView)),
  );
  for (var attempt = 0; attempt < 10; attempt++) {
    if (container.read(platformCredentialsProvider).hydrated) break;
    await tester.pump(_kFrame);
  }
  expect(
    container.read(platformCredentialsProvider).hydrated,
    isTrue,
    reason: '凭证 provider 应在限定帧数内完成本机恢复',
  );
  return container;
}

/// 展开某平台编辑器(折叠态点「配置」)。
Future<void> _expand(WidgetTester tester, String site) async {
  await tester.ensureVisible(find.byKey(Key('user-credential-toggle-$site')));
  await tester.tap(find.byKey(Key('user-credential-toggle-$site')));
  await _pumpFrames(tester, 2);
}

/// 某平台状态徽标上的文案。
String _statusOf(WidgetTester tester, String site) {
  final badge = find.descendant(
    of: find.byKey(Key('user-credential-status-$site')),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(badge.first).data ?? '';
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('渲染:账号区匿名提示 + YouTube/小红书 平台项与未配置徽标', (tester) async {
    await _pumpView(tester);

    expect(find.byKey(const Key('user-credentials-view')), findsOneWidget);
    expect(find.text('用户'), findsOneWidget);
    expect(find.text('未登录 · 点顶栏头像可登录'), findsOneWidget);

    // 平台项:YouTube 与小红书都在(小红书解析未接入需显式标注)。
    expect(find.byKey(const Key('user-credential-youtube')), findsOneWidget);
    expect(find.byKey(const Key('user-credential-xhs')), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('小红书'), findsOneWidget);
    expect(find.text('该平台解析尚未接入'), findsOneWidget);
    expect(_statusOf(tester, 'youtube'), '未配置');
    expect(tester.takeException(), isNull);
  });

  testWidgets('粘贴保存:徽标转已配置 + 显示脱敏摘要 + 落盘', (tester) async {
    final container = await _pumpView(tester);
    final cookie = 'SID=abcde12345; HSID=zyxwvu67890';

    await _expand(tester, 'youtube');
    await tester.enterText(
      find.byKey(const Key('user-credential-input-youtube')),
      cookie,
    );
    await _pumpFrames(tester, 2);
    await tester.tap(find.byKey(const Key('user-credential-save-youtube')));
    await _pumpFrames(tester, 4);

    // provider 生效。
    expect(
      container
          .read(platformCredentialsProvider)
          .credentialFor('youtube')
          .isConfigured,
      isTrue,
    );
    // 写盘证明:内存后端里能看到该键。
    final raw = await SharedPreferencesAsync().getString(
      'zishu.credentials.youtube',
    );
    expect(raw, isNotNull);
    expect(raw, contains('SID=abcde12345'));

    // 收起后仍显示已配置徽标与脱敏摘要(不整串回显)。
    await tester.tap(find.byKey(const Key('user-credential-toggle-youtube')));
    await _pumpFrames(tester, 2);
    expect(_statusOf(tester, 'youtube'), '已配置');
    expect(find.textContaining('SID=abc'), findsNothing);
    expect(find.textContaining('…'), findsWidgets, reason: '脱敏摘要应带省略号');
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入校验:空值与过短内容都不写盘并给出提示', (tester) async {
    final container = await _pumpView(tester);

    await _expand(tester, 'xhs');
    await tester.tap(find.byKey(const Key('user-credential-save-xhs')));
    await _pumpFrames(tester, 2);
    expect(find.text('请先粘贴 Cookie 或 Token'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('user-credential-input-xhs')),
      'a1=x',
    );
    await tester.tap(find.byKey(const Key('user-credential-save-xhs')));
    await _pumpFrames(tester, 2);
    expect(find.text('内容过短,请粘贴完整的 Cookie 串'), findsOneWidget);

    expect(
      container.read(platformCredentialsProvider).configuredSites,
      isEmpty,
      reason: '校验未通过不得落库',
    );
    expect(
      await SharedPreferencesAsync().getString('zishu.credentials.xhs'),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('清除:回到未配置且删除本机键', (tester) async {
    final container = await _pumpView(tester);

    await _expand(tester, 'youtube');
    await tester.enterText(
      find.byKey(const Key('user-credential-input-youtube')),
      'SID=abcde12345; HSID=zyxwvu67890',
    );
    await tester.tap(find.byKey(const Key('user-credential-save-youtube')));
    await _pumpFrames(tester, 3);
    expect(_statusOf(tester, 'youtube'), '已配置');

    await tester.tap(find.byKey(const Key('user-credential-clear-youtube')));
    await _pumpFrames(tester, 3);

    expect(_statusOf(tester, 'youtube'), '未配置');
    expect(container.read(platformCredentialsProvider).configuredSites, isEmpty);
    expect(
      await SharedPreferencesAsync().getString('zishu.credentials.youtube'),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('预置凭据:进页即显示已配置,并可展开回显当前值', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          'zishu.credentials.youtube':
              '{"value":"SID=seeded12345; HSID=seeded","updatedAt":1700000000000}',
        });

    await _pumpView(tester);
    expect(_statusOf(tester, 'youtube'), '已配置');

    await _expand(tester, 'youtube');
    final field = tester.widget<TextField>(
      find.byKey(const Key('user-credential-input-youtube')),
    );
    expect(field.controller?.text, 'SID=seeded12345; HSID=seeded');
    expect(tester.takeException(), isNull);
  });
}
