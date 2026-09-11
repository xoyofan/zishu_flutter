# 平台「解析 → 播放」耗时基准

- 生成时间: 2026-09-12 02:18:59
- 环境: Windows 桌面(本机网络,含透明代理;绝对值仅供同环境对比,跨网络需重跑)
- 方法: browse 选首个可解析在播房 → 计分轮带 app 平台默认偏好档(soop 高清 / twitch,youtube 720p / 其余超清),`resolveRoom` 预热 1 次 + 计分 3 次取中位;「热解析」= 同一实例连续解析 3 次中位(带偏好档的 60s 结果缓存与连接复用)
- HTTP 请求耗时经注入的计时 `http.Client` 按 `host+path` 聚合(仅最后一轮冷解析)
- 播放就绪:首选线路首字节探测(HLS = 清单/变体 + 首分片 TTFB;FLV = 首包 TTFB),近似播放器打开等待

## 总览

| 平台 | 状态 | 解析中位(ms) | 最快/最慢(ms) | 热解析中位(ms) | 播放就绪(ms) | 房号 | 档位 |
|---|---|---:|---|---:|---:|---|---|
| douyu | live | 399 | 390 / 437 | 0 | 1065 | 9263298 | 原画1080P30/高清 |
| huya | live | 141 | 131 / 165 | 0 | 303 | 138297 | 蓝光6M/蓝光4M/超清/流畅 |
| bilibili | live | 336 | 241 / 371 | 0 | 614 | 21987615 | 原画/蓝光/超清 |
| douyin | live | 809 | 635 / 841 | 0 | 2313 | 467182558845 | 蓝光/高清/流畅 |
| yy | live | 282 | 248 / 339 | 0 | 52 | 22490906 | 超清/高清/流畅 |
| twitch | live | 853 | 781 / 7902 | 0 | 1997 | caedrel | 原画/720p60/480p/360p/160p |
| kuaishou | live | 541 | 516 / 654 | 0 | 514 | yzdsjujingyi0618 | 蓝光 质臻/蓝光 4M/超清/高清 |
| soop | live | 2369 | 2014 / 18712 | 0 | 704 | phonics1 | 原画/高清/标清/4K |
| youtube | live | 7280 | 4303 / 9518 | 0 | 1682 | EtfmB9iy2-I | 1080p/720p/480p/360p/240p/144p |

## 各平台请求耗时分布(最后一轮解析)

### douyu · 偏好档 超清

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| playweb.douyucdn.cn/lapi/live/getH5PlayV1/9263298 | 4 | 319 | 80 | OK |
| www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption | 1 | 103 | 103 | OK |
| playweb.douyucdn.cn/lapi/live/hlsH5Preview/9263298 | 1 | 64 | 64 | OK |
| www.douyu.com/betard/9263298 | 1 | 38 | 38 | OK |

非 HTTP 阶段: 白名单加密 md5 auth(TTL 缓存);偏好档懒取流(未命中才全档并行);播放接口响应 60s 缓存

播放探测: hls playlist+segment — `https://hlshw1a.douyucdn2.cn/live/9263298roClfUg8h.m3u8?txSecret=e6ca500efc479f909b41ee76be22ef46&tx...`

### huya · 偏好档 超清

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| www.huya.com/138297 | 1 | 129 | 129 | OK |
| mp.huya.com/cache.php | 1 | 116 | 116 | OK |

非 HTTP 阶段: anti-code(Tars 编码,纯 CPU);页面与 profile 并行,web-stream 两段

播放探测: hls playlist+segment — `https://al.hls.huya.com/src/1199531993866-1199531993866-5309087595177705472-2399064111188-10057-A-0-...`

### bilibili · 偏好档 超清

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room | 1 | 171 | 171 | OK |
| api.bilibili.com/x/web-interface/nav | 1 | 84 | 84 | OK |
| api.live.bilibili.com/room/v1/Room/get_info | 1 | 80 | 80 | OK |
| api.bilibili.com/x/frontend/finger/spi | 1 | 69 | 69 | OK |
| api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo | 1 | 66 | 66 | OK |

非 HTTP 阶段: WBI 签名 nav/finger 并行;get_info 已带主播名/头像时跳过 anchor;anchor 与 play_info 并行

播放探测: hls playlist+segment — `https://d1--cn-gotcha104.bilivideo.com/live-bvc/969401/live_6n6qeh_SyjddJg_bu4lx_2500.m3u8?expires=1...`

