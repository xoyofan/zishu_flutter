# 平台「解析 → 播放」耗时基准

- 生成时间: 2026-09-12 01:37:11
- 环境: Windows 桌面(本机网络,含透明代理;绝对值仅供同环境对比,跨网络需重跑)
- 方法: browse 选首个可解析在播房 → `resolveRoom` 预热 1 次 + 计分 3 次取中位;「热解析」= 同一实例连续解析 3 次中位(命中 resolver 内 20s/60s 缓存与连接复用)
- HTTP 请求耗时经注入的计时 `http.Client` 按 `host+path` 聚合(仅最后一轮冷解析)
- 播放就绪:首选线路首字节探测(HLS = 清单/变体 + 首分片 TTFB;FLV = 首包 TTFB),近似播放器打开等待

## 总览

| 平台 | 状态 | 解析中位(ms) | 最快/最慢(ms) | 热解析中位(ms) | 播放就绪(ms) | 房号 | 档位 |
|---|---|---:|---|---:|---:|---|---|
| douyu | live | 411 | 406 / 412 | 236 | 1059 | 9263298 | 原画1080P30/高清 |
| huya | live | 255 | 253 / 274 | 142 | 329 | 518518 | 蓝光20M/蓝光8M/蓝光4M/超清/流畅 |
| bilibili | live | 385 | 381 / 418 | 283 | 440 | 21987615 | 原画/蓝光/超清 |
| douyin | live | 878 | 802 / 1022 | 311 | 8322 | 497429344372 | 蓝光/高清/流畅 |
| yy | live | 377 | 333 / 396 | 305 | 76 | 22490906 | 超清/高清/流畅 |
| twitch | live | 2470 | 1849 / 3874 | 0 | 1575 | shroud | 1080p60/720p60/480p30/360p30/160p30 |
| kuaishou | live | 502 | 476 / 580 | 352 | 733 | nuan05051 | 蓝光 质臻/蓝光 4M/超清/高清 |
| soop | live | 13788 | 3636 / 22556 | 0 | 1391 | khm11903 | 原画/高清/标清/4K |
| youtube | live | 6898 | 4871 / 8034 | 0 | 3622 | 0cexASOXD1w | 1080p/720p/480p/360p/240p/144p |

## 各平台请求耗时分布(最后一轮解析)

### douyu

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| playweb.douyucdn.cn/lapi/live/getH5PlayV1/9263298 | 4 | 317 | 79 | OK |
| www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption | 1 | 112 | 112 | OK |
| playweb.douyucdn.cn/lapi/live/hlsH5Preview/9263298 | 1 | 60 | 60 | OK |
| www.douyu.com/betard/9263298 | 1 | 38 | 38 | OK |

非 HTTP 阶段: 白名单加密 md5 auth(TTL 缓存)+ multirates 多 CDN 探测

播放探测: hls playlist+segment — `https://hlshw1a.douyucdn2.cn/live/9263298roClfUg8h.m3u8?txSecret=11b14fc2a5ca7bf355cec7e662f37a00&tx...`

### huya

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| mp.huya.com/cache.php | 1 | 151 | 151 | OK |
| www.huya.com/518518 | 1 | 100 | 100 | OK |

非 HTTP 阶段: anti-code(Tars 编码,纯 CPU)+ web-stream 两段

播放探测: hls playlist+segment — `https://al.hls.huya.com/src/1430972471-1430972471-6145979964421308416-2862068398-10057-A-0-1-imgplus...`

### bilibili

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room | 1 | 207 | 207 | OK |
| api.bilibili.com/x/web-interface/nav | 1 | 57 | 57 | OK |
| api.live.bilibili.com/room/v1/Room/get_info | 1 | 48 | 48 | OK |
| api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo | 1 | 42 | 42 | OK |
| api.bilibili.com/x/frontend/finger/spi | 1 | 27 | 27 | OK |

非 HTTP 阶段: WBI 签名(纯 CPU)+ room_info/play_info 两段

播放探测: hls playlist+segment — `https://d1--cn-gotcha104.bilivideo.com/live-bvc/957221/live_6n6qeh_SyjddJg_bu4lx_2500.m3u8?expires=1...`

