import 'package:flutter/widgets.dart';

/// Font Awesome Free 6 (Solid) 字形常量。
///
/// **为什么用 FA 而不是 Material Icons**：播放页统计行的 VIP / SVIP 在 web 真源里
/// 就是 Font Awesome 的 `crown` / `gem`（见 SFVideoLive
/// `apps/web/src/utils/browse/roomStatIcons.ts` 的 `ROOM_STAT_ICON_FA =
/// { audience: "eye", vip: "crown", svip: "gem" }`）；而 Material Icons **没有**
/// crown / gem 对应字形（只有 `diamond` / `workspace_premium`，语义与形状都不同）。
///
/// 字体资产：`assets/fonts/fa-solid-900.ttf`（Font Awesome Free 6.7.2，许可见
/// `assets/fonts/LICENSE-fontawesome.txt`）。Flutter 会在构建时按使用到的字形
/// tree-shaking，发布包只含下面这三个字形。
///
/// 码点来自 FA 6.7.2 的 `metadata/icons.yml`（`unicodes.secondary`，`10f521`
/// 记法表示 PUA 码位 `f521`），与 FA 官方 v5+ 的码点一致。
abstract final class AppIcons {
  /// FA `eye` —— 「人气 / 观众」列（web `roomStatIconFa('audience')`）。
  static const IconData eye = IconData(0xf06e, fontFamily: 'FontAwesome');

  /// FA `crown` —— 「VIP / 贵宾」列（web `roomStatIconFa('vip')`）。
  static const IconData crown = IconData(0xf521, fontFamily: 'FontAwesome');

  /// FA `gem` —— 「SVIP 档」列（web `roomStatIconFa('svip')`）。
  static const IconData gem = IconData(0xf3a5, fontFamily: 'FontAwesome');
}
