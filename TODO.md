# TODO / 待办事项

> 更新日期:2026-08-21

## 一、功能待办

- [ ] **iOS 构建与验证**(需 macOS + Xcode):`flutter build ios`、Patrol iOS 测试(`ios/RunnerUITests` SPM 集成)尚未真机/模拟器验证
- [ ] **iOS 蒲公英上传脚本**完整跑通一次
- [x] **Android release 正式签名**:`android/app/build.gradle.kts` 已支持 `android/key.properties` 驱动签名;存在该文件即用正式 keystore,否则回退 debug(不破坏本地/CI)。用户只需按 `android/key.properties.example` 说明生成 keystore 并填入即可
- [x] **下载断点续传**:`HttpModelDownloader` 支持 `Range` 续传(206 追加 / 200 整包覆盖 / 416 删除重试);`ModelManager` 网络失败时保留部分文件供下一个源/下次续传。含 `test/model_downloader_test.dart` 与 `test/model_manager_test.dart` 用例
- [x] **多模型并发下载体验确认**:已支持——每模型独立 `CancelToken` 与下载/取消按钮,数据层可并发;已确认无需改代码
- [x] **词级时长启发式改进**:sherpa-onnx `OfflineTts.generate` 不暴露真实词级时间戳(等官方),已将启发式升级——英文按"元音簇"估音节数、数字按位数,比纯字符数更贴近朗读时长;CJK 按字符数(1 字≈1 音节)(`lib/tts/text_chunker.dart`)
- [x] **i18n 本地化**:接入 `flutter_localizations` + `gen-l10n`(`lib/l10n/` + `l10n.yaml` + `flutter: generate: true`);`AppLocalizations` 支持 zh/en,跟随系统语言回退中文;主要界面文案已迁移(`app.dart` / `synthesize_page` / `tts_settings_page` / `model_manage_page` / `main_shell` / 气泡视图),含 `test/l10n_test.dart`
- [x] **设置页"自定义镜像"输入**:改为"自动 / 自定义前缀 + 输入框",可输入任意前缀(`lib/ui/tts_settings_page.dart`)
- [x] **模型校验**:下载后除 bzip2 魔数外,新增 `model.onnx` 非平凡大小校验(<1KB 判为损坏)(`lib/data/model_manager.dart`)
- [x] **CI 集成**:新增 GitHub Actions workflow(`.github/workflows/ci.yml`)跑 `flutter analyze` + 单测;打 tag 自动打包待接入

## 二、代码审查发现(2026-08-21 首轮审查)

> 首轮审查完成后,以下项已在本轮修复/清理。

### 2.1 需修复

- [x] **【Bug】历史恢复的气泡点击"重读"无声音**
  - 位置:`lib/tts/tts_streaming_service.dart` `replayUtterance()`
  - 修复:`Utterance` 分块字段改为可变;`replayUtterance` 检测 `segments` 为空时用 `normalizedText` 重新 `splitWords` + `_buildProgressiveChunks` 重建再走拉取式合成播放;新增测试验证

### 2.2 建议清理(死代码)

- [x] **删除 `replaySegment`**——已被 `replayUtterance` 取代,全工程无引用
- [x] **删除 `ModelManager.effectiveUrl`**——已被 `downloadCandidates` 取代,无引用
- [x] **删除 `TtsStreamingService.segmentWords` 公共 getter**——视图已改用 `utterance.allWords`/`utterance.segmentWords`,测试同步改用后者

### 2.3 建议完善

- [x] **widget 冒烟测试补充"发送后输入框清空"断言**
- [x] **model_manager 多镜像回退单元测试**:新增 `test/model_manager_test.dart`,验证候选顺序(手动镜像 → 国内代理 → 直连)、失败自动切换、bzip2 魔数校验拒收错误页
- [x] **双源状态收敛**:运行时以 ChangeNotifier 为单一事实源,dva 只做持久化写入;`TtsSettings.load()` / `ModelManager.load()` / `TtsStreamingService.loadHistory()` 均改为"仅首次生效"(幂等),避免运行时改动被重复 load 覆盖(`lib/models/tts_settings.dart` 等)
- [x] **耗时统计 UI 折叠/展开**:`speaking_bubbles_view.dart` 长气泡的耗时统计默认折叠为"耗时统计 ▸",点击展开,避免占空间
- [x] **`_buildProgressiveChunks` 与 `_addPatternChunks`** 注释已同步分块策略演进(首句 1+4+10、后续整句、长句 10)
- [x] **性能**:后台 isolate 音频采样改用 `TransferableTypedData` 零拷贝移交(`lib/tts/tts_engine.dart`),长文本避免逐段 Float32List 跨 isolate 拷贝;含 `test/isolate_transfer_test.dart` 验证

### 2.4 长文本卡"合成中"无声音(本轮新增修复)

- [x] **根因**:急切串行合成 + 无界队列 + 播放器无看门狗,主 isolate 过载、`onPlayerComplete`/`onPrepared` 丢失即永久卡死
- [x] **修复**:`SequentialAudioPlayer` 重写为**拉取式 + 1 段预取 + 完成看门狗 + play 超时 + provider 超时**,内存有界、可自愈;`TtsStreamingService` 改为按需合成(provider 回调),`onQueueDrained` 仅在真正播完最后一段触发
- [x] **模型预加载**:进入合成页(应用启动)后台预加载所选模型,已加载则忽略;加载期间发送按钮禁用(`modelLoading`)
- [x] **测试**:新增 `test/player_heal_test.dart`(看门狗自愈)、历史重读测试;全量 30 个单测/冒烟通过