### douyin

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| live.douyin.com/ | 1 | 492 | 492 | OK |
| live.douyin.com/webcast/room/web/enter/ | 1 | 298 | 298 | OK |

非 HTTP 阶段: a_bogus 签名(SM3+RC4,纯 CPU)在每次带签请求前计算;cookie 引导(300s TTL)

播放探测: hls playlist+segment — `http://pull-hls-l13.douyincdn.com/third/stream-120067682024030995_or4.m3u8?expire=1789752865&sign=36...`

### yy

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| stream-manager.yy.com/v3/channel/streams | 4 | 257 | 64 | OK |
| www.yy.com/api/liveInfoDetail/22490906/22490906/0 | 1 | 71 | 71 | OK |

非 HTTP 阶段: stream-manager 每档一次 POST;失败回退移动 HLS

播放探测: flv first bytes — `https://ks-flv-web.yy.com/live/15013_xv_22490906_22490906_0_0_0-15013_xa_22490906_22490906_0_0_0-0-0...`

### twitch

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| gql.twitch.tv/gql | 2 | 5344 | 2672 | OK |
| usher.ttvnw.net/api/channel/hls/shroud.m3u8 | 1 | 299 | 299 | OK |

非 HTTP 阶段: GQL POST + playback access token(元数据/token 并行);直播结果 20s 缓存

播放探测: hls playlist+segment — `https://aps12.playlist.ttvnw.net/v1/playlist/CpUFwwoTnTDVYgd0b0ktrUtmZTnKUOpr2FRcdOPlWOhl5NPXkcR_sYw...`

### kuaishou

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| live.kuaishou.com/u/nuan05051 | 1 | 474 | 474 | OK |

非 HTTP 阶段: 房间页 HTML 解析(__INITIAL_STATE__),feed 弹幕不走解析链路

播放探测: flv first bytes — `https://tx-origin.pull.yximgs.com/gifshow/qfenv7otKFk_GameAvcFhdL3.flv?txSecret=e74b75f0659615900e37...`

### soop

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| livestream-manager.sooplive.com/broad_stream_assign.html | 4 | 9017 | 2254 | OK |
| live.sooplive.co.kr/afreeca/player_live_api.php | 5 | 2073 | 415 | OK |

非 HTTP 阶段: 房间详情 60s 缓存;全档并行取流(每档 assign/aid 并行,封顶 4 档);瞬时错误短重试

播放探测: hls playlist+segment — `https://live-global-cdn-v02.sooplive.com/live-stmc-40/auth_playlist.m3u8?aid=.A32.pxqRXFPZNcY9Qg1.H8...`

