/// 虎牙官方徽章 URL 纯函数契约(`huya_chat_badges.dart`)。
///
/// 真源 = 虎牙官网自己的前端(2026-09-26 取证):
/// - `components/ConsumeLevelBadge/index.tsx`
/// - `assets/modules/conf` 常量 `C`(身份后缀图模板)
/// - `widget/fans-icon` + web `fanBadges/huya.ts`(7 档 identity 映射)
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  group('消费等级牌官方 URL', () {
    test('分档目录严格对齐官网 iLevel 区间', () {
      expect(huyaConsumeLevelTier(0), 1);
      expect(huyaConsumeLevelTier(9), 1);
      expect(huyaConsumeLevelTier(10), 10);
      expect(huyaConsumeLevelTier(19), 10);
      expect(huyaConsumeLevelTier(20), 20);
      expect(huyaConsumeLevelTier(29), 20);
      expect(huyaConsumeLevelTier(30), 30);
      expect(huyaConsumeLevelTier(39), 30);
      expect(huyaConsumeLevelTier(40), 40);
      expect(huyaConsumeLevelTier(44), 40);
      expect(huyaConsumeLevelTier(45), 45);
      expect(huyaConsumeLevelTier(49), 45);
      expect(huyaConsumeLevelTier(50), 50);
      expect(huyaConsumeLevelTier(59), 50);
      expect(huyaConsumeLevelTier(60), 60);
      expect(huyaConsumeLevelTier(120), 60);
    });

    test('音色由 iIsPolished 决定,非 NORMAL 样式走 hide 目录', () {
      expect(
        huyaConsumeLevelBadgeUrl(level: 30, badgeStyle: 0, isPolished: 1),
        'https://diy-assets.msstatic.com/consumeLevelBadgeV2/30/light.png',
      );
      expect(
        huyaConsumeLevelBadgeUrl(level: 30, badgeStyle: 0, isPolished: 0),
        'https://diy-assets.msstatic.com/consumeLevelBadgeV2/30/gray.png',
      );
      // 8 档 × 2 音色全覆盖(实测 16 个 URL 全部 200)。
      for (final level in [5, 15, 25, 35, 42, 47, 55, 60]) {
        for (final polished in [0, 1]) {
          final url = huyaConsumeLevelBadgeUrl(
            level: level,
            badgeStyle: 0,
            isPolished: polished,
          );
          expect(
            url,
            'https://diy-assets.msstatic.com/consumeLevelBadgeV2/'
            '${huyaConsumeLevelTier(level)}/${polished == 1 ? 'light' : 'gray'}.png',
          );
        }
      }
      expect(
        huyaConsumeLevelBadgeUrl(level: 30, badgeStyle: 1, isPolished: 1),
        'https://diy-assets.msstatic.com/consumeLevelBadgeV2/hide/light.png',
      );
    });

    test('官网渲染守卫:iLevel=0 且常规样式不渲染', () {
      expect(huyaConsumeLevelBadgeUrl(level: 0, badgeStyle: 0), '');
      expect(
        huyaConsumeLevelBadgeUrl(level: 0, badgeStyle: 1, isPolished: 1),
        'https://diy-assets.msstatic.com/consumeLevelBadgeV2/hide/light.png',
      );
    });

    test('官方图等效尺寸 45x20(90x40 @2x 素材)', () {
      expect(kHuyaConsumeLevelBadgeWidth, 45);
      expect(kHuyaConsumeLevelBadgeHeight, 20);
    });
  });

  group('粉丝牌身份后缀图', () {
    test('官网硬编码模板只替换 <identity>', () {
      expect(
        kHuyaFansIdentityUrlTemplate,
        'https://diy-assets.msstatic.com/webui/fansBadge/3/v2/<identity>.png',
      );
      for (final identity in [1, 2, 3, 4, 11, 12, 13]) {
        expect(
          huyaFansIdentityUrl(identity),
          'https://diy-assets.msstatic.com/webui/fansBadge/3/v2/$identity.png',
        );
      }
      expect(huyaFansIdentityUrl(0), '', reason: '无身份不渲染');
    });

    test('房间级资源模板替换 <identity>/<dark>/<ua> 且 .name → .png', () {
      const template =
          'https://fileserver.cdn.huya.com/web_admin_badgeDefaultIdentityUrl/'
          'hash/<ua>_<dark>_<identity>.name';
      expect(
        huyaFansIdentityUrl(12, template: template),
        'https://fileserver.cdn.huya.com/web_admin_badgeDefaultIdentityUrl/'
            'hash/3_0_12.png',
      );
      expect(
        huyaFansIdentityUrl(12, template: template, dark: 1),
        'https://fileserver.cdn.huya.com/web_admin_badgeDefaultIdentityUrl/'
            'hash/3_1_12.png',
      );
    });
  });

  group('消费等级 → 身份档位回落', () {
    test('7 档映射(web fanBadges/huya.ts resolveHuyaVipEmblemIdentity)', () {
      expect(huyaFansIdentityFallback(0), 0);
      expect(huyaFansIdentityFallback(1), 1);
      expect(huyaFansIdentityFallback(4), 1);
      expect(huyaFansIdentityFallback(5), 2);
      expect(huyaFansIdentityFallback(7), 2);
      expect(huyaFansIdentityFallback(8), 3);
      expect(huyaFansIdentityFallback(10), 3);
      expect(huyaFansIdentityFallback(11), 4);
      expect(huyaFansIdentityFallback(13), 4);
      expect(huyaFansIdentityFallback(14), 11);
      expect(huyaFansIdentityFallback(16), 11);
      expect(huyaFansIdentityFallback(17), 12);
      expect(huyaFansIdentityFallback(19), 12);
      expect(huyaFansIdentityFallback(20), 13);
      expect(huyaFansIdentityFallback(99), 13);
    });
  });
}
