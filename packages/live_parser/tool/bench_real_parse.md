# 真实解析 benchmark

- 运行时间: 2026-09-13 16:25:29.069333
- 环境: 直连各平台 live_parser(dart `http` 默认 Client,不走代理 env)
- 方法: 每平台先 fetchRooms(limit=10)测列表耗时,取首间房间 resolveRoom 测房间解析;resolve 跑 3 次取冷/热区间与中位(失败即中止)。

| 平台 | browse 列表 | resolve 房间(冷/热,中位) | 线路数 | 画质档 | 状态 |
|---|---|---|---|---|---|
| douyu | 225ms (10间) | 795/76ms 中位79 | 4 | 2 | browse OK; resolve OK(live,Ktitty佳佳丶) |
| huya | 229ms (120间) | 190/118ms 中位125 | 36 | 6 | browse OK; resolve OK(live,老实人sask) |
| bilibili | 323ms (22间) | 285/104ms 中位285 | 32 | 4 | browse OK; resolve OK(live,哔哩哔哩英雄联盟赛事) |
| iptv | 0ms (0间) | 无房间ID | — | — | browse OK; 无可用房间 |
| twitch | 504ms (10间) | FAIL | — | — | browse OK; resolve FAIL: 未获取到播放令牌 |
| yy | 139ms (10间) | 421/132ms 中位164 | 3 | 3 | browse OK; resolve OK(live,柠小檬) |
| soop | 728ms (10间) | 1770/0ms 中位0 | 1 | 4 | browse OK; resolve OK(live,김민교.) |
| kuaishou | 659ms (10间) | 617/364ms 中位434 | 4 | 4 | browse OK; resolve OK(live,星辰໊ོ༊) |
| douyin | 1344ms (10间) | 401/188ms 中位205 | 4 | 2 | browse OK; resolve OK(live,靖涛二手车销售有限公司) |
| youtube | 1587ms (10间) | 8096/0ms 中位0 | 6 | 6 | browse OK; resolve OK(live,LCK-Carry) |

## 汇总

- 总耗时: 25609ms(含顺序串行各平台)。
- resolve 成功: 8 / 失败: 1。
- 说明: 单平台串行、无并发;海外站(Twitch/YouTube/SOOP)可能受网络/代理/地域限制失败,属预期。
- 线路数反映「多线路自动切换」的数据基础: 线路数>1 的平台断流时可由 mpv 播放列表内部跳下一条。
