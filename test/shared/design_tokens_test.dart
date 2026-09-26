/// design token 契约测试:把 `design_tokens.dart` 的数值钉死在
/// SFVideoLive web 真源上,防止再次漂移。
///
/// 每个断言都标注了 web 真源出处;若本文件失败,先回 web 核对,
/// **不要**直接改断言迁就实现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';

import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/zishu_tokens.dart';

void main() {
  group('AppColors 契约', () {
    test('error 对齐 web --danger(#e55050)', () {
      // 真源:`apps/web/src/styles/theme.css:9` -> `--danger: #e55050;`
      //
      // 注意:主题 token(`zishu_tokens.dart` 的 `error`)早已是 E55050,
      // 只有这条平行常量残留旧值 F56C6C。两者必须一致,否则后续一旦有人
      // 从 `AppColors.error` 取色就会与主题色分叉。
      expect(AppColors.error, const Color(0xFFE55050));
    });
  });

  group('聊天徽章 token 契约', () {
    test('虎牙超粉 V 使用官网金色,浅色主题有独立可读值', () {
      expect(ZishuTokens.dark.chatSuperFan, const Color(0xFFFBBF24));
      expect(ZishuTokens.light.chatSuperFan, const Color(0xFFA16207));
    });

    // 以下数值来自 web 参考实现的 em 折算（1em = 聊天行字号 14），
    // 不是截图估算：
    //  真源 = SFVideoLive/apps/web/src/components/chat/ChatFanBadge.vue
    //        与 ChatUserLevelBadge.vue 的 <style scoped>
    //  官方侧（斗鱼 canvas 房间 252140 / 虎牙房间 333003）实测值只保留
    //  解析包仍需要的几何量（如 kHuyaConsumeLevelBadgeWidth）。
    test('聊天徽章通用尺寸按 web 的 em 口径折算(1em = 14)', () {
      expect(AppChatBadge.em, 14);
      expect(AppChatBadge.levelHeight, closeTo(20.72, 0.001));
      expect(AppChatBadge.levelMinWidth, closeTo(16.8, 0.001));
      expect(AppChatBadge.levelFontSize, closeTo(8.96, 0.001));
      expect(AppChatBadge.levelPadX, closeTo(3.64, 0.001));
      expect(AppChatBadge.levelFontSizeWide, 14);
      expect(AppChatBadge.levelPadXWide, closeTo(3.08, 0.001));
      expect(AppChatBadge.fanHeight, closeTo(17.92, 0.001));
      expect(AppChatBadge.fanMinWidth, closeTo(44.8, 0.001));
      expect(AppChatBadge.fanPadLeft, closeTo(2.24, 0.001));
      expect(AppChatBadge.fanPadRight, closeTo(3.08, 0.001));
      expect(AppChatBadge.fanGap, closeTo(2.52, 0.001));
      expect(AppChatBadge.fanFontSize, closeTo(12.6, 0.001));
      expect(AppChatBadge.iconHeight, closeTo(16.1, 0.001));
      expect(AppChatBadge.biliFanHeight, closeTo(20.72, 0.001));
      expect(AppChatBadge.biliFanMinWidth, 49);
      expect(AppChatBadge.biliFanPadX, 7);
      expect(AppChatBadge.biliFanGap, closeTo(2.8, 0.001));
      expect(AppChatBadge.fanTextShadow, hasLength(2));
    });

    test('斗鱼 LV 胶囊按 web 口径(1.15em 高 / 2px 圆角),旧官网 32x16 口径已下线', () {
      // web `.chat-user-level--douyu { height: 1.15em; border-radius: 2px }`。
      // 旧值（32×16 全圆端 + `levelEmblem` 小徽标 + 5 档米金/绿/蓝/靛/紫
      // `levelGradient`）是斗鱼官网 canvas 的实测口径，2026-09-26 按用户
      // 「复刻原网页样式」改为 web 口径；官网档位记录见 DESIGN.md §4.4。
      expect(AppDouyuChatBadge.levelHeight, closeTo(16.1, 0.001));
      expect(AppDouyuChatBadge.levelRadius, 2);
      expect(
        AppDouyuChatBadge.levelHeight,
        lessThan(AppChatBadge.levelHeight),
        reason: '斗鱼等级胶囊比通用 1.48em 矮一档',
      );
    });

    test('斗鱼粉丝牌尺寸固定为官网实测(官方 PNG 60x19, 渲染高 18)', () {
      expect(AppDouyuChatBadge.fanHeight, 18);
      expect(AppDouyuChatBadge.fanImageWidth, 60);
      // 团名左内缩 = web `ChatFanBadge.vue` 斗鱼分支
      // `.chat-fan-badge--douyu-official .chat-fan-badge__content`
      // 的 `padding-left: 1.58em`(按 14px 折算 22.1 → 22)。旧值 24 是
      // 手写估值,叠 12px 字号后 3 字团名需 64px > 60px 徽章会撑出右缘
      // (2026-09-26 用户报「长度还是不够」)。
      expect(AppDouyuChatBadge.fanTextInset, 22);
      expect(AppDouyuChatBadge.fanTextShadow, hasLength(2));
      expect(AppDouyuChatBadge.fanFallbackBg, const Color(0xFF3A3A3A));
    });

    test('斗鱼至尊大钻石边长固定为官网 :host 实测 28(四个 dy-* 里唯一非 16px)', () {
      expect(AppDouyuChatBadge.supremeSide, 28);
    });

    test('虎牙等级图 45x20 不变,叠字改为 web 的右下角定位', () {
      // 官方图 90x40(@2x) = 45x20 CSS px（解析包常量，仍用于图片尺寸）。
      expect(kHuyaConsumeLevelBadgeWidth, 45);
      expect(kHuyaConsumeLevelBadgeHeight, 20);
      // web `.chat-user-level__huya-lv { right: .12em; bottom: .06em;
      // font-size: .58em }`。旧值是把数字放在「左侧菱形之后居中」
      // （`levelEmblem = 20`），2026-09-26 按 web 口径改到右下角。
      expect(AppHuyaChatBadge.levelTextRight, closeTo(1.68, 0.001));
      expect(AppHuyaChatBadge.levelTextBottom, closeTo(0.84, 0.001));
      expect(AppHuyaChatBadge.levelTextFontSize, closeTo(8.12, 0.001));
    });

    test('虎牙粉丝牌按 web 口径(1.15em 高 / 3.4em 最小宽 / 2px 圆角)', () {
      expect(AppHuyaChatBadge.fanHeight, closeTo(16.1, 0.001));
      expect(AppHuyaChatBadge.fanMinWidth, closeTo(47.6, 0.001));
      expect(AppHuyaChatBadge.fanRadius, 2);
      expect(AppHuyaChatBadge.fanPadLeft, closeTo(1.96, 0.001));
      expect(AppHuyaChatBadge.fanPadRight, closeTo(3.92, 0.001));
      expect(AppHuyaChatBadge.fanLevelDisc, closeTo(9.85, 0.01));
      expect(AppHuyaChatBadge.fanDiscGap, closeTo(1.31, 0.01));
      expect(AppHuyaChatBadge.fanNameFontSize, closeTo(11.06, 0.001));
    });

    test('虎牙粉丝牌 7 档底色与实测分档边界一致', () {
      expect(AppHuyaChatBadge.fanGradient(4), AppHuyaChatBadge.fanTier1);
      expect(AppHuyaChatBadge.fanGradient(6), AppHuyaChatBadge.fanTier2);
      expect(AppHuyaChatBadge.fanGradient(15), AppHuyaChatBadge.fanTier3);
      expect(AppHuyaChatBadge.fanGradient(20), AppHuyaChatBadge.fanTier4);
      expect(AppHuyaChatBadge.fanGradient(22), AppHuyaChatBadge.fanTier5);
      expect(AppHuyaChatBadge.fanGradient(25), AppHuyaChatBadge.fanTier6);
      expect(AppHuyaChatBadge.fanGradient(30), AppHuyaChatBadge.fanTier7);
      expect(AppHuyaChatBadge.fanTier2.first, const Color(0xFF66AEDA));
      expect(AppHuyaChatBadge.fanTier7.first, const Color(0xFFFB9401));
    });
  });

  group('AppMotion 契约', () {
    test('fast 对齐 web --fluent-duration-fast(150ms)', () {
      // 真源:`apps/web/src/styles/main.css:74`
      //   `--fluent-duration-fast: var(--el-transition-duration-fast, 150ms);`
      expect(AppMotion.fast, const Duration(milliseconds: 150));
    });

    test('normal 对齐 web --fluent-duration-normal(250ms)', () {
      // 真源:`apps/web/src/styles/main.css:84`
      //   `--fluent-duration-normal: var(--el-transition-duration, 250ms);`
      expect(AppMotion.normal, const Duration(milliseconds: 250));
    });

    test('curve 对齐 web --fluent-easing', () {
      // 真源:`apps/web/src/styles/main.css:85`
      //   `--fluent-easing: cubic-bezier(0.16, 1, 0.3, 1);`
      //
      // Flutter 的 `Curves.easeOutCubic` 是 `Cubic(0.215, 0.61, 0.355, 1)`,
      // 与 web 曲线**不同**,必须显式取 web 的四个控制点。
      expect(AppMotion.curve, const Cubic(0.16, 1, 0.3, 1));
    });
  });

  group('AppDirectoryDrawer 契约', () {
    test('railWidth 保持 52(不要改成 28)', () {
      // 真源:`apps/web/src/components/layout/DirectoryDrawer.vue:660`
      //   `width: var(--directory-rail-width);` -> `--directory-rail-width: 52px`
      //   (main.css:39);AppLayout.vue:216 的 margin-left 同源。
      //
      // 防回归:内部看板 `tasks-ui-refine.md` 曾声称视觉宽约 28px,
      // 那与真源不符;28px 属于顶栏平台 tab 在 768–1080 的收缩值
      // (`docs/ui-reference/README.md:39`),2026-09-21 已回写文档。
      expect(AppDirectoryDrawer.railWidth, 52);
    });
  });

  group('AppTypography 契约', () {
    // 真源:`lib/src/shared/presentation/design_tokens.dart` 既有档位;
    // 这几档被大量组件引用,任何改动都会连带 golden/布局漂移,故逐项钉死。
    test('title 保持 16/1.35/w600', () {
      expect(AppTypography.title.fontSize, 16);
      expect(AppTypography.title.height, 1.35);
      expect(AppTypography.title.fontWeight, FontWeight.w600);
    });

    test('body 保持 13/1.4(无显式字重)', () {
      expect(AppTypography.body.fontSize, 13);
      expect(AppTypography.body.height, 1.4);
      expect(AppTypography.body.fontWeight, isNull);
    });

    test('bodySecondary 保持 12/1.4(无显式字重)', () {
      expect(AppTypography.bodySecondary.fontSize, 12);
      expect(AppTypography.bodySecondary.height, 1.4);
      expect(AppTypography.bodySecondary.fontWeight, isNull);
    });

    test('caption 保持 11/1.3(无显式字重)', () {
      expect(AppTypography.caption.fontSize, 11);
      expect(AppTypography.caption.height, 1.3);
      expect(AppTypography.caption.fontWeight, isNull);
    });

    group('新增 5 档阶梯(8–22px 阶梯的补充档)', () {
      test('display = 22px + letterSpacing -0.3', () {
        expect(AppTypography.display.fontSize, 22);
        expect(AppTypography.display.letterSpacing, -0.3);
        expect(AppTypography.display.height, 1.2);
        expect(AppTypography.display.fontWeight, FontWeight.w600);
      });

      test('headline = 18px + letterSpacing -0.1', () {
        expect(AppTypography.headline.fontSize, 18);
        expect(AppTypography.headline.letterSpacing, -0.1);
        expect(AppTypography.headline.height, 1.3);
        expect(AppTypography.headline.fontWeight, FontWeight.w600);
      });

      test('subtitle = 14px + letterSpacing 0', () {
        expect(AppTypography.subtitle.fontSize, 14);
        expect(AppTypography.subtitle.letterSpacing, 0);
        expect(AppTypography.subtitle.height, 1.35);
        expect(AppTypography.subtitle.fontWeight, FontWeight.w500);
      });

      test('label = 10px + letterSpacing 0.3', () {
        expect(AppTypography.label.fontSize, 10);
        expect(AppTypography.label.letterSpacing, 0.3);
        expect(AppTypography.label.height, 1.3);
        expect(AppTypography.label.fontWeight, FontWeight.w500);
      });

      test('overline = 9px + letterSpacing 0.5', () {
        expect(AppTypography.overline.fontSize, 9);
        expect(AppTypography.overline.letterSpacing, 0.5);
        expect(AppTypography.overline.height, 1.2);
        expect(AppTypography.overline.fontWeight, FontWeight.w600);
      });
    });
  });

  group('AppElevation 契约', () {
    // 这里逐字段写死期望值:token 只是把组件里的裸 BoxShadow 搬了个家,
    // 一旦有一项不等价(颜色/模糊/偏移/扩散),对应 golden 就会漂。
    test('popover = 黑 24% / blur 16 / y+4(来源 category_flyout.dart:171)', () {
      expect(AppElevation.popover.length, 1);
      final shadow = AppElevation.popover.single;
      expect(shadow.color, const Color(0x3D000000));
      expect(shadow.blurRadius, 16);
      expect(shadow.offset, const Offset(0, 4));
      expect(shadow.spreadRadius, 0);
    });

    test('hairline = 黑 35% / blur 0 / spread 1', () {
      // 来源:`lib/src/features/play/widgets/player_controls.dart:738` 与 `:781`
      // (on-video 角标的 1px 贴边描边)。
      expect(AppElevation.hairline.length, 1);
      final shadow = AppElevation.hairline.single;
      expect(shadow.color, const Color(0x59000000));
      expect(shadow.blurRadius, 0);
      expect(shadow.offset, Offset.zero);
      expect(shadow.spreadRadius, 1);
    });

    test('sheet = 黑 55% / blur 28 / x-6(来源 play_immersive_side_sheet.dart:126)', () {
      // 注意:alpha 必须是 `withValues(alpha: 0.55)` 的浮点值,不能换成
      // `Color(0x8C000000)` —— 0x8C/255 = 0.5490…,两者可能差 1/255。
      expect(AppElevation.sheet.length, 1);
      final shadow = AppElevation.sheet.single;
      expect(shadow.color.a, closeTo(0.55, 1e-9));
      expect(shadow.color.r, 0);
      expect(shadow.color.g, 0);
      expect(shadow.color.b, 0);
      expect(shadow.blurRadius, 28);
      expect(shadow.offset, const Offset(-6, 0));
      expect(shadow.spreadRadius, 0);
    });

    test('accentGlow = 强调色 22% / blur 8 / y+2(来源 platform_strip.dart:269)', () {
      const accent = Color(0xFF8B5CF6);
      expect(AppElevation.accentGlow(accent).length, 1);
      final shadow = AppElevation.accentGlow(accent).single;
      expect(shadow.color.a, closeTo(0.22, 1e-9));
      expect(shadow.color, accent.withValues(alpha: 0.22));
      expect(shadow.blurRadius, 8);
      expect(shadow.offset, const Offset(0, 2));
      expect(shadow.spreadRadius, 0);
    });
  });

  group('AppFocus 契约', () {
    test('ring 返回 2 圈阴影,spread 分别为 4 与 2', () {
      // Windows 桌面键盘可达性基线:2px 实环 + 2px 间隙的外扩环。
      // ringWidth(2)+ ringOffset(2) 是外层半透明圈,内层实圈即 ringWidth。
      const accent = Color(0xFF8B5CF6);
      final ring = AppFocus.ring(accent);
      expect(ring.length, 2);
      expect(ring[0].spreadRadius, 4);
      expect(ring[0].spreadRadius, AppFocus.ringWidth + AppFocus.ringOffset);
      expect(ring[0].blurRadius, 0);
      expect(ring[0].color, accent.withValues(alpha: 0.24));
      expect(ring[1].spreadRadius, 2);
      expect(ring[1].spreadRadius, AppFocus.ringWidth);
      expect(ring[1].blurRadius, 0);
      expect(ring[1].color, accent);
      expect(AppFocus.ringWidth, 2);
      expect(AppFocus.ringOffset, 2);
    });
  });

  group('AppFontSize 契约（字号阶梯唯一来源）', () {
    // 9 档覆盖 9–22px。新增/改动字号必须同时改 DESIGN.md §3.2 与本组断言。
    test('九档数值', () {
      expect(AppFontSize.overline, 9);
      expect(AppFontSize.label, 10);
      expect(AppFontSize.caption, 11);
      expect(AppFontSize.bodySecondary, 12);
      expect(AppFontSize.body, 13);
      expect(AppFontSize.subtitle, 14);
      expect(AppFontSize.title, 16);
      expect(AppFontSize.headline, 18);
      expect(AppFontSize.display, 22);
    });

    test('AppTypography 的 fontSize 逐档取自 AppFontSize（单一来源）', () {
      expect(AppTypography.overline.fontSize, AppFontSize.overline);
      expect(AppTypography.label.fontSize, AppFontSize.label);
      expect(AppTypography.caption.fontSize, AppFontSize.caption);
      expect(AppTypography.bodySecondary.fontSize, AppFontSize.bodySecondary);
      expect(AppTypography.body.fontSize, AppFontSize.body);
      expect(AppTypography.subtitle.fontSize, AppFontSize.subtitle);
      expect(AppTypography.title.fontSize, AppFontSize.title);
      expect(AppTypography.headline.fontSize, AppFontSize.headline);
      expect(AppTypography.display.fontSize, AppFontSize.display);
    });

    test('单调递增且两两可区分，总数恰为 9（type-scale skill 的校验项）', () {
      const sizes = <double>[
        AppFontSize.overline,
        AppFontSize.label,
        AppFontSize.caption,
        AppFontSize.bodySecondary,
        AppFontSize.body,
        AppFontSize.subtitle,
        AppFontSize.title,
        AppFontSize.headline,
        AppFontSize.display,
      ];
      for (var i = 1; i < sizes.length; i += 1) {
        expect(sizes[i], greaterThan(sizes[i - 1]));
      }
      expect(sizes.toSet().length, 9);
    });
  });

  group('on-video 字幕胶囊契约', () {
    // 真源:字幕胶囊/状态胶囊原来是 4 处裸值(`Color(0xCC101010)` +
    // `BorderRadius.circular(10)`),抽成 token 后像素不变(值逐字相同),
    // 但守卫不再放行第 5 处。
    test('AppOnVideo.captionPillBg = 黑 80%(不随主题翻转)', () {
      expect(AppOnVideo.captionPillBg, const Color(0xCC101010));
    });

    test('AppRadius.captionPill = 10(具名例外,只用于字幕胶囊)', () {
      expect(AppRadius.captionPill, 10);
      expect(AppRadius.allCaptionPill, BorderRadius.circular(10));
    });
  });
}