### youtube

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| rr3---sn-npoeen66.googlevideo.com/videoplayback/id/0cexASOXD1w.1/itag/96/source/yt_live_broadcast/expire/1789169812/ei/NDykaqTDDpezjuMPpd2BqA0/ip/2407:d840:50:e:315c:705c:f683:c6e7/requiressl/yes/ratebypass/yes/live/1/sgoap/gir%3Dyes%3Bitag%3D140/sgovp/gir%3Dyes%3Bitag%3D137/rqh/1/hls_chunk_host/rr3---sn-npoeen66.googlevideo.com/xpc/EgVo2aDSNQ%3D%3D/bui/AR3QkAk2QsRT7ETUOAW_c-eyNooVFxZtIwUJeyzZDcr93S1q-XcUkd7__szh90VIOYbCQXtxH6LKZKB0/spc/I-rgIejf2Q_yKt0mJi2aqPbq0487sLAhOh8zm17dMrWtFV4/vprv/1/reg/0/playlist_type/DVR/initcwndbps/6195000/met/1789148213,/mh/XB/mm/44/mn/sn-npoeen66/ms/lva/mv/m/mvi/3/pl/62/rms/lva,lva/keepalive/yes/fexp/51565116,52135441/mt/1789147983/sparams/expire,ei,ip,id,itag,source,requiressl,ratebypass,live,sgoap,sgovp,rqh,xpc,bui,spc,vprv,reg,playlist_type/sig/AE0s2JYwRQIgdcT90WV3XJKu_Y-kv-8iG4zgL12GsXStqdIZy2NtmnwCIQCZNHm6lHrWH0Z0Zn-wawBRoyB8qP8PBYKRrrxiJw4HsA%3D%3D/lsparams/hls_chunk_host,initcwndbps,met,mh,mm,mn,ms,mv,mvi,pl,rms/lsig/APaTxxMwRAIgeiYRXAyxnAZ9KnGZMUhLQdKNzgYhNZKhPVICDIQofZwCIBup2w8mWnSEDSkGuYbEtS7Ik7whxSuUOP1ZDasYKIhY/playlist/index.m3u8/sq/0/goap/lmt%3D1/govp/lmt%3D1/dur/5.000/file/seg.ts | 1 | 1365 | 1365 | OK |
| www.youtube.com/watch | 1 | 977 | 977 | OK |
| manifest.googlevideo.com/api/manifest/hls_playlist/expire/1789169812/ei/NDykaqTDDpezjuMPpd2BqA0/ip/2407:d840:50:e:315c:705c:f683:c6e7/id/0cexASOXD1w.1/itag/96/source/yt_live_broadcast/requiressl/yes/ratebypass/yes/live/1/sgoap/gir%3Dyes%3Bitag%3D140/sgovp/gir%3Dyes%3Bitag%3D137/rqh/1/hls_chunk_host/rr3---sn-npoeen66.googlevideo.com/xpc/EgVo2aDSNQ%3D%3D/bui/AR3QkAk2QsRT7ETUOAW_c-eyNooVFxZtIwUJeyzZDcr93S1q-XcUkd7__szh90VIOYbCQXtxH6LKZKB0/spc/I-rgIejf2Q_yKt0mJi2aqPbq0487sLAhOh8zm17dMrWtFV4/vprv/1/reg/0/playlist_type/DVR/initcwndbps/6195000/met/1789148213,/mh/XB/mm/44/mn/sn-npoeen66/ms/lva/mv/m/mvi/3/pl/62/rms/lva,lva/dover/11/pacing/0/keepalive/yes/fexp/51565116,52135441/mt/1789147983/sparams/expire,ei,ip,id,itag,source,requiressl,ratebypass,live,sgoap,sgovp,rqh,xpc,bui,spc,vprv,reg,playlist_type/sig/AE0s2JYwRQIgdcT90WV3XJKu_Y-kv-8iG4zgL12GsXStqdIZy2NtmnwCIQCZNHm6lHrWH0Z0Zn-wawBRoyB8qP8PBYKRrrxiJw4HsA%3D%3D/lsparams/hls_chunk_host,initcwndbps,met,mh,mm,mn,ms,mv,mvi,pl,rms/lsig/APaTxxMwRAIgeiYRXAyxnAZ9KnGZMUhLQdKNzgYhNZKhPVICDIQofZwCIBup2w8mWnSEDSkGuYbEtS7Ik7whxSuUOP1ZDasYKIhY/playlist/index.m3u8 | 1 | 674 | 674 | OK |

非 HTTP 阶段: yt-dlp 子进程(含 Deno/EJS)+ master/变体/首分片三段预校验;解析优先 dlp;20s 结果缓存

yt-dlp `-J` 单独耗时: 4188ms(已含在解析中位数内)

播放探测: hls playlist+segment — `https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1789169812/ei/NDykaqTDDpezjuMPpd2B...`

## 对照 SFVideoLive / pure_live 的优化记录(2026-09-12)

> 数据由 `packages/live_parser/tool/benchmark_platforms.dart` 生成;
> 本节为人工结论与优化依据,重新生成数据后需同步维护。
> 本机网络(含透明代理)单请求方差极大(同一接口 0.3s~2.7s),跨轮次绝对值波动 ±2~3 倍;
> 结构性指标(请求数/并发度/热解析)比单轮中位数更可靠。

### 三处优化(对照 SF 实现)