### douyin · 偏好档 超清

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| live.douyin.com/ | 1 | 467 | 467 | OK |
| live.douyin.com/webcast/room/web/enter/ | 1 | 165 | 165 | OK |

非 HTTP 阶段: a_bogus 签名(SM3+RC4,纯 CPU)在每次带签请求前计算;cookie 引导(300s TTL)

播放探测: hls playlist+segment — `http://pull-hls-l26.douyincdn.com/stage/stream-696528592435675275_or4.m3u8?expire=6aad8037&sign=ed36...`

### yy · 偏好档 超清

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| stream-manager.yy.com/v3/channel/streams | 2 | 165 | 83 | OK |
| www.yy.com/api/liveInfoDetail/22490906/22490906/0 | 1 | 81 | 81 | OK |

非 HTTP 阶段: detail + gear1 探测(命中偏好档时直接复用响应);未命中全档并行

播放探测: flv first bytes — `https://tx-flv-web.yy.com/live/15013_xv_22490906_22490906_0_0_0-15013_xa_22490906_22490906_0_0_0-0-0...`

### twitch · 偏好档 720p

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| gql.twitch.tv/gql | 2 | 987 | 494 | OK |
| usher.ttvnw.net/api/channel/hls/caedrel.m3u8 | 1 | 251 | 251 | OK |

非 HTTP 阶段: GQL POST + playback access token(元数据/token 并行);直播结果 20s 缓存

播放探测: hls playlist+segment — `https://aps13.playlist.ttvnw.net/v1/playlist/CuQEfSZOjdsCW5zc9TrD756qk8pZCMfUm9kCxJNduPx7aOMTBNuSiPo...`

### kuaishou · 偏好档 超清

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| live.kuaishou.com/u/yzdsjujingyi0618 | 1 | 514 | 514 | OK |

非 HTTP 阶段: 房间页 HTML 解析(__INITIAL_STATE__),feed 弹幕不走解析链路

播放探测: flv first bytes — `https://tx-origin.pull.yximgs.com/gifshow/1Dx71Z9ewzE_GameAvcFhdL3.flv?txSecret=9ace5baf593a33f21e90...`

### soop · 偏好档 高清

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| livestream-manager.sooplive.com/broad_stream_assign.html | 1 | 1660 | 1660 | OK |
| live.sooplive.co.kr/afreeca/player_live_api.php | 2 | 819 | 410 | OK |

非 HTTP 阶段: 房间详情/档位 60s 缓存;偏好档懒取流(其余档空线路占位);瞬时错误短重试

播放探测: hls playlist+segment — `https://live-global-cdn-v02.sooplive.com/live-stm-09/auth_playlist.m3u8?aid=.A32.pxqRXFPZNcY9Qg1.lub...`

### youtube · 偏好档 720p

| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |
|---|---:|---:|---:|---|
| manifest.googlevideo.com/api/manifest/hls_playlist/expire/1789172323/ei/A0akauToCKKj9fwPjaS66A4/ip/2407:d840:50:e:315c:705c:f683:c6e7/id/EtfmB9iy2-I.1/itag/96/source/yt_live_broadcast/requiressl/yes/ratebypass/yes/live/1/sgoap/gir%3Dyes%3Bitag%3D140/sgovp/gir%3Dyes%3Bitag%3D137/rqh/1/hls_chunk_host/rr2---sn-npoe7nsr.googlevideo.com/xpc/EgVo2aDSNQ%3D%3D/bui/AR3QkAmvHy2VCMWtRQleRnQQ74rqKhFPfU81Jar66wrqBfBrHkJ-B82S54yDNB8fVI45cMdJEf8bncFL/spc/I-rgIQVk_gsUQPi3dkx7zENqYsskoLdn4VDNOyaP-KxgyIU/vprv/1/reg/0/playlist_type/DVR/hcs/sd/initcwndbps/6208750/met/1789150724,/mh/Yp/mm/44/mn/sn-npoe7nsr/ms/lva/mv/m/mvi/2/pl/62/rms/lva,lva/smhost/rr1---sn-npoe7ndl.googlevideo.com/dover/11/pacing/0/keepalive/yes/fexp/51565115,52135441/mt/1789150345/sparams/expire,ei,ip,id,itag,source,requiressl,ratebypass,live,sgoap,sgovp,rqh,xpc,bui,spc,vprv,reg,playlist_type/sig/AE0s2JYwRQIhAMeDQwIQPi0lV89IgAKPAXGGl7BeJnabh1eG8Hq7gl-LAiA0Hw5mbBUsuyVX-x6Tb8eUr3o0ewnmVK9ExwpiUUh-KQ%3D%3D/lsparams/hls_chunk_host,hcs,initcwndbps,met,mh,mm,mn,ms,mv,mvi,pl,rms,smhost/lsig/APaTxxMwRgIhAJch97p5wdQrv94IA2Z54Pvv6upXPeS_QJrKJlFhBvZZAiEAlsmItQ_uHvmb6D7W9Jli8HrveTPbAaguHGEnmD7DVA4%3D/playlist/index.m3u8 | 1 | 4025 | 4025 | OK |
| rr2---sn-npoe7nsr.googlevideo.com/videoplayback/id/EtfmB9iy2-I.1/itag/96/source/yt_live_broadcast/expire/1789172323/ei/A0akauToCKKj9fwPjaS66A4/ip/2407:d840:50:e:315c:705c:f683:c6e7/requiressl/yes/ratebypass/yes/live/1/sgoap/gir%3Dyes%3Bitag%3D140/sgovp/gir%3Dyes%3Bitag%3D137/rqh/1/hls_chunk_host/rr2---sn-npoe7nsr.googlevideo.com/xpc/EgVo2aDSNQ%3D%3D/bui/AR3QkAmvHy2VCMWtRQleRnQQ74rqKhFPfU81Jar66wrqBfBrHkJ-B82S54yDNB8fVI45cMdJEf8bncFL/spc/I-rgIQVk_gsUQPi3dkx7zENqYsskoLdn4VDNOyaP-KxgyIU/vprv/1/reg/0/playlist_type/DVR/hcs/sd/initcwndbps/6208750/met/1789150724,/mh/Yp/mm/44/mn/sn-npoe7nsr/ms/lva/mv/m/mvi/2/pl/62/rms/lva,lva/smhost/rr1---sn-npoe7ndl.googlevideo.com/keepalive/yes/fexp/51565115,52135441/mt/1789150345/sparams/expire,ei,ip,id,itag,source,requiressl,ratebypass,live,sgoap,sgovp,rqh,xpc,bui,spc,vprv,reg,playlist_type/sig/AE0s2JYwRQIhAMeDQwIQPi0lV89IgAKPAXGGl7BeJnabh1eG8Hq7gl-LAiA0Hw5mbBUsuyVX-x6Tb8eUr3o0ewnmVK9ExwpiUUh-KQ%3D%3D/lsparams/hls_chunk_host,hcs,initcwndbps,met,mh,mm,mn,ms,mv,mvi,pl,rms,smhost/lsig/APaTxxMwRgIhAJch97p5wdQrv94IA2Z54Pvv6upXPeS_QJrKJlFhBvZZAiEAlsmItQ_uHvmb6D7W9Jli8HrveTPbAaguHGEnmD7DVA4%3D/playlist/index.m3u8/sq/0/goap/lmt%3D1/govp/lmt%3D1/dur/0.767/file/seg.ts | 1 | 2228 | 2228 | OK |
| www.youtube.com/watch | 1 | 1915 | 1915 | OK |

非 HTTP 阶段: yt-dlp 子进程(含 Deno/EJS;提取结果与地址链校验 60s 实例缓存)+ master/变体/首分片三段预校验;解析优先 dlp;结果 20s 缓存

yt-dlp `-J` 单独耗时: 2815ms(已含在解析中位数内)

播放探测: hls playlist+segment — `https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1789172323/ei/A0akauToCKKj9fwPjaS6...`

## 优化记录(人工维护,重新生成数据后同步更新)

> 数据由 `packages/live_parser/tool/benchmark_platforms.dart` 生成;
> 本机网络(含透明代理)单请求方差大,结构性指标(请求数/并发度/缓存命中)比单轮中位数更可靠。
> 本轮起计分轮带 app 各平台默认偏好档(soop 高清 / twitch,youtube 720p / 其余超清),
> 与更早的「全档枚举」口径不完全可比;懒取流的平台只解析偏好档。

### 本轮优化(2026-09-12,对照 SF 服务层缓存与各站实现)

