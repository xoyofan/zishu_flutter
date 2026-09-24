/// 各站点的公共展示契约。
///
/// 标签与列顺序来自 `DESIGN.md`/SFVideoLive 的房间统计口径;这里只保存
/// 纯 Dart 描述,供 parser 注册项和 Flutter 共享 formatter 消费。
library;

import '../models/models.dart';

const RoomStatColumn kAudienceColumn = RoomStatColumn(
  field: RoomStatField.audience,
  label: '观众',
  tone: RoomStatTone.audience,
);

const RoomStatColumn kWatchingColumn = RoomStatColumn(
  field: RoomStatField.audience,
  label: '观看',
  tone: RoomStatTone.audience,
);

const RoomStatColumn kVipColumn = RoomStatColumn(
  field: RoomStatField.vip,
  label: '贵宾',
  tone: RoomStatTone.vip,
);

const RoomStatColumn kSuperFanColumn = RoomStatColumn(
  field: RoomStatField.svip,
  label: '超粉',
  tone: RoomStatTone.svip,
);

const RoomStatColumn kDiamondFanColumn = RoomStatColumn(
  field: RoomStatField.svip,
  label: '钻粉',
  tone: RoomStatTone.svip,
);

const RoomStatColumn kMedalColumn = RoomStatColumn(
  field: RoomStatField.vip,
  label: '粉丝勋章',
  tone: RoomStatTone.vip,
);

const RoomStatColumn kGuardColumn = RoomStatColumn(
  field: RoomStatField.svip,
  label: '大航海',
  tone: RoomStatTone.svip,
);

const RoomStatColumn kFanClubColumn = RoomStatColumn(
  field: RoomStatField.vip,
  label: '粉丝团',
  tone: RoomStatTone.vip,
);

const RoomStatColumn kMemberColumn = RoomStatColumn(
  field: RoomStatField.svip,
  label: '会员',
  tone: RoomStatTone.svip,
);

const RoomStatColumn kSubscribeColumn = RoomStatColumn(
  field: RoomStatField.vip,
  label: '订阅',
  tone: RoomStatTone.vip,
);

const SiteDisplaySpec kDouyuDisplay = SiteDisplaySpec(
  showFollowers: true,
  showStartedAt: true,
  roomStats: [kAudienceColumn, kVipColumn, kDiamondFanColumn],
);

const SiteDisplaySpec kHuyaDisplay = SiteDisplaySpec(
  showFollowers: true,
  roomStats: [kAudienceColumn, kVipColumn, kSuperFanColumn],
);

const SiteDisplaySpec kBilibiliDisplay = SiteDisplaySpec(
  showFollowers: true,
  roomStats: [kAudienceColumn, kMedalColumn, kGuardColumn],
);

const SiteDisplaySpec kDouyinDisplay = SiteDisplaySpec(
  showFollowers: true,
  roomStats: [kAudienceColumn, kFanClubColumn, kMemberColumn],
);

const SiteDisplaySpec kKuaishouDisplay = SiteDisplaySpec(
  roomStats: [kAudienceColumn],
);

const SiteDisplaySpec kSoopDisplay = SiteDisplaySpec(
  showFollowers: true,
  showStartedAt: true,
  roomStats: [kWatchingColumn, kSubscribeColumn],
);

const SiteDisplaySpec kTwitchDisplay = SiteDisplaySpec(
  showStartedAt: true,
  roomStats: [kAudienceColumn],
);

const SiteDisplaySpec kYoutubeDisplay = SiteDisplaySpec(
  showStartedAt: true,
  roomStats: [kWatchingColumn],
);

const SiteDisplaySpec kYyDisplay = SiteDisplaySpec(
  showStartedAt: true,
  roomStats: [kAudienceColumn],
);
