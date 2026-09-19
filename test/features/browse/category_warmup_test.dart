/// 分类预热(category_warmup)单测。
library;

import 'package:live_parser/live_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/features/browse/application/category_warmup.dart';

void main() {
  test('串行逐站预热:每个站点各调用一次拉取,顺序与站点集合一致', () async {
    final called = <String>[];
    final result = CategoryResult(site: 'test', groups: []);
    final sites = ['douyu', 'huya', 'bilibili'];
    await warmupBrowseCategories(
      (site) async {
        called.add(site);
        return result;
      },
      sites,
    );
    expect(called, sites, reason: '每个站点应各预热一次且保持串行顺序');
  });

  test('某站预热失败静默跳过,不影响后续站点', () async {
    final called = <String>[];
    Object? caught;
    await warmupBrowseCategories(
      (site) async {
        called.add(site);
        if (site == 'huya') throw Exception('预热失败');
        return CategoryResult(site: site, groups: []);
      },
      ['douyu', 'huya', 'bilibili'],
    ).catchError((Object e) {
      caught = e;
      return <CategoryResult>[];
    });
    expect(called, ['douyu', 'huya', 'bilibili'],
        reason: '失败站不应中断后续站点的预热');
    expect(caught, isNull, reason: '预热失败应被静默吞掉');
  });
}
