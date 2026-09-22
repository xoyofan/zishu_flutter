/// design token 契约测试:把 `design_tokens.dart` 的数值钉死在
/// SFVideoLive web 真源上,防止再次漂移。
///
/// 每个断言都标注了 web 真源出处;若本文件失败,先回 web 核对,
/// **不要**直接改断言迁就实现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';

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

  group('AmbientMotion 契约(氛围轨,清单 1.1/1.4)', () {
    // 真源: docs/ui-refine/ambient-effect-inventory.md §1 —— 值必须逐字采用;
    // 本组失败先回清单核对,不要改断言迁就实现。
    test('pageTransition = 180ms(页面过渡)', () {
      expect(AmbientMotion.pageTransition, const Duration(milliseconds: 180));
    });

    test('pulse = 1.6s(循环)', () {
      expect(AmbientMotion.pulse, const Duration(milliseconds: 1600));
    });

    test('shimmer = 1.4s(循环)', () {
      expect(AmbientMotion.shimmer, const Duration(milliseconds: 1400));
    });

    testWidgets('disableAnimations=true → 零时长/静态模式(reduce_motion 降级)',
        (tester) async {
      AmbientMotionSpec? spec;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              spec = AmbientMotion.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(spec!.reduced, isTrue);
      expect(spec!.pageTransition, Duration.zero);
      expect(spec!.pulse, Duration.zero);
      expect(spec!.shimmer, Duration.zero);
    });

    testWidgets('disableAnimations=false → 完整档(时长取 token 常量)',
        (tester) async {
      AmbientMotionSpec? spec;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              spec = AmbientMotion.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(spec!.reduced, isFalse);
      expect(spec!.pageTransition, AmbientMotion.pageTransition);
      expect(spec!.pulse, AmbientMotion.pulse);
      expect(spec!.shimmer, AmbientMotion.shimmer);
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

  group('AmbientGlow 契约(氛围轨,清单 1.2)', () {
    // 三档均为 accent 派生的纯外发光:无偏移、无 spread;alpha 必须是
    // `withValues(alpha: ...)` 的浮点值,与调用点逐像素一致。
    const accent = Color(0xFF8B5CF6);

    test('cardHover = accent 18% / blur 12', () {
      expect(AmbientGlow.cardHoverAlpha, 0.18);
      expect(AmbientGlow.cardHoverBlur, 12);
      final shadows = AmbientGlow.cardHover(accent);
      expect(shadows.length, 1);
      final shadow = shadows.single;
      expect(shadow.color, accent.withValues(alpha: 0.18));
      expect(shadow.color.a, closeTo(0.18, 1e-9));
      expect(shadow.blurRadius, 12);
      expect(shadow.offset, Offset.zero);
      expect(shadow.spreadRadius, 0);
    });

    test('ctaSheen = accent 24% / blur 16', () {
      expect(AmbientGlow.ctaSheenAlpha, 0.24);
      expect(AmbientGlow.ctaSheenBlur, 16);
      final shadows = AmbientGlow.ctaSheen(accent);
      expect(shadows.length, 1);
      final shadow = shadows.single;
      expect(shadow.color, accent.withValues(alpha: 0.24));
      expect(shadow.color.a, closeTo(0.24, 1e-9));
      expect(shadow.blurRadius, 16);
      expect(shadow.offset, Offset.zero);
      expect(shadow.spreadRadius, 0);
    });

    test('halo = accent 8% / blur 64', () {
      expect(AmbientGlow.haloAlpha, 0.08);
      expect(AmbientGlow.haloBlur, 64);
      final shadows = AmbientGlow.halo(accent);
      expect(shadows.length, 1);
      final shadow = shadows.single;
      expect(shadow.color, accent.withValues(alpha: 0.08));
      expect(shadow.color.a, closeTo(0.08, 1e-9));
      expect(shadow.blurRadius, 64);
      expect(shadow.offset, Offset.zero);
      expect(shadow.spreadRadius, 0);
    });

    test('topBandAlpha = 6%(壳层顶部光带上限,清单 3.4)', () {
      // 光带是渐变底不是外发光:只有颜色本体常量(无 blur/offset helper),
      // 调用点拼 `accent.withValues(alpha: AmbientGlow.topBandAlpha)`。
      // 清单 3.4 的「≤6%」即本值,调高即违规。
      expect(AmbientGlow.topBandAlpha, 0.06);
      expect(accent.withValues(alpha: AmbientGlow.topBandAlpha).a, closeTo(0.06, 1e-9));
    });
  });

  group('AmbientBlur 契约(毛玻璃上限,清单 1.3)', () {
    test('maxSigma = 20(BackdropFilter 超限即违规)', () {
      expect(AmbientBlur.maxSigma, 20);
    });

    test('具体用点档位:navSigma 16 / panelSigma 12(清单 3.1/3.2)', () {
      // 值逐字取自清单 3.1/3.2;两者都必须 ≤ maxSigma(硬上限)。
      expect(AmbientBlur.navSigma, 16);
      expect(AmbientBlur.panelSigma, 12);
      expect(AmbientBlur.navSigma, lessThanOrEqualTo(AmbientBlur.maxSigma));
      expect(AmbientBlur.panelSigma, lessThanOrEqualTo(AmbientBlur.maxSigma));
    });

    test('glassSurfaceAlpha = 0.85(surface 85%,清单 3.1)', () {
      expect(AmbientBlur.glassSurfaceAlpha, 0.85);
      const surface = Color(0xFF1F1F1F);
      expect(
        surface.withValues(alpha: AmbientBlur.glassSurfaceAlpha).a,
        closeTo(0.85, 1e-9),
      );
    });

    test('glassThinAlpha = 0.55(薄档,批1;严格小于 85% 厚档)', () {
      // 薄档给顶栏等 aurora 兜底场景,85% 厚档保留给清单 3.2 侧栏面板;
      // 薄档一旦 ≥ 厚档,"两档分工"就不存在了,故断言严格小于。
      expect(AmbientBlur.glassThinAlpha, 0.55);
      expect(
        AmbientBlur.glassThinAlpha,
        lessThan(AmbientBlur.glassSurfaceAlpha),
      );
    });
  });

  group('AmbientAurora 契约(批1,DESIGN.md §2.4)', () {
    // 真源: preview/glass-preview.html Demo F(用户拍板默认值);
    // 上限即 DESIGN.md §2.4 表中值,超限即违规。
    test('washAlpha = 0.2(上限 0.25)', () {
      expect(AmbientAurora.washAlpha, 0.2);
      expect(AmbientAurora.washAlpha, lessThanOrEqualTo(0.25));
    });

    test('三团 alpha 精确值与上限(0.78≤0.8 / 0.4≤0.5 / 0.34≤0.4)', () {
      expect(AmbientAurora.primaryBlobAlpha, 0.78);
      expect(AmbientAurora.primaryBlobAlpha, lessThanOrEqualTo(0.8));
      expect(AmbientAurora.accentBlobAlpha, 0.4);
      expect(AmbientAurora.accentBlobAlpha, lessThanOrEqualTo(0.5));
      expect(AmbientAurora.balanceBlobAlpha, 0.34);
      expect(AmbientAurora.balanceBlobAlpha, lessThanOrEqualTo(0.4));
    });


    test('grainAlpha = 0.06(噪点覆层上限 6%)', () {
      expect(AmbientAurora.grainAlpha, 0.06);
      expect(AmbientAurora.grainAlpha, lessThanOrEqualTo(0.06));
    });
  });

  group('AmbientCardGlass 契约(批3,DESIGN.md §2.4 内容卡条目)', () {
    test('hairline 边框:白 9% 常态 / 白 22% hover(hover 更亮)', () {
      expect(AmbientCardGlass.border.a, closeTo(0.09, 0.01));
      expect(AmbientCardGlass.borderHover.a, closeTo(0.22, 0.01));
      expect(
        AmbientCardGlass.borderHover.a,
        greaterThan(AmbientCardGlass.border.a),
      );
    });

  });

  group('AmbientAuroraPalette 契约(批1,DESIGN.md §2.4)', () {
    const accent = Color(0xFF7C4DFF);

    AmbientAuroraPalette paletteFor(String site) =>
        AmbientAuroraPalette.forSite(site, accent: accent);

    test('团1 与 PlatformBrandCatalog 逐平台一致(all 特判取 accent)', () {
      for (final b in PlatformBrandCatalog.navPlatforms) {
        final expected = b.id == 'all' ? accent : b.color;
        expect(paletteFor(b.id).primary, expected, reason: 'site=${b.id}');
      }
    });

    test('聚合页 all 与未收录站点团1 = accent(不铺品牌金,防土黄)', () {
      expect(paletteFor('all').primary, accent);
      final p = paletteFor('not-a-site');
      expect(p.primary, accent);
      // 团3 冷青默认不变(紫青对比)。
      expect(p.balance, const Color(0xFF00D2D3));
    });

    test('团2 恒等于传入 accent(切平台不变)', () {
      for (final b in PlatformBrandCatalog.navPlatforms) {
        expect(paletteFor(b.id).accent, accent, reason: 'site=${b.id}');
      }
    });

    test('团3 配对表抽查:黄/橙亮底平台配冷色,冷平台配暖点缀', () {
      expect(paletteFor('all').balance, const Color(0xFF00D2D3));
      expect(paletteFor('douyu').balance, const Color(0xFF00D2D3));
      expect(paletteFor('huya').balance, const Color(0xFF48DBFB));
      expect(paletteFor('yy').balance, const Color(0xFF54A0FF));
      expect(paletteFor('bilibili').balance, const Color(0xFF54A0FF));
      expect(paletteFor('douyin').balance, const Color(0xFF00D2D3));
      expect(paletteFor('twitch').balance, const Color(0xFF00D2D3));
      expect(paletteFor('kuaishou').balance, const Color(0xFF00D2D3));
      expect(paletteFor('xhs').balance, const Color(0xFF00D2D3));
      expect(paletteFor('youtube').balance, const Color(0xFF00D2D3));
      // 本就冷色的平台反过来配暖色点缀,冷暖平衡。
      expect(paletteFor('soop').balance, const Color(0xFFFF6BCB));
      expect(paletteFor('iptv').balance, const Color(0xFFFF9F43));
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
