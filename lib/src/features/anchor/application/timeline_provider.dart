import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/fixture_sources.dart';

/// 动态时间线条目:房间摘要 + 事件时间(样例固定偏移生成)。
class TimelineEntry {
  const TimelineEntry({required this.room, required this.eventTime});

  final RoomSummary room;
  final DateTime eventTime;

  /// 相对时间文案:如「5 分钟前」「2 小时前」「1 天前」。
  String get relativeLabel {
    final diff = DateTime.now().difference(eventTime);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

/// 时间线状态:全部条目 + 当前平台筛选。
class TimelineState {
  const TimelineState({required this.entries, this.filterSite = 'all'});

  /// 全部动态条目,按事件时间递减(最新在前)。
  final List<TimelineEntry> entries;

  /// 平台筛选 id,'all' 表示全平台。
  final String filterSite;

  /// 筛选后的可见条目。
  List<TimelineEntry> get visible => filterSite == 'all'
      ? entries
      : entries.where((entry) => entry.room.site == filterSite).toList(growable: false);
}

/// 时间线 controller:把 kFixtureRooms 映射为带事件时间的动态流,并持有平台筛选。
class TimelineController extends AsyncNotifier<TimelineState> {
  /// 样例事件固定偏移(分钟),递减排列形成「最新在前」的时间线。
  static const List<int> _kEventOffsetsMinutes = [
    5, 32, 68, 145, 300, 540, 1250, 1600, 2900, 4400, //
  ];

  @override
  FutureOr<TimelineState> build() {
    final now = DateTime.now();
    final entries = <TimelineEntry>[
      for (var i = 0; i < kFixtureRooms.length; i++)
        TimelineEntry(
          room: kFixtureRooms[i],
          eventTime: now.subtract(
            Duration(minutes: _kEventOffsetsMinutes[i % _kEventOffsetsMinutes.length]),
          ),
        ),
    ];
    return TimelineState(entries: entries);
  }

  /// 切换平台筛选;与当前值相同则不触发重建。
  void setFilter(String site) {
    final current = state.value;
    if (current == null || current.filterSite == site) return;
    state = AsyncData(TimelineState(entries: current.entries, filterSite: site));
  }
}

/// 时间线 provider(autoDispose:离开页面即释放)。
final timelineControllerProvider = AsyncNotifierProvider.autoDispose
    <TimelineController, TimelineState>(TimelineController.new);
