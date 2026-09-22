/// 语音识别中文字幕条:多句横向排列,每句存活 5s。
///
/// 位置由调用方(Positioned)决定 —— 控制栏上方一点;控制栏淡出时字幕
/// 仍常显(字幕语义)。译文就绪才上屏(与弹幕翻译同口径)。
///
/// 布局(用户口径 2026-09-21):**充分利用播放宽度**,多句横向排列、句间留
/// 空隙;每句独立计时 5s 后消失,而不是只显示最新一句。宽度不够时自动
/// 折行(Wrap),不截断句子。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech2zh/speech2zh.dart';

import '../application/caption_lines.dart';
import '../application/speech_caption_provider.dart';
import '../../../shared/presentation/design_tokens.dart';

/// 模型下载确认弹窗:未下载 → 下载;有 `.part` → 断点续传。
class CaptionDownloadDialog extends StatelessWidget {
  const CaptionDownloadDialog({
    super.key,
    required this.language,
    required this.info,
  });

  final SpeechLanguage language;
  final ModelDownloadInfo info;

  @override
  Widget build(BuildContext context) {
    final mb = (info.totalBytes / 1024 / 1024).toStringAsFixed(0);
    final downloaded = (info.downloadedBytes / 1024 / 1024).toStringAsFixed(1);
    return AlertDialog(
      title: const Text('下载字幕模型'),
      content: Text(
        '${language.code.toUpperCase()} 字幕模型约 $mb MB。\n'
        '${info.hasPartial ? '已存在 $downloaded MB 未完成文件，将尝试断点续传。' : '首次使用需要下载模型。'}',
      ),
      actions: [
        TextButton(
          key: const Key('caption-download-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('caption-download-confirm'),
          onPressed: () =>
              Navigator.pop(context, CaptionDownloadAction.download),
          child: Text(info.hasPartial ? '继续下载' : '下载'),
        ),
      ],
    );
  }
}

enum CaptionDownloadAction { download }

class CaptionOverlay extends ConsumerWidget {
  const CaptionOverlay({super.key, required this.site, required this.roomId});

  final String site;
  final String roomId;

  /// 句间水平空隙(用户口径:每一句间隔一点)。
  static const double _kSentenceGap = 14;

  /// 折行时的行距。
  static const double _kRowGap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      roomSpeechCaptionProvider((site: site, roomId: roomId)),
    );
    final hasText = state.lines.isNotEmpty;
    if (!hasText &&
        state.phase != CaptionUiPhase.downloading &&
        state.phase != CaptionUiPhase.loadingModel &&
        state.phase != CaptionUiPhase.error) {
      return const SizedBox.shrink();
    }

    final Widget body = hasText
        ? _SentenceRow(lines: state.lines)
        : _StatusPill(text: _statusText(state));

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          // 充分利用播放宽度:只留两侧安全边距,不再限宽 720。
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: body,
          ),
        ),
      ),
    );
  }

  /// 状态文案指明具体语言模型(用户口径:英文/韩文…),避免多语言平台下
  /// 看不出在下载哪一个。
  String _statusText(CaptionUiState state) {
    final language = state.language;
    final prefix = language == null
        ? '字幕'
        : '${speechLanguageLabel(language)}字幕';
    return switch (state.phase) {
      CaptionUiPhase.downloading => () {
        final p = state.downloadProgress ?? 0;
        if (p >= 1) return '$prefix模型校验中…';
        final speed = state.downloadBytesPerSecond;
        final speedText = speed == null || speed <= 0
            ? ''
            : ' · ${(speed / 1024 / 1024).toStringAsFixed(1)} MB/s';
        return '$prefix模型下载中 ${(p * 100).toStringAsFixed(0)}%$speedText';
      }(),
      CaptionUiPhase.loadingModel => '$prefix引擎加载中…',
      CaptionUiPhase.error => '$prefix失败：${state.message ?? '未知错误'}',
      _ => '',
    };
  }
}

/// 多句横向排列:句间留空隙,放不下自动折行;每句为独立胶囊底色。
class _SentenceRow extends StatelessWidget {
  const _SentenceRow({required this.lines});

  final List<CaptionLine> lines;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: CaptionOverlay._kSentenceGap,
      runSpacing: CaptionOverlay._kRowGap,
      children: [
        for (final line in lines)
          _SentencePill(
            // key 让同文案重复出现时也能各自独立渲染/计时。
            key: ValueKey<Object>(line),
            text: line.text,
          ),
      ],
    );
  }
}

class _SentencePill extends StatelessWidget {
  const _SentencePill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppOnVideo.captionPillBg,
        borderRadius: AppRadius.allCaptionPill,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Colors.white, height: 1.35),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          color: AppOnVideo.captionPillBg,
          borderRadius: AppRadius.allCaptionPill,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
