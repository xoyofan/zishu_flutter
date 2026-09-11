/// 首页左栏折叠偏好:Notifier + shared_preferences 持久化。
///
/// 对齐参考实现 SFVideoLive `utils/ui/drawerPref.ts`(`zishu/directoryDrawer`
/// 全局偏好,`{ open: true }` 默认展开):启动时异步读盘,首次启动/读盘失败
/// 一律回退「展开」,不阻塞 UI;每次开合立即写盘。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 左栏折叠偏好控制器:仅承载「展开/收起」一个布尔量。
class SidebarPrefController extends Notifier<bool> {
  /// SharedPreferencesAsync 的存储键(带前缀与模块名避免冲突)。
  static const String storageKey = 'zishu.browse.sidebarOpen';

  /// 默认展开(对齐参考 `open: true`)。
  static const bool defaultValue = true;

  @override
  bool build() {
    // 启动时异步恢复;完成前 UI 先使用默认值(展开)。
    Future<void>.microtask(_restore);
    return defaultValue;
  }

  /// 从本地存储恢复;读盘失败静默保留默认值。
  Future<void> _restore() async {
    try {
      final stored = await SharedPreferencesAsync().getBool(storageKey);
      if (stored != null) state = stored;
    } catch (_) {
      // 平台存储不可用等异常:保持默认展开,页面不崩溃。
    }
  }

  /// 写入指定开合状态并持久化(写盘失败时内存态仍生效)。
  Future<void> setOpen(bool open) async {
    state = open;
    try {
      await SharedPreferencesAsync().setBool(storageKey, open);
    } catch (_) {
      // 写盘失败:下次启动回退旧值。
    }
  }

  /// 在开合状态间切换。
  Future<void> toggle() => setOpen(!state);
}

/// 左栏折叠偏好 provider(true = 展开,false = 收起)。
final sidebarOpenProvider =
    NotifierProvider<SidebarPrefController, bool>(SidebarPrefController.new);
