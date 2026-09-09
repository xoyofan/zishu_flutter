/// 播放页右侧 328px 信息栏:聊天(静态样例弹幕)/关注/推荐 三个 Tab。
/// 弹幕视觉参照 SFVideoLive web:徽章 + 彩色用户名 + 消息正文,G2 接真实弹幕流。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

class PlaySidePanel extends StatelessWidget {
  const PlaySidePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: tokens.border),
      ),
      child: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              tabs: const [Tab(text: '聊天'), Tab(text: '关注'), Tab(text: '推荐')],
              indicatorColor: tokens.brand,
              labelColor: tokens.textPrimary,
              unselectedLabelColor: tokens.textSecondary,
              labelStyle: AppTypography.body,
              dividerColor: tokens.border,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _ChatSampleList(),
                  const _PanelHint(text: '关注/特别关注/开播提醒(M4)'),
                  const _PanelHint(text: '关注房间推荐(M4)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条样例弹幕:可选粉丝团徽章 + 用户名 + 正文。
class _ChatSample {
  const _ChatSample(this.user, this.message, {this.fanLevel});

  final String user;
  final String message;

  /// 粉丝团等级;null 表示无徽章。
  final int? fanLevel;
}

const List<_ChatSample> _chatSamples = [
  _ChatSample('星河不入梦', '来了来了，主播这波操作可以', fanLevel: 12),
  _ChatSample('奶茶三分甜', '晚上好呀，刚下班就来蹲直播'),
  _ChatSample('皮蛋solo', '这波是教科书级别，学会了吗', fanLevel: 7),
  _ChatSample('夜色温柔', '画质终于不糊了，表扬'),
  _ChatSample('风起于青萍之末', '前排围观，顺便签到', fanLevel: 23),
  _ChatSample('小狮子嗷呜', 'BGM 叫什么名字呀？'),
  _ChatSample('代码搬运工', '这个走位有点东西', fanLevel: 5),
  _ChatSample('今天也想摸鱼', '关注了关注了，明天还来'),
  _ChatSample('山间清风', '主播声音好听，讲解也细', fanLevel: 9),
  _ChatSample('烤冷面加蛋', '水友赛什么时候安排一下'),
  _ChatSample('云端漫步', '刚刚那波团战复盘讲得好', fanLevel: 31),
  _ChatSample('一只小海豹', '来了来了，老规矩先点个关注'),
];

class _ChatSampleList extends StatelessWidget {
  const _ChatSampleList();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              for (final sample in _chatSamples)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ChatRow(sample: sample),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text(
            '弹幕接入于 G2(fixture stream)',
            style: AppTypography.caption.copyWith(color: tokens.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.sample});

  final _ChatSample sample;

  /// 用户名 -> 稳定色相(SFVideoLive 同款 hash 着色思路)。
  Color _userColor(BuildContext context) {
    var hash = 0;
    for (final unit in sample.user.codeUnits) {
      hash = (hash * 31 + unit) % 360;
    }
    return HSLColor.fromAHSL(1, hash.toDouble(), 0.6, 0.68).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fanLevel = sample.fanLevel;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (fanLevel != null) ...[
          _FanBadge(level: fanLevel),
          const SizedBox(width: AppSpacing.xs),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: sample.user,
                  style: AppTypography.bodySecondary.copyWith(
                    color: _userColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '：', style: AppTypography.bodySecondary),
                TextSpan(
                  text: sample.message,
                  style: AppTypography.bodySecondary.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 粉丝团徽章:圆角色块 + 等级数字(真实粉丝牌素材在 G2 接入)。
class _FanBadge extends StatelessWidget {
  const _FanBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.brand.withValues(alpha: 0.18),
        borderRadius: AppRadius.allSm,
        border: Border.all(color: tokens.brand.withValues(alpha: 0.6)),
      ),
      child: Text(
        '粉丝 $level',
        style: AppTypography.caption.copyWith(
          color: tokens.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PanelHint extends StatelessWidget {
  const _PanelHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.bodySecondary,
        ),
      ),
    );
  }
}