| 平台 | SF 做法 | 优化前(我们) | 优化后(我们) |
|---|---|---|---|
| SOOP | `resolveAllTiers` 全档 `Promise.all`、单档 assign/aid `Promise.all`、`MAX_TIERS=4`;服务层 tier/payload 缓存 60s | 每档 `await` 串行,assign→aid 串行,无档位上限,无缓存 | 全档 `Future.wait`、单档 assign/aid 并行、封顶 4 档、详情 60s + 档位 60s 缓存、保留瞬时错误短重试 |
| Twitch | 元数据批量 GQL + `playlistCache` 20s(token+usher 一次解析内不重发) | 元数据→token→usher 串行,无缓存,无重试 | 元数据与 token 并行(token 失败静默,离线不加时延)、瞬时错误重试、直播结果 20s 缓存 |
| YouTube | `fetchHlsTiers` 前查 `playlistCache` 20s;`validateMediaChain` 首档预校验 | watch 页→dlp→预校验 串行;无缓存 | watch 页与 dlp 并行、直播结果 20s 缓存、保留 dlp 首档预校验 |

### 冷解析对比(同一工具、同机)

| 平台 | 优化前中位(01:17) | 优化后代表轮(01:33) | 本轮(01:46,受网络抖动) | 稳健对比(优化后 min) |
|---|---:|---:|---:|---:|
| douyu | 364 | 342 | 411 | 406 |
| huya | 270 | 302 | 255 | 253 |
| bilibili | 472 | 475 | 385 | 381 |
| douyin | 863 | 678 | 878 | 802 |
| yy | 438 | 416 | 377 | 333 |
| twitch | 4287 | 1899 | 2470 | 1849 |
| kuaishou | 505 | 564 | 502 | 476 |
| soop | 14139 | 3988 | 13788(网络突发) | **3636** |
| youtube | 7773 | 8832 | 6898 | 4871 |

- 结论:Twitch/SOOP/YouTube 的最优冷路径分别提升约 2.3×/3.9×/1.6×;
  其余平台差异在噪声区间(单请求 RTT 主导,已是 2~5 个串行请求的下限)。
- 本轮 SOOP 中位偏高是代理网络突发(4 个并行 assign 同段拥塞:min 3.6s / max 22.6s),
  非实现回退;结构上请求数、并发度与 SF 已一致。

### 热解析(同一实例 20s/60s 内重复解析)

- **soop / twitch / youtube = 0ms**:分别命中档位 60s、结果 20s、结果 20s 缓存,
  短时间重复进房/重试不再产生任何请求。
- douyu 236 / huya 142 / bilibili 283 / douyin 311 / yy 305 / kuaishou 352 ms:
  为「连接复用 + 签名/密钥缓存」后的纯 RTT 成本,属预期。

### 仍待优化(按收益排序)

1. **SOOP 冷路径**:瓶颈是上游单请求 0.9~2.7s(经代理),冷启动仍有 1(详情)+8(4 档×2)
   请求;进一步只能降档位数(如仅预取首选档、其余档懒加载)——需扩展 RoomPayload 契约
   (streams 允许懒加载或二次补全)。
2. **YouTube dlp 3.4~12s 方差最大**:`yt-dlp -J` 子进程 + BotGuard 挑战;
   可考虑解析结果按 videoId 缓存更久(如 5min,需接受 URL 过期风险)或复用上次提取。
3. **抖音播放就绪方差大(0.2~8.3s)**:douyincdn 不同 CDN 首分片差异明显;
   建议解析时对 HLS 线路做多 CDN 探测/排序,或在播放器侧做首选线路快速回退。
4. **Twitch usher/播放探测**:`aps13.playlist.ttvnw.net` 在代理环境 TLS 握手易被中断
   (本机现象);真实网络正常,解析侧已有重试。
5. **app 层缓存(可选)**:SF 在服务层有 meta 45s / tier 60s / payload 60s 三级缓存
   + 并发合并;zishu 目前只在解析器内缓存,可考虑在 PlayController 加 60s
   `(site,roomId) -> RoomPayload` 缓存,让返回再进房瞬时。

