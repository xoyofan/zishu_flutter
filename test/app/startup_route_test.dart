import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/app/app_router.dart';

void main() {
  group('StartupRoute 启动参数', () {
    tearDown(() {
      // configure 是静态写入,逐用例还原默认值,防串扰。
      StartupRoute.value = '/all';
    });

    test('无参数:默认 /all,行为不变', () {
      StartupRoute.configure(const []);
      expect(StartupRoute.value, '/all');
    });

    test('--route 优先级最高:直接指定任意路由', () {
      StartupRoute.configure(
        const ['--route', '/soop/category', '--site', 'douyin', '--room', '1'],
      );
      expect(StartupRoute.value, '/soop/category');
    });

    test('--site + --room 分离形式:直达播放页', () {
      StartupRoute.configure(const ['--site', 'douyin', '--room', '123456']);
      expect(StartupRoute.value, '/douyin/play/123456');
    });

    test('--site= / --room= 等号形式等价', () {
      StartupRoute.configure(const ['--site=huya', '--room=660000']);
      expect(StartupRoute.value, '/huya/play/660000');
    });

    test('参数顺序无关(--room 在 --site 前)', () {
      StartupRoute.configure(const ['--room', '123456', '--site', 'douyin']);
      expect(StartupRoute.value, '/douyin/play/123456');
    });

    test('--room 直播间 URL:按域名推断平台并提取尾段房间号', () {
      StartupRoute.configure(
        const ['--room', 'https://live.douyin.com/123456?from=share'],
      );
      expect(StartupRoute.value, '/douyin/play/123456');
    });

    test('--room URL 与 --site 冲突时以 URL 域名为准(同 play 路由纠正语义)', () {
      StartupRoute.configure(
        const ['--site', 'huya', '--room', 'https://www.douyu.com/959748'],
      );
      expect(StartupRoute.value, '/douyu/play/959748');
    });

    test('未知站点 URL:推断不出平台,保持默认首页', () {
      StartupRoute.configure(const ['--room', 'https://example.com/live/1']);
      expect(StartupRoute.value, '/all');
    });

    test('缺 --site 的纯房间号:平台未知,保持默认首页', () {
      StartupRoute.configure(const ['--room', '123456']);
      expect(StartupRoute.value, '/all');
    });

    test('--room 缺失或空值:保持默认首页', () {
      StartupRoute.configure(const ['--site', 'douyin']);
      expect(StartupRoute.value, '/all');
      StartupRoute.configure(const ['--site', 'douyin', '--room', '']);
      expect(StartupRoute.value, '/all');
    });
  });
}
