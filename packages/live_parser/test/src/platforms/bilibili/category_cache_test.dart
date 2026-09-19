import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/browse.dart';
import 'package:live_parser/src/platforms/bilibili/wbi.dart';
import 'package:test/test.dart';

import '../../../support/fake_bilibili_api.dart';

void main() {
  test('分类缓存空壳分组校验:空壳按未命中处理,重拉后自愈覆盖(对齐 web e389570)', () async {
    final fake = FakeBilibiliApi()
      ..areaListResponse = {
        // 上游改版空壳:顶层分组非空但全部无子项;旧逻辑会把空结果霸占在缓存里。
        'code': 0,
        'data': [
          {'id': 2, 'name': '网游', 'list': []},
          {'id': 6, 'name': '手游', 'list': []},
        ],
      }
      ..roomListResponse = {'code': 0, 'data': []}
      ..webMainListResponse = {'code': 0, 'data': []};
    final browse = BilibiliBrowseRepository(
      ParserHttp(client: fake),
      BilibiliCredentials(),
    );

    // 第一次:空壳分组按未命中处理,不落缓存。
    final empty = await browse.fetchCategories('bilibili');
    expect(empty.groups, isEmpty);

    // 上游恢复真实分组后,第二次请求必须重新拉取(而不是回读空壳缓存)。
    fake.areaListResponse = jsonDecode(
      await File('test/fixtures/bilibili/area_list.json').readAsString(),
    );
    final recovered = await browse.fetchCategories('bilibili');
    expect(recovered.groups, hasLength(1));
    expect(recovered.groups.single.name, '网游');
    expect(recovered.groups.single.items.map((i) => i.name), contains('英雄联盟'));

    // 有了真实分组后缓存生效:第三次不再发起网络请求。
    fake.areaListResponse = {'code': 500, 'message': 'upstream broken', 'data': []};
    final cached = await browse.fetchCategories('bilibili');
    expect(cached.groups.single.name, '网游');
  });
}
