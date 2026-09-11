# 平台「解析 → 播放」耗时基准

- 生成时间: 2026-09-12 01:17:23
- 环境: Windows 桌面(本机网络,含透明代理;绝对值仅供同环境对比,跨网络需重跑)
- 方法: browse 选首个可解析在播房 → `resolveRoom` 7 次(1 预热 + 3 计分 ×最多 4 候选房),计分轮取中位;HTTP 请求耗时经注入的计时 `http.Client` 按 `host+path` 聚合
- 播放就绪:首选线路首字节探测(HLS = 清单/变体 + 首分片 TTFB;FLV = 首包 TTFB),近似播放器打开等待

## 总览

| 平台 | 状态 | 解析中位(ms) | 最快/最慢(ms) | 播放就绪(ms) | 房号 | 档位 |
|---|---|---:|---|---:|---|---|
| douyu | live | 364 | 331 / 397 | 1082 | 9263298 | 原画1080P30/高清 |
| huya | live | 270 | 267 / 312 | 359 | 518518 | 蓝光20M/蓝光8M/蓝光4M/超清/流畅 |
| bilibili | live | 472 | 470 / 477 | 648 | 21987615 | 原画/蓝光/超清 |
| douyin | live | 863 | 782 / 923 | 4449 | 25204930060 | 蓝光/超清/高清/流畅 |
| yy | live | 438 | 391 / 543 | 322 | 22490906 | 超清/高清/流畅 |
| twitch | live | 4287 | 2259 / 4287 | - | caedrel | 原画/720p60/480p/360p/160p |
| kuaishou | live | 505 | 503 / 506 | 682 | 3xumpdgrirtsasq | 蓝光Plus/蓝光/超清/高清 |
| soop | live | 14139 | 11170 / 31414 | 777 | khm11903 | 原画/高清/标清/4K |
| youtube | live | 7773 | 5001 / 8003 | 884 | 0cexASOXD1w | 1080p/720p/480p/360p/240p/144p |

## 各平台请求耗时分布(最后一轮解析)

### douyu

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| playweb.douyucdn.cn/lapi/live/getH5PlayV1/9263298 | 4 | 306 | 77 | OK |
| www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption | 1 | 120 | 120 | OK |
| playweb.douyucdn.cn/lapi/live/hlsH5Preview/9263298 | 1 | 56 | 56 | OK |
| www.douyu.com/betard/9263298 | 1 | 24 | 24 | OK |

非 HTTP 阶段: 白名单加密 md5 auth(TTL 缓存)+ multirates 多 CDN 探测

播放探测: hls playlist+segment — `https://hlshw1a.douyucdn2.cn/live/9263298roClfUg8h.m3u8?txSecret=a0fe3d20dbb8d0880df0d635c5a3b208&tx...`

### huya

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| mp.huya.com/cache.php | 1 | 158 | 158 | OK |
| www.huya.com/518518 | 1 | 110 | 110 | OK |

非 HTTP 阶段: anti-code(Tars 编码,纯 CPU)+ web-stream 两段

播放探测: hls playlist+segment — `https://al.hls.huya.com/src/1430972471-1430972471-6145979964421308416-2862068398-10057-A-0-1-imgplus...`

### bilibili

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room | 1 | 201 | 201 | OK |
| api.live.bilibili.com/room/v1/Room/get_info | 1 | 111 | 111 | OK |
| api.bilibili.com/x/web-interface/nav | 1 | 74 | 74 | OK |
| api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo | 1 | 59 | 59 | OK |
| api.bilibili.com/x/frontend/finger/spi | 1 | 28 | 28 | OK |

非 HTTP 阶段: WBI 签名(纯 CPU)+ room_info/play_info 两段

播放探测: hls playlist+segment — `https://d1--cn-gotcha104.bilivideo.com/live-bvc/355017/live_6n6qeh_SyjddJg_bu4lx_2500.m3u8?expires=1...`

### douyin

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| live.douyin.com/ | 1 | 611 | 611 | OK |
| live.douyin.com/webcast/room/web/enter/ | 1 | 249 | 249 | OK |

非 HTTP 阶段: a_bogus 签名(SM3+RC4,纯 CPU)在每次带签请求前计算;cookie 引导(300s TTL)

