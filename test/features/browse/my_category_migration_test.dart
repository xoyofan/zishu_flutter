/// 我的分类 v2→v3 救援迁移单测:
/// 中文快照保留、可映射英文快照换中文保留、韩文+错 cid 丢弃、v2 键清理。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/features/browse/application/my_category_provider.dart';

void main() {
  /// seed v2 键并建 container,轮询等迁移完成(迁移完成标志 = v3 键已写入)。
  Future<ProviderContainer> pump({
    required List<Map<String, Object>> legacy,
  }) async {
    final store = InMemorySharedPreferencesAsync.withData(<String, Object>{
      'zishu.myCategories.v2': jsonEncode(legacy),
    });
    SharedPreferencesAsyncPlatform.instance = store;
    final prefs = SharedPreferencesAsync();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(myCategoriesProvider);
    for (var i = 0; i < 100; i++) {
      if (container.read(myCategoriesProvider).isNotEmpty &&
          await prefs.getString('zishu.myCategories.v3') != null) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return container;
  }

  test('中文快照保留、可映射英文换中文保留、韩文坏条丢弃、v2 键删除', () async {
    final container = await pump(legacy: const [
      // 中文好条目(播放页收藏,cid 可能错但 name 是中文展示名)→ 保留。
      {'site': 'soop', 'cid': 'phonics1', 'name': '英雄联盟'},
      // twitch 英文旧快照,cid 命中跨平台表 → 换中文保留。
      {'site': 'twitch', 'cid': 'maplestory', 'name': 'maplestory'},
      // soop 播放页错绑「房间号 cid + 韩文快照」→ 丢弃。
      {'site': 'soop', 'cid': 'phonics1', 'name': '포로/걸렘'},
      // 非法条目 → 丢弃。
      {'site': '', 'cid': '', 'name': '无效条目'},
    ]);
    final prefs = SharedPreferencesAsync();

    final entries = container.read(myCategoriesProvider);
    expect(
      entries.map((e) => (e.site, e.cid, e.name)).toList(),
      [
        ('soop', 'phonics1', '英雄联盟'),
        ('twitch', 'maplestory', '冒险岛'),
      ],
    );

    // 迁移结果固化进 v3,v2 键清理。
    final v3 = await prefs.getString('zishu.myCategories.v3');
    expect(v3, isNotNull);
    expect(jsonDecode(v3!), hasLength(2));
    expect(await prefs.getString('zishu.myCategories.v2'), isNull);
  });

  test('v2 键不存在时不做任何写入', () async {
    final store = InMemorySharedPreferencesAsync.withData(const {});
    SharedPreferencesAsyncPlatform.instance = store;
    final prefs = SharedPreferencesAsync();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(myCategoriesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(myCategoriesProvider), isEmpty);
    expect(await prefs.getString('zishu.myCategories.v3'), isNull);
  });
}
