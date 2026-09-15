# 真实解析 benchmark

- 运行时间: 2026-09-15 23:37:05.966749
- 环境: 直连各平台 live_parser(dart `http` 默认 Client,不走代理 env)
- 方法: 每平台先 fetchRooms(limit=10)测列表耗时,取首间房间 resolveRoom 测房间解析;resolve 跑 3 次取冷/热区间与中位(失败即中止)。

| 平台 | browse 列表 | resolve 房间(冷/热,中位) | 线路数 | 画质档 | 状态 |
|---|---|---|---|---|---|
| douyu | 228ms (10间) | 795/93ms 中位97 | 15 | 5 | browse OK; resolve OK(live,寅子) |
| huya | 332ms (120间) | 233/118ms 中位140 | 36 | 6 | browse OK; resolve OK(live,微竞-芜湖神【0172】) |
| bilibili | 304ms (22间) | 112/94ms 中位96 | 24 | 3 | browse OK; resolve OK(live,炫神_) |
| iptv | 0ms (0间) | 无房间ID | — | — | browse OK; 无可用房间 |
| twitch | 1488ms (10间) | 4316/0ms 中位0 | 5 | 5 | browse OK; resolve OK(live,IlloJuan) |
| yy | 87ms (10间) | 376/112ms 中位191 | 3 | 3 | browse OK; resolve OK(live,星儿) |
| soop | 275ms (10间) | 940/0ms 中位0 | 1 | 4 | browse OK; resolve OK(live,봉준) |
| kuaishou | 497ms (10间) | 477/270ms 中位343 | 2 | 2 | browse OK; resolve OK(live,轨C迹动漫篮球) |
| douyin | 771ms (10间) | 214/180ms 中位194 | 8 | 4 | browse OK; resolve OK(live,英英爱吃美食) |
| youtube | 2008ms (10间) | 8382/0ms 中位0 | 6 | 6 | browse OK; resolve OK(live,undergroundDV 達哥) |

## 汇总

- 总耗时: 23779ms(含顺序串行各平台)。
- resolve 成功: 9 / 失败: 0。
- 说明: 单平台串行、无并发;海外站(Twitch/YouTube/SOOP)可能受网络/代理/地域限制失败,属预期。
- 线路数反映「多线路自动切换」的数据基础: 线路数>1 的平台断流时可由 mpv 播放列表内部跳下一条。