播放探测: hls playlist+segment — `http://pull-hls-f11.douyincdn.com/stage/stream-408297970868421290_or4.m3u8?expire=1789751686&sign=9d...`

### yy

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| stream-manager.yy.com/v3/channel/streams | 4 | 441 | 110 | OK |
| www.yy.com/api/liveInfoDetail/22490906/22490906/0 | 1 | 96 | 96 | OK |

非 HTTP 阶段: stream-manager 每档一次 POST;失败回退移动 HLS

播放探测: flv first bytes — `https://ks-flv-web.yy.com/live/15013_xv_22490906_22490906_0_0_0-15013_xa_22490906_22490906_0_0_0-0-0...`

### twitch

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| gql.twitch.tv/gql | 2 | 3075 | 1538 | OK |
| usher.ttvnw.net/api/channel/hls/caedrel.m3u8 | 1 | 1210 | 1210 | OK |

失败轮次:
- 9671ms: ClientException: Connection closed before full header was received, uri=https://usher.ttvnw.net/api/channel/hls/caedrel.m3u8?client_id=kimne78kx3ncx6brgo4mv6wki5h1ko&token=%7B%22adblock%22%3Afalse%2C%22authorization%22%3A%7B%22forbidden%22%3Afalse%2C%22reason%22%3A%22%22%7D%2C%22blackout_enabled%22%3Afalse%2C%22channel%22%3A%22caedrel%22%2C%22channel_id%22%3A92038375%2C%22chansub%22%3A%7B%22restricted_bitrates%22%3A%5B%5D%2C%22view_until%22%3A1924905600%7D%2C%22ci_gb%22%3Afalse%2C%22geoblock_reason%22%3A%22%22%2C%22device_id%22%3Anull%2C%22expires%22%3A1789148104%2C%22extended_history_allowed%22%3Afalse%2C%22game%22%3A%22%22%2C%22hide_ads%22%3Afalse%2C%22https_required%22%3Atrue%2C%22mature%22%3Afalse%2C%22notification_id%22%3Anull%2C%22partner%22%3Afalse%2C%22platform%22%3A%22web%22%2C%22player_type%22%3A%22site%22%2C%22private%22%3A%7B%22allowed_to_view%22%3Atrue%7D%2C%22privileged%22%3Afalse%2C%22role%22%3A%22%22%2C%22server_ads%22%3Atrue%2C%22show_ads%22%3Atrue%2C%22subscriber%22%3Afalse%2C%22turbo%22%3Afalse%2C%22user_id%22%3Anull%2C%22user_ip%22%3A%22103.172.182.27%22%2C%22version%22%3A3%2C%22maximum_resolution%22%3A%22FULL_HD%22%2C%22maximum_video_bitrate_kbps%22%3A12500%2C%22maximum_resolution_reasons%22%3A%7B%22QUAD_HD%22%3A%5B%22AUTHZ_GEO%22%2C%22AUTHZ_NOT_LOGGED_IN%22%5D%2C%22ULTRA_HD%22%3A%5B%22AUTHZ_GEO%22%2C%22AUTHZ_NOT_LOGGED_IN%22%5D%7D%2C%22maximum_video_bitrate_kbps_reasons%22%3A%5B%22AUTHZ_DISALLOWED_BITRATE%22%5D%7D&sig=33732b9803440ad574ee355b18439e5f672c21c3&allow_source=true&allow_audio_only=true&type=any

非 HTTP 阶段: GQL POST + playback access token

播放探测: probe error: HandshakeException: Connection terminated during handshake — `https://aps13.playlist.ttvnw.net/v1/playlist/CuME51czsYjOUwgsk_uH_qDTtFD2rKxRDq640cKD2SU4F5Mkv3jfSkp...`

### kuaishou

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| live.kuaishou.com/u/3xumpdgrirtsasq | 1 | 503 | 503 | OK |

非 HTTP 阶段: 房间页 HTML 解析(__INITIAL_STATE__),feed 弹幕不走解析链路

播放探测: flv first bytes — `https://tx-origin.pull.yximgs.com/gifshow/RiEcqhscyMU_GameAvcFhdL3Lto.flv?txSecret=46ca5ae35f5e09fe2...`

### soop

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| live.sooplive.co.kr/afreeca/player_live_api.php | 7 | 19728 | 2818 | 2 失败 |
| livestream-manager.sooplive.com/broad_stream_assign.html | 4 | 11067 | 2767 | OK |

