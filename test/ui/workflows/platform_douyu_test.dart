/// douyu 平台 workflow 用例(任务卡 W2)。
///
/// fixture 阶段三平台共用同一批样例数据(kFixtureRooms 全为 douyu 站,
/// FixtureBrowseSource 对任意 site 返回相同的分类与房间列表),因此本文件
/// 与 platform_huya_test.dart / platform_bilibili_test.dart 结构完全同构,
/// 仅 site 参数不同;G1 接入 DirectLiveParserGateway 替换 fixture 数据源后,
/// 同一组用例自动变成真实平台差异测试,用例零重写。
///
/// 断言约定(见 platform_workflow.dart):
/// - 房间卡片锚点不写死 site 前缀(fixture 阶段 huya/bilibili 的卡片 key
///   仍是 room-card-douyu-*),统一按 'room-card-' 前缀计数;
/// - 分类锚点 category-group-*/category-item-* 全平台通用(每组 3 项)。
library;

import 'package:flutter_test/flutter_test.dart';

import 'platform_workflow.dart';

/// 参数化注册单个平台的 3 个 workflow 用例(新平台接入只需加一个
/// `platform_<site>_test.dart` 并调用本函数,driver 零改动)。
void _registerPlatformWorkflowTests({
  required String site,
  required String groupLabel,
}) {
  group(groupLabel, () {
    testWidgets('categoryRenders($site):分组渲染与子分类联动', (tester) async {
      await pumpPlatformApp(tester, '/$site');
      await expectCategoryRenders(tester, site);
    });

    testWidgets('categoryRoomsCorrect($site):子分类房间网格字段非空',
        (tester) async {
      await pumpPlatformApp(tester, '/$site');
      await expectCategoryRoomsCorrect(tester, site);
    });

    testWidgets('platformSmoke($site):分类→房间→进房→切画质→返回',
        (tester) async {
      await pumpPlatformApp(tester, '/$site');
      await platformSmoke(tester, site);
    });
  });
}

void main() {
  _registerPlatformWorkflowTests(site: 'douyu', groupLabel: 'douyu 平台 workflow');
}
