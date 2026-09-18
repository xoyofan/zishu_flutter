/// design token 契约测试:把 `design_tokens.dart` 的数值钉死在
/// SFVideoLive web 真源上,防止再次漂移。
///
/// 每个断言都标注了 web 真源出处;若本文件失败,先回 web 核对,
/// **不要**直接改断言迁就实现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';

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

  group('AppDirectoryDrawer 契约', () {
    test('railWidth 保持 52(不要改成 28)', () {
      // 真源:`apps/web/src/components/layout/DirectoryDrawer.vue:660`
      //   `width: var(--directory-rail-width);` -> `--directory-rail-width: 52px`
      //
      // 防回归:内部看板 `tasks-ui-refine.md` 曾声称视觉宽约 28px,
      // 那与真源不符;52 才是展开态里 rail 容器的实际宽度。
      expect(AppDirectoryDrawer.railWidth, 52);
    });
  });
}