非 HTTP 阶段: 每档画质 assign+aid 两次请求;批量并发时上游为短连接(已加 Connection: close+重试)

播放探测: hls playlist+segment — `https://live-global-cdn-v02.sooplive.com/live-stmc-40/auth_playlist.m3u8?aid=.A32.pxqRXFPZNcY9Qg1.H8...`

### youtube

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| manifest.googlevideo.com/api/manifest/hls_playlist/expire/1789168635/ei/mzekaq6FAaydssUPlKfZgAs/ip/2407:d840:50:e:315c:705c:f683:c6e7/id/0cexASOXD1w.1/itag/96/source/yt_live_broadcast/requiressl/yes/ratebypass/yes/live/1/sgoap/gir%3Dyes%3Bitag%3D140/sgovp/gir%3Dyes%3Bitag%3D137/rqh/1/hls_chunk_host/rr3---sn-npoeen66.googlevideo.com/xpc/EgVo2aDSNQ%3D%3D/bui/AR3QkAnNuLbQWLrxpQMJumWahnPJMsNafOYSvDC2NvCP5QG2zz8PzZWytbCJ7orCGSz1m2wXuzG470Jz/spc/I-rgIZN8ejLdQswwm2T5qymUu1XRwJ22TWLVrJRJGEpd16w/vprv/1/reg/0/playlist_type/DVR/initcwndbps/6195000/met/1789147035,/mh/XB/mm/44/mn/sn-npoeen66/ms/lva/mv/m/mvi/3/pl/62/rms/lva,lva/dover/11/pacing/0/keepalive/yes/fexp/51565115,52135441,52178455/mt/1789146547/sparams/expire,ei,ip,id,itag,source,requiressl,ratebypass,live,sgoap,sgovp,rqh,xpc,bui,spc,vprv,reg,playlist_type/sig/AE0s2JYwRAIgImdjnsiZ0eXreLB_WQ3uNd8VjrjuuJVbKCYFBfdRh8ACIA8kS9-fNoHsSvzKv_3DfNp07RkgNUUEdrGd1GEazjUs/lsparams/hls_chunk_host,initcwndbps,met,mh,mm,mn,ms,mv,mvi,pl,rms/lsig/APaTxxMwRQIgEhdzmw49WdZNcxJYGNXvDzoxDMZ3QNuBMjXuDjeI7vcCIQCkMVuXrNCjPs1IN3LVsSSvVOgJuVh0ebNafnh3Dd6wOg%3D%3D/playlist/index.m3u8 | 1 | 1789 | 1789 | OK |
| rr3---sn-npoeen66.googlevideo.com/videoplayback/id/0cexASOXD1w.1/itag/96/source/yt_live_broadcast/expire/1789168635/ei/mzekaq6FAaydssUPlKfZgAs/ip/2407:d840:50:e:315c:705c:f683:c6e7/requiressl/yes/ratebypass/yes/live/1/sgoap/gir%3Dyes%3Bitag%3D140/sgovp/gir%3Dyes%3Bitag%3D137/rqh/1/hls_chunk_host/rr3---sn-npoeen66.googlevideo.com/xpc/EgVo2aDSNQ%3D%3D/bui/AR3QkAnNuLbQWLrxpQMJumWahnPJMsNafOYSvDC2NvCP5QG2zz8PzZWytbCJ7orCGSz1m2wXuzG470Jz/spc/I-rgIZN8ejLdQswwm2T5qymUu1XRwJ22TWLVrJRJGEpd16w/vprv/1/reg/0/playlist_type/DVR/initcwndbps/6195000/met/1789147035,/mh/XB/mm/44/mn/sn-npoeen66/ms/lva/mv/m/mvi/3/pl/62/rms/lva,lva/keepalive/yes/fexp/51565115,52135441,52178455/mt/1789146547/sparams/expire,ei,ip,id,itag,source,requiressl,ratebypass,live,sgoap,sgovp,rqh,xpc,bui,spc,vprv,reg,playlist_type/sig/AE0s2JYwRAIgImdjnsiZ0eXreLB_WQ3uNd8VjrjuuJVbKCYFBfdRh8ACIA8kS9-fNoHsSvzKv_3DfNp07RkgNUUEdrGd1GEazjUs/lsparams/hls_chunk_host,initcwndbps,met,mh,mm,mn,ms,mv,mvi,pl,rms/lsig/APaTxxMwRQIgEhdzmw49WdZNcxJYGNXvDzoxDMZ3QNuBMjXuDjeI7vcCIQCkMVuXrNCjPs1IN3LVsSSvVOgJuVh0ebNafnh3Dd6wOg%3D%3D/playlist/index.m3u8/sq/0/goap/lmt%3D1/govp/lmt%3D1/dur/5.000/file/seg.ts | 1 | 1670 | 1670 | OK |
| www.youtube.com/watch | 1 | 1260 | 1260 | OK |

