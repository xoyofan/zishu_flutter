/// category_sections 单测:抽屉与顶部 hover 浮层共用的一级分区构建逻辑
/// (Dart 移植自参考 `drawerCategories.ts`,用户口径:不平铺、不限条数)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show CategoryGroup, CategoryItem;
import 'package:zishu_flutter/src/shared/domain/category_sections.dart';

CategoryGroup _group(String id, String name, List<String> cids) =>
    CategoryGroup(
      id: id,
      name: name,
      items: [
        for (final cid in cids)
          CategoryItem(cid: cid, name: '分类$cid', pic: ''),
      ],
    );

void main() {
  test('douyu:过滤非游戏一级分区(颜值/正能量/语音/科技文化)与空组', () {
    final groups = [
      _group('1', '网游竞技', ['1', '2']),
      _group('8', '颜值', ['80']),
      _group('9', '手游', []),
      _group('16', '正能量', ['160']),
    ];
    final sections = buildCategorySections('douyu', groups);
    expect(sections.map((s) => s.id), ['1'], reason: '颜值/正能量应被过滤,空组不产出 section');
  });

  test('douyu:按 DRAWER_GROUP_ORDER 排序(网游→单机→手游→赛车→娱乐)', () {
    final groups = [
      _group('2', '娱乐', ['21']),
      _group('1', '网游竞技', ['1']),
      _group('9', '手游', ['9']),
      _group('15', '单机', ['15']),
      _group('22', '赛车', ['22']),
      _group('99', '其他', ['99']),
    ];
    final sections = buildCategorySections('douyu', groups);
    expect(sections.map((s) => s.id), ['1', '15', '9', '22', '2', '99'],
        reason: '有排序表的分区按表序,其余排最后');
  });

  test('无排序表的平台(huya 以外的 bilibili 等)保持原序且不过滤', () {
    final groups = [
      _group('8', '颜值', ['80']),
      _group('1', '游戏', ['1']),
    ];
    final sections = buildCategorySections('bilibili', groups);
    expect(sections.map((s) => s.id), ['8', '1'], reason: '非 douyu/huya/douyin 原样返回');
  });

  test('不限条数:每区条目全量保留(用户口径 2026-09-27,不用参考实现的 18 条 limit)', () {
    final groups = [
      _group('1', '网游竞技', [for (var i = 1; i <= 40; i++) '$i']),
    ];
    final sections = buildCategorySections('douyu', groups);
    expect(sections.single.items.length, 40);
  });

  test('isFlatCategoryGroups:单组平台(twitch/soop/快手)判定为平铺', () {
    expect(isFlatCategoryGroups([_group('0', '全部', ['1'])]), isTrue);
    expect(
      isFlatCategoryGroups([
        _group('1', '网游', ['1']),
        _group('2', '手游', ['2']),
      ]),
      isFalse,
    );
  });

  test('douyin:按排序表重排(1 网游 → 2 手游),不过滤分组', () {
    final groups = [
      _group('2', '手游', ['21']),
      _group('1', '网游', ['11']),
    ];
    final sections = buildCategorySections('douyin', groups);
    expect(sections.map((s) => s.id), ['1', '2'], reason: 'douyin 排序表 1 在 2 前');
    expect(sections.map((s) => s.name), ['网游', '手游']);
  });
}
