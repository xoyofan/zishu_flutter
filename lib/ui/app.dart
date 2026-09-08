/// 应用根：GetMaterialApp + 左侧 70px 导航（对标 SFVideoLive App.vue + NavSidebar）。
///
/// M0 阶段：路由壳 + 占位首页；M3 按视图逐个替换。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'theme/design_tokens.dart';

class ZishuApp extends StatelessWidget {
  const ZishuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '紫薯直播',
      debugShowCheckedModeBanner: false,
      theme: ZishuTheme.light(),
      darkTheme: ZishuTheme.dark(),
      themeMode: ThemeMode.dark, // web 默认暗色
      defaultTransition: Transition.fade,
      getPages: [
        GetPage(name: '/', page: () => const _HomePlaceholder()),
        GetPage(name: '/all', page: () => const _HomePlaceholder()),
        GetPage(name: '/settings', page: () => const _SettingsPlaceholder()),
      ],
      initialRoute: '/all',
    );
  }
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('紫薯直播 · M0 骨架')),
      drawer: const _RailPlaceholder(),
      body: const Center(child: Text('engine/ui 分层已就绪，等待 M1 数据闭环')),
    );
  }
}

class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('设置（M3）')));
}

/// 70px 左导航占位（M3 换成完整 NavSidebar 复刻）。
class _RailPlaceholder extends StatelessWidget implements PreferredSizeWidget {
  const _RailPlaceholder();

  @override
  Size get preferredSize => const Size(ZishuDims.navWidth, double.infinity);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: ZishuDims.navWidth,
        child: const Drawer(child: Center(child: Text('nav'))),
      );
}
