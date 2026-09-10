/// 画质档位:与实际可播放的 streams **严格同源**,保持顺序与原名,不补档、不重排。
///
/// 历史问题:此前直接从 getH5PlayV1 的 multirates 全量生成,于是当某一档的
/// 全部线路都取流失败时,该档仍留在 availableQualities 里、但 streams 中已没有
/// 对应项 —— UI 画质 chip 点击后在 streams 里找不到同名项,表现为**静默无反应
/// 的死键**。现在改为只暴露真正拿到线路的档位,保证
/// 「列出来的档 = 点得动的档」。
library;

import '../../models/models.dart';

List<QualityOption> douyuAvailableQualities(List<StreamQuality> streams) => [
  for (final stream in streams)
    QualityOption(name: stream.name, rate: stream.rate),
];