非 HTTP 阶段: yt-dlp 子进程(含 Deno/EJS)+ master/变体/首分片三段预校验;解析优先 dlp

yt-dlp `-J` 单独耗时: 3374ms(已含在解析中位数内)

播放探测: hls playlist+segment — `https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1789168635/ei/mzekaq6FAaydssUPlKfZ...`

## 耗时分布与改进点(人工分析,随版本更新)

> 以上数据由 `packages/live_parser/tool/benchmark_platforms.dart` 生成;
> 本节为人工结论,重新生成数据后需同步维护。

### 房间解析(中位)

- **第一梯队 < 0.6s**:虎牙 270 / 斗鱼 364 / YY 438 / B站 472 / 快手 505。
  成本主要是 2~5 个串行 API + 强签名 CPU,已接近网络 RTT 下限。
- **抖音 863ms**:cookie 引导(首页 611ms)+ enter 249ms。cookie 300s TTL 到期后
  每次解析都会重付 ~0.6s。建议 TTL 提到 30min,或在 app 启动时预热一次。
- **Twitch 4287ms**:`gql` ×2 合计 3.1s(均值 1.5s/次)+ `usher` 1.2s,且出现
  「连接被提前关闭」失败轮(当前无重试)。建议:① playback token / gql 结果按
  进程缓存到 token 过期;② 瞬时传输错误重试 2 次;③ 两次 gql 若互不依赖可并发。
- **YouTube 7773ms**:`yt-dlp -J` 3.4s + master/首分片预校验 ~3.4s + watch 页 1.3s。
  建议:① watch 页与 dlp 提取 `Future.wait` 并发;② dlp 成功后跳过三段预校验
  (刚签出的 URL 仍新鲜,或仅保留首分片 Range);③ dlp 结果按 videoId 短缓存(≈5min)。
- **SOOP 14139ms(最大头)**:`player_live_api` ×7 合计 19.7s(含 2 次失败重试)、
  `broad_stream_assign` ×4 合计 11.1s;且每档画质 assign+aid 两次请求**串行**。
  建议:① 各档取流 `Future.wait` 并发(约 8×RTT → 2×RTT);② 去掉
  `Connection: close`(经代理每次新 TLS 握手 1~2s),仅保留失败重试;
  ③ assign 与 aid 无时序依赖,可并行。

### 播放就绪(清单 + 首分片 TTFB)

- **< 0.4s**:YY 322 / 虎牙 359。
- **0.6 ~ 1.1s**:B站 648 / 快手 682 / SOOP 777(解析耗时后 CDN 已热)/
  YouTube 884 / 斗鱼 1082。
- **抖音 4449ms**:douyincdn 首分片 TTFB 明显偏慢(本环境/CDN 侧),解析仅 863ms;
  可考虑在首选 CDN 超时后自动切备用线路,或对抖音优先 FLV(首包更快)。
- **Twitch 探测失败**:`aps13.playlist.ttvnw.net` TLS 握手被中断(本机代理环境),
  重试后可缓解;真实网络下应正常。

### 建议优先序(收益/成本)

1. **SOOP**:档位取流并发 + 去掉 `Connection: close`(预计 14s → 2~3s)。
2. **YouTube**:watch/dlp 并发 + dlp 免预校验(预计 7.8s → 3~4s)。
3. **抖音**:cookie TTL 提升 + 启动预热(首房 0.86s → ~0.25s;后续房间本就是 0.25s 级)。
4. **Twitch**:token/gql 缓存 + 瞬时错误重试(预计 4.3s → 1~2s)。

