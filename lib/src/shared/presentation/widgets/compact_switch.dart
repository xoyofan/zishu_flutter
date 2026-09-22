import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 全局紧凑开关(用户口径 2026-09-20:开关滑杆等默认大小全局统一)。
///
/// 自绘迷你开关(对齐 web el-switch 密度:轨道 30×16、圆角 8、滑块 12),
/// 替代 Material 默认大尺寸 Switch。选中轨道品牌紫(tokens.accent);
/// 未选中透明底 + 描边。保留 value/onChanged/Semantics(toggled) 语义。
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final track = tokens.accent;
    const offBorder = Color(0xff3a3a3a);
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 30,
          height: 16,
          decoration: BoxDecoration(
            color: value ? track : Colors.transparent,
            borderRadius: AppRadius.allMd,
            border: Border.all(color: value ? track : offBorder),
          ),
          child: AnimatedAlign(
            duration: AppMotion.fast,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: 12,
              height: 12,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? Colors.white : tokens.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
