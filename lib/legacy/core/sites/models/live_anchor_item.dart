// 来源：pure_live（AGPL-3.0）lib/model/live_anchor_item.dart，原样移植。
import 'dart:convert';

class LiveAnchorItem {
  /// 房间ID
  final String roomId;

  /// 封面
  final String avatar;

  /// 用户名
  final String userName;

  /// 直播中
  final bool liveStatus;

  LiveAnchorItem({
    required this.roomId,
    required this.avatar,
    required this.userName,
    required this.liveStatus,
  });

  @override
  String toString() {
    return json.encode({
      'roomId': roomId,
      'avatar': avatar,
      'userName': userName,
      'liveStatus': liveStatus,
    });
  }
}
