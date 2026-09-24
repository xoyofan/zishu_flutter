import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  test('all 浏览默认纳入所有现有可浏览直播站,排除 all', () {
    final all = buildSiteRegistry()['all']!.browse! as CrossBrowseRepository;

    expect(all.siteIds, [
      'douyu',
      'huya',
      'bilibili',
      'douyin',
      'kuaishou',
      'yy',
      'twitch',
      'soop',
      'youtube',
    ]);
    expect(all.siteIds, isNot(contains('all')));
  });
}
