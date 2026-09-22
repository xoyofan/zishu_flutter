/// yt-dlp 参数组装回归:代理注入是「YouTube 必须走代理」的网络下的关键修复。
///
/// 背景(2026-09-22 实测):yt-dlp 是独立子进程,不会继承宿主 HttpClient 的
/// 代理 —— 未下发 `--proxy` 时直连提取 39665/6675/7823ms,下发后
/// 3433/5095/5054ms,且直连方差极大;这正是「YouTube 直播间进房非常慢」的
/// 主因(冷解析约 11s 里几乎全是 dlp 等待)。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  group('buildYoutubeDlpArgs', () {
    test('基础参数:watch URL + -J + 不跟播放列表 + 静音警告', () {
      final args = buildYoutubeDlpArgs(videoId: 'abc123');
      expect(args.first, 'https://www.youtube.com/watch?v=abc123');
      expect(args, containsAll(['-J', '--no-playlist', '--no-warnings']));
      expect(args, isNot(contains('--proxy')), reason: '未给代理端口时不得下发');
    });

    test('给出代理端口时下发 --proxy,并保持 http:// 前缀', () {
      final args = buildYoutubeDlpArgs(
        videoId: 'abc123',
        proxyHostPort: '127.0.0.1:7897',
      );
      final index = args.indexOf('--proxy');
      expect(index, isNonNegative);
      expect(args[index + 1], 'http://127.0.0.1:7897');
    });

    test('代理端口为空串视为未配置', () {
      final args = buildYoutubeDlpArgs(videoId: 'abc123', proxyHostPort: '');
      expect(args, isNot(contains('--proxy')));
    });

    test('deno 路径转正斜杠(Windows 盘符路径的 RUNTIME:PATH 约定)', () {
      final args = buildYoutubeDlpArgs(
        videoId: 'abc123',
        denoPath: r'C:\Tools\deno.exe',
      );
      final index = args.indexOf('--js-runtimes');
      expect(index, isNonNegative);
      expect(args[index + 1], 'deno:C:/Tools/deno.exe');
    });

    test('deno 与代理可同时下发', () {
      final args = buildYoutubeDlpArgs(
        videoId: 'abc123',
        denoPath: r'C:\Tools\deno.exe',
        proxyHostPort: '127.0.0.1:7897',
      );
      expect(args, containsAll(['--js-runtimes', '--proxy', '-J']));
    });
  });
}