| 平台 | 改动 | 效果 |
|---|---|---|
| 全部 | 注册表出口 `CachedRoomResolver`:带偏好档进房 **60s 结果缓存**(对齐 SF 服务层 payload 60s;仅缓存成功在播结果,并发同键合并) | 热解析 9 平台全为 **0ms**;重进/短窗口回访零请求 |
| 斗鱼 | 偏好档懒取流(命中即只取该档,跳过其余 CDN 的 rate=0 探测);未命中时档间 `Future.wait` 并行;`getH5PlayV1` 响应按 (rid,rate,cdn) 缓存 60s | 冷解析 411→399ms;切档成功响应不再重打播放接口 |
| YY | 原「逐档串行 4 次 POST」→ detail + gear1 探测;命中偏好档直接复用探测响应;未命中全档并行;档位 60s 缓存 | 冷解析 377→282ms;切档命中缓存 |
| 虎牙 | 页面与 profile 改为并行(原先串行) | 冷解析 255→141ms |
| B 站 | nav(WBI)与 finger(buvid3)并行;get_info 已带主播名/头像时跳过 `get_anchor_in_room`;anchor 兜底与 play_info 并行 | 冷解析 385→336ms;信息齐全的房少 1 次请求 |
| SOOP | (上一提交)`resolveTier` 懒取流 + 档位 60s 缓存 | 请求数 9→3,中位 13788→2369ms(assign 单次 2s 级上游波动占主导) |
| YouTube | dlp 提取结果与地址链校验 60s **实例级**缓存:切档/换偏好档不重跑子进程与三段预校验(模块级会污染冷解析口径,故放实例) | 切档从 4~7s 降到 ~1s(仅 watch 页元数据);冷解析仍是 dlp 主导 |
| Twitch | (上一提交)元数据/token 并行 + 20s 缓存,本轮无改动 | 冷解析中位 2470→853ms(波动大:781~7902) |

### 冷解析对比(同一工具、同机)

| 平台 | 01:46 全档口径(ms) | 本轮 app 口径(ms) | 本轮 min(ms) | 说明 |
|---|---:|---:|---:|---|
| douyu | 411 | 399 | 390 | 每档多 CDN + 白名单签名;已到 2~3 RTT 下限 |
| huya | 255 | 141 | 131 | 页面/profile 并行后 ≈ 单请求 RTT |
| bilibili | 385 | 336 | 241 | nav/finger 并行 + anchor 条件化;本房缺 face 仍有 1 次 anchor |
| douyin | 878 | 809 | 635 | cookie 引导(300s)+ enter 两段,受首页 0.5s 级 RTT 主导 |
| yy | 377 | 282 | 248 | 4→2 次请求(探测 + 偏好档) |
| twitch | 2470 | 853 | 781 | GQL 与 token 并行;网络波动大 |
| kuaishou | 502 | 541 | 516 | 单请求页面解析,差异在噪声区间 |
| soop | 13788 | 2369 | 2014 | 懒取流:3 次请求(详情/assign/aid) |
| youtube | 6898 | 7280 | 4303 | dlp 子进程 2.8~4.7s + 三段预校验;方差最大 |

### 热解析(同一实例 20s/60s 内重复解析)

- **9 平台全部 0ms**:带偏好档的结果 60s 缓存(SOOP/Twitch/YouTube 自身缓存叠加),
  短时间重复进房/重试不再产生任何请求。
- 切档场景:YY 档位缓存、斗鱼播放响应缓存、SOOP 档位缓存、YouTube dlp 提取+校验缓存
  均命中,仅 watch 页元数据等必要请求。

### 仍待优化(按收益排序)

1. **YouTube 冷路径**:dlp 子进程 2.8~4.7s + master/变体/分片三段预校验(≈2-3s,本轮分片 2.2s);
   反爬路线决定其下限,进一步优化需要预先 warm 或缩短校验,风险高,暂保持。
2. **抖音/斗鱼播放就绪波动**:CDN 首分片 TTFB 差异大(0.3~8.6s),属播放侧线路选择,
   可在播放器做首选线路快速回退(非解析链路)。
3. **斗鱼「偏好档未命中」**:默认档不在该房档位列表时回落全档枚举(与 app `_pickQuality`
   「没有才退」一致),多花 1~2 RTT;可考虑未命中时取最接近档,但会改变现有语义,待产品确认。
4. **B 站 anchor 兜底**:部分房间 get_info 缺 face,仍需 1 次 155ms 级兜底请求;无安全替代。
