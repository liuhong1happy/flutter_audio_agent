# TODO / 主计划 — 语音对话 + 声音克隆 + 声纹识别(自足交接文档)

> 更新日期:2026-09-29
> 本文件是**自足交接文档**:包含功能清单、实施追踪、以及全部已核实的实现知识(sherpa_onnx API 签名、模型 URL/体积、现有代码地图、设计决策、坑位)。在任意新机器上仅凭本文件即可实施,无需本机缓存或记忆。
> 关联:详细设计现状见 `docs/敏捷开发/v1.0.2 APP设计内容.md`(**规划中,下一版本**)、
> `docs/敏捷开发/v1.0.1 APP设计内容.md`(当前已发布版本)、`docs/敏捷开发/v1.0.0 APP设计内容.md`(纯 TTS 基线)、`README.md`。
>
> **2026-09-29 第二轮追加**:v1.0.2 规划 —— **本地知识库 + 本地短期记忆 + 本地长期记忆**。
> 详见[第十一节](#十一v102-规划2026-09-29-追加)与新增阶段 12–17,坑位 18–39;
> 完整设计见 `docs/敏捷开发/v1.0.2 APP设计内容.md`。**尚未写一行实现代码。**
>
> **2026-09-29 追加**:第一~九阶段已全部实施完成,本轮在此之上做了**声纹能力扩展**(双声纹模型
> 选择 / 对话声纹门禁 / 按说话人切克隆音色 / 声纹写操作的设备认证)。新增内容集中在
> [第九节](#九声纹能力扩展2026-09-29)与[第六节](#六实施阶段每阶段可验证)的阶段 11,
> 新增坑位见[第七节](#七风险与坑实施必读) 13–17。**原第一~九节的描述仍是准确的**,只有
> 声纹相关处(2.2 模型表、3.3 API 面、5.7 设置)按本轮改动做了修订。

---

## 〇、一句话目标

给 flutter_tts_demo(现为纯离线 TTS,仅用 sherpa_onnx `OfflineTts` 的 vits/kokoro 族)新增**「语音对话」**核心页(VAD 常开免按 → 离线 ASR → 声纹识别说话人 → 在线 LLM → TTS 语音回复),并附带**声音克隆**(配置型,PocketTTS 零样本克隆音,对话可选发音)与**声纹识别**(对话中自动识别说话人,非独立 Tab)。

### 已确认决策(不要改)
- **LLM = DeepSeek V4 Flash 在线版**(OpenAI 兼容 API,`chat/completions` 流式)。这是**唯一联网组件**;ASR/TTS/克隆/声纹/VAD 全部离线。
- 平台 **Android 优先**(v1 只在 Android 验证;iOS 本期不做,但代码尽量平台无关)。
- 对话页做**一键初始化**:未就绪时显示三件套(VAD/ASR/TTS)卡片,一键下载默认模型并自动配置。
- 克隆与声纹为**配置型能力**,不对应独立底部 Tab;底部导航共 3 个 Tab(合成 / 对话 / 设置,模型下载并入设置页各分类子页)。
- 说话人识别深度 = **个性化对话 + 按人记忆**:身份注入 LLM 提示词、未知说话人访客模式。**不做**按说话人换发音(超范围)。

> **设计变更(2026-08-23,用户确认)**:
> - 会话历史**不再按说话人分桶**,改为**单一时间线**(多说话人共一个会话),按时间排序;**存储从 flutter_dva/SharedPreferences 迁到 SQLite**(`sqflite`,`version`+`onUpgrade` 版本化迁移),支持分页。
> - **对话双模式**:音频模式(语音→ASR→声纹→LLM→TTS 语音回复,仅显示最后一轮)与文本模式(打字→LLM 纯文本回复,不转 TTS,显示全部);Header 左侧历史、中间模式切换、右侧设置按钮。
> - **设置页两级**:首页大类 ListItem → 子页配置 + 各自模型下载;底部 3 Tab(合成/对话/设置,移除「模型」Tab)。
> - **LLM 多服务商**:OpenAI 兼容,内置 DeepSeek(`deepseek-v4-flash`/`deepseek-v4-pro`)/ Moonshot / 智谱 / 通义千问 + 自定义。
> - **声纹注册改整页**(圆形居中录音按钮,支持连续注册多个说话人)。

---

## 一、新增依赖

```yaml
dependencies:
  record: ^7.1.1   # 麦克风:持续 PCM16 流 startStream() / wav 落盘 start()
```
- `record` 7.x 要求 Android **minSdk ≥ 23**。若构建失败,改 `android/app/build.gradle.kts`:`minSdk = maxOf(flutter.minSdkVersion, 23)`。
- `AndroidManifest.xml` 加 `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`(INTERNET 已有)。
- 其余全部复用现有依赖:dio(下载 + LLM SSE)、path/path_provider、archive、provider、flutter_dva、jieba_flutter、sherpa_onnx ^1.13.6。

---

## 二、模型目录(全部 URL 与体积已从 k2-fsa GitHub release API 核实)

### 2.1 现有 7 项(tts;晓雅为默认,列表供参考)
来源基址:`https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models`;代理列表 `kChinaGitHubProxies = ['https://ghfast.top/','https://ghproxy.net/','https://gh-proxy.com/','https://ghps.cc/']`

| id | 说明 | 字节 | speakers | sampleRate |
|---|---|---|---|---|
| vits-piper-zh_CN-xiao_ya-medium-int8 | Piper 晓雅 | 14,016,124 | 1 | 22050 |
| vits-piper-zh_CN-chaowen-medium-int8 | Piper 超文(男声) | 14,011,298 | 1 | 22050 |
| vits-piper-zh_CN-huayan-medium | Piper huayan(女声,fp32) | 67,255,926 | 1 | 22050 |
| vits-zh-hf-fanchen-C | Fanchen C | 119,326,431 | 187 | 16000 |
| vits-melo-tts-zh_en | MeloTTS 中英混读 | 167,006,755 | 1 | 44100 |
| vits-zh-hf-theresa | Theresa | 120,596,617 | 804 | 22050 |
| kokoro-multi-lang-v1_0 | Kokoro 中英混读 | 349,418,188 | 53 | 24000 |

### 2.2 新增 5 项
| kind | id | 资产 & 基址 | 字节 | 文件形状 |
|---|---|---|---|---|
| asrParaformer(默认) | sherpa-onnx-paraformer-zh-2023-09-14 | `asr-models` 下 `…/sherpa-onnx-paraformer-zh-2023-09-14.tar.bz2` | 234,051,698 | 解压后 model.onnx + tokens.txt |
| asrSenseVoice(可选) | sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17 | `asr-models` 下同名 tar.bz2(**注意:int8 在日期前**;`…-2024-07-17.tar.bz2` 无 int8 的是 fp32 ~1GB,勿用) | 163,002,883 | model.onnx + tokens.txt |
| speaker(默认) | 3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k | `speaker-recongition-models`(基址名是官方这个拼写,带 typo)下 **裸 `….onnx`** | 39,593,761 | 单文件 onnx,无解压 |
| speaker(可选) | 3dspeaker_speech_campplus_sv_zh-cn_16k-common | 同上基址下**裸 `….onnx`**(2026-09-29 实测:直连 302→200,`Content-Length: 28281138`,无需代理) | 28,281,138 | 单文件 onnx,无解压;192 维,跨域更稳 |
| vad | silero_vad | `asr-models` 下 **裸 `silero_vad.onnx`** | ~629,000 | 单文件 onnx,无解压,仅 16kHz |
| pocket | sherpa-onnx-pocket-tts-int8-2026-01-26 | `tts-models` 下同名 tar.bz2 | 98,336,520 | 解压含 `lm_flow.int8.onnx`、`lm_main.int8.onnx`、`encoder.onnx`(**fp32**)、`decoder.int8.onnx`、`text_conditioner.onnx`、`vocab.json`、`token_scores.json` |

基址常量(新增到 `model_catalog.dart`):
```dart
const String kAsrModelsReleaseBase = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models';
const String kSpeakerModelsReleaseBase = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models';
```

**默认对话三件套** `kDefaultConversationModelIds = {vad: 'silero_vad', asr: 'sherpa-onnx-paraformer-zh-2023-09-14', tts: 'vits-piper-zh_CN-xiao_ya-medium-int8'}`(TTS 用目录最小 14MB,下载快)。

**声纹模型有两个**(2026-09-29 追加)。`ModelCatalog.speakers()` 返回声明序列表,首个为默认;
`ModelCatalog.byKind(speaker)` 仍返回**声明序第一个**(ERes2Net),这是"用户从未选过时"的默认,
**不要重排已有条目顺序**。另有 `kLegacyVoiceprintModelId` 常量(= ERes2Net 的 id),专供老档案
迁移 —— 不能用 `byKind` 做迁移,否则有人重排目录就会把老档案迁进另一套嵌入空间。

---

## 三、sherpa_onnx ^1.13.6 已核实的 API 面(实施时以此为准,勿凭记忆)

包路径(本机缓存,新机器 pub get 后同):`…/pub cache/sherpa_onnx-1.13.6/lib/`。入口 `sherpa_onnx.dart` re-export 全部 `src/*`。
**铁律:所有 sherpa 类是 FFI 原生,必须在后台 isolate 中 `initBindings()`(同步)后使用;主 isolate 不得调用。音频跨 isolate 用 `TransferableTypedData` 零拷贝。**

### 3.1 TTS 克隆(PocketTTS)
```dart
// 加载
OfflineTts(OfflineTtsConfig(
  model: OfflineTtsModelConfig(
    pocket: OfflineTtsPocketModelConfig(
      lmFlow: '…/lm_flow.int8.onnx', lmMain: '…/lm_main.int8.onnx',
      encoder: '…/encoder.onnx', decoder: '…/decoder.int8.onnx',
      textConditioner: '…/text_conditioner.onnx',
      vocabJson: '…/vocab.json', tokenScoresJson: '…/token_scores.json',
      voiceEmbeddingCacheCapacity: 50),
    numThreads: 2, provider: 'cpu'),
  maxNumSenetences: 1));
// 生成(零样本克隆,无需参考文本转写)
final audio = tts.generateWithConfig(
  text: '…', config: OfflineTtsGenerationConfig(
    referenceAudio: refSamples /*Float32List [-1,1]*/,
    referenceSampleRate: refRate /*模型会重采样*/,
    numSteps: 5, extra: {'seed': 42}));
// audio.samples: Float32List, audio.sampleRate: int
tts.free();
```
- 参考音频 3–10s 清晰单声道;PocketTTS 无需参考文本(**ZipVoice 才需要**,勿混)。

### 3.2 ASR
```dart
OfflineRecognizer(OfflineRecognizerConfig(
  feat: const FeatureConfig(sampleRate: 16000, featureDim: 80),
  model: OfflineModelConfig(
    paraformer: kind == asrParaformer ? OfflineParaformerModelConfig(model: '…/model.onnx') : const OfflineParaformerModelConfig(),
    senseVoice: kind == asrSenseVoice ? OfflineSenseVoiceModelConfig(model: '…/model.onnx', language: 'auto', useInverseTextNormalization: true) : const OfflineSenseVoiceModelConfig(),
    tokens: '…/tokens.txt', numThreads: 2, provider: 'cpu'),
  decodingMethod: 'greedy_search'));
// 识别
final s = recognizer.createStream();          // OfflineStream
s.acceptWaveform(samples: Float32List, sampleRate: 16000);
recognizer.decode(s);
final r = recognizer.getResult(s);            // text / lang / emotion / event / tokens / timestamps
s.free();
```
- `OfflineModelConfig` 有 18 个模型族子配置,`tokens` 必填。

### 3.3 声纹(⚠️ 用 OnlineStream,不是 OfflineStream)
```dart
final extractor = SpeakerEmbeddingExtractor(config: SpeakerEmbeddingExtractorConfig(model: '…/….onnx', numThreads: 1, provider: 'cpu'));
final stream = extractor.createStream();       // OnlineStream
stream.acceptWaveform(samples: Float32List, sampleRate: 16000);
while (extractor.isReady(stream)) {}           // 忙等,勿并发调用该引擎
final emb = extractor.compute(stream);         // Float32List, 维数 extractor.dim(=192)
final manager = SpeakerEmbeddingManager(extractor.dim);
manager.add(name: '张三', embedding: emb);
manager.addMulti(name: '李四', embeddingList: [emb1, emb2]); // 一人多段
manager.search(embedding: emb, threshold: 0.6);  // → '' 表示未匹配
manager.verify(name: '张三', embedding: emb, threshold: 0.6); // → bool
manager.allSpeakerNames; manager.numSpeakers;
```

**多模型要点(2026-09-29 追加)**:
- `SpeakerEmbeddingExtractorConfig` 只接受**单个** model 路径 —— 没有"一个 extractor 挂多模型"这回事,
  多模型必须多个 extractor 实例(每个 ~30–40MB onnx + 运行时激活)。
- `SpeakerEmbeddingManager` **不带任何模型标识**:内部就是个 `{name → 向量}` 扁平表。两个 3D-Speaker 模型
  的嵌入**都是 192 维**,所以把一个模型的嵌入喂给另一个模型的 manager **不会报错**,只是分数变成噪音。
  务必在应用层按模型分桶,别指望 SDK 兜底。
- 因此 `SpeakerEngine` 的实现是 `modelId → extractor + manager` 的映射,**7 个方法全部要求显式传 `modelId`**,
  槽不存在就回错误,绝不回落到"当前某个"模型。worker 里 `load` 会先摘掉旧槽再 free(留着已释放对象的
  引用,一旦重建抛异常就会 use-after-free)。
- **同步顺序是硬约束**:`load` 会无条件重建该槽的 manager,所以"把档案灌进 manager"必须发生在 `load`
  **之后**(此时目标是空 manager,全量写入不会重复注册)。Dart 侧读不到 manager 内部状态,做不了增量同步。

### 3.4 VAD
```dart
final vad = VoiceActivityDetector(
  config: VadModelConfig(
    sileroVad: SileroVadModelConfig(
      model: '…/silero_vad.onnx', threshold: 0.5,
      minSilenceDuration: 0.5, minSpeechDuration: 0.25,
      windowSize: 512, maxSpeechDuration: 15.0),
    sampleRate: 16000, provider: 'cpu'),
  bufferSizeInSeconds: 60);
vad.acceptWaveform(Float32List);   // 持续喂块
if (!vad.isEmpty()) { final seg = vad.front(); /* SpeechSegment{samples, start} */ vad.pop(); }
vad.reset(); vad.flush(); vad.clear(); vad.free();
```

### 3.5 WAV(仅在需要时用,本项目主 isolate 用纯 Dart 编解码)
`readWave(filename) → WaveData{samples, sampleRate}`;`writeWave(filename, samples, sampleRate)` —— 均会碰原生,只应在 isolate 内用;主 isolate 统一用项目已有的纯 Dart `wav_encoder.dart`(写)+ 待新增 `wav_reader.dart`(读)。

### 3.6 其他可用但本计划不需要
`OnlineRecognizer`(流式 ASR)、`OfflineSpeakerDiarization`、`OfflinePunctuation`、`AudioTagging`、`SpokenLanguageIdentification`、`OfflineSpeechDenoiser`、`KeywordSpotter`、`CircularBuffer`。

---

## 四、现有代码地图(复用点,勿重复造)

- **入口**:`lib/main.dart` → `initDva` → `lib/app.dart`(`MaterialApp` + `MultiProvider` 暴露 settings/modelManager/streamingService/克隆/声纹/对话)→ `lib/ui/main_shell.dart`(底部导航 + IndexedStack,3 Tab:合成/对话/设置;跨 Tab 用回调,子页用 `Navigator.push`)。
- **DI**:`lib/app_dependencies.dart` — 手写单例 `AppDependencies`,构造可传 fakes(测试用),`init()` 幂等。新增服务在此接线 + 在 `app.dart` 的 MultiProvider 暴露。
- **状态**:flutter_dva(持久化,`lib/dva/app_dva.dart` + `app_models.dart`,命名空间 settings/downloads/history,ReduxPersistor key 前缀 `perist:`)+ provider ChangeNotifier(运行时事实源)。
- **TTS 引擎模板**:`lib/tts/tts_engine.dart` `SherpaTtsEngine` — `Isolate.spawn(_workerEntry)`、worker 内 `initBindings()`、load/generate 消息协议、`TransferableTypedData` 零拷贝。**新引擎照抄此模板**。
- **音频播放**:`lib/tts/sequential_audio_player.dart` — `AudioPlaybackQueue` 抽象 + `SequentialAudioPlayer`(拉取式 + 1 段预取 + 看门狗);`lib/tts/wav_encoder.dart` — 纯 Dart `wavBytes(Float32List, sampleRate)` 写 WAV。
- **文本管线**:`lib/tts/text_normalizer.dart`、`lib/tts/text_chunker.dart`(`TextChunker.splitWords` 用 jieba,分块策略:首句 1+4+10、后续整句≤20 词)。
- **模型管理**:`lib/data/model_catalog.dart`(目录)、`model_downloader.dart`(dio Range 续传 + 镜像 fallback)、`archive_extractor.dart`(tar.bz2 + compute + 路径消毒)、`model_manager.dart`(`downloadModel`:下载→bzip2 魔数校验→解压→resolve 完整性→≥1KB onnx 校验→dva 持久化 downloadedIds)、`model_files_resolver.dart`(`resolve(model, rootDir)` 扫目录 → `ResolvedModelPaths{modelPath,tokensPath,lexiconPath,voicesPath,dataDir,ruleFsts}`,onnx 优先 int8>fp16)、`app_paths.dart`(`modelsDir`=documents/sherpa_tts/models,`audioCacheDir`=temp/tts_audio)。
- **模型描述**:`lib/models/tts_model.dart` — `TtsModelFamily{vits,kokoro}` + `TtsModel{id,displayName,description,url,tarBz2SizeBytes,license,speakers,sampleRate,family,ruleFsts,multilingual}`(TTS 专用形状,需泛化)。
- **UI 模式**:页面 = StatefulWidget + `context.watch<T>()` + `AppLocalizations.of(context)` + 主题 token(`lib/theme/`)。`lib/ui/widgets/speaking_bubbles_view.dart`(词高亮气泡,不适配对话页);`streaming_text_view.dart`(未接线)。
- **l10n**:`l10n.yaml` arb-dir `lib/l10n`,模板 `app_zh.arb`;加键须 **zh+en 两份同步** 后 `flutter gen-l10n`;占位符需 `@key` 元数据。
- **测试**:`test/`(含 `test/support/fakes.dart` 假下载器/引擎)、`patrol_test/`。`AppDependencies` 已有可选 fakes 注入点,新参数继续用可选。
- 平台目录仅 `android/`、`ios/`(无 windows/web);宿主 Windows。Android 已配 INTERNET + cleartext。

---

## 五、架构设计(定稿)

### 5.1 模型目录泛化
- `TtsModel` 增加:`ModelKind kind`(tts/asrParaformer/asrSenseVoice/speaker/pocket/vad)、`ModelDownloadFormat downloadFormat`(tarBz2/rawFile)、`String? rawFileName`;`family/speakers/sampleRate/ruleFsts/multilingual` 改带默认值。
- `ModelFilesResolver.resolve` 按 `kind` 分支;`ResolvedModelPaths.isComplete` 按 kind:tts→model+tokens+(lexicon|dataDir);asr→model+tokens;speaker/vad→model;pocket→7 文件齐。
- pocket 的 `encoder.onnx` 是 fp32,找文件时**勿用 int8 优先规则**;`vocab.json`/`token_scores.json` 精确名匹配。
- `ModelManager.downloadModel` 按 `downloadFormat` 分支:`rawFile` 直接下载到 `modelUnpackedDir/rawFileName`,跳过 bzip2 校验与解压;完整性/体积校验照旧。`clearAllCaches` 一并清克隆音/声纹/对话缓存。
- 设置页两级:语音合成子页下拉过滤 `kind==tts`;各分类子页显示各自模型下载(非 TTS 显示种类标签)。

### 5.2 隔离区引擎(各自独立、懒加载;不合并成单 worker,避免同时压住多模型)
- 抽 `lib/tts/isolate_bridge.dart`:请求/应答(id 映射 + Completer)+ `TransferableTypedData` + 单向 fire-and-forget + worker→main 事件通道(VAD 用)。**重构 `SherpaTtsEngine` 复用**(风险低,有测试覆盖)。
- `lib/tts/vad_engine.dart`:`load(silero 路径+参数)` → `addSamples(Float32List)`(fire-and-forget)→ 事件 `onSegment(SpeechSegment)`;`reset/flush/clear`。双向流式协议。
- `lib/tts/asr_engine.dart`:`load(kind, modelPath, tokensPath, threads)` → `recognize(samples, sr) → AsrResult{text, lang, emotion}`。
- `lib/tts/speaker_engine.dart`:`load(model, threads)` → `restore(List<(name, List<emb>)>)` → `extract(samples, sr) → Float32List` → `add/addMulti/remove/search(threshold)/verify`。⚠️ 忙等提取,engine 内串行。
- `lib/tts/pocket_tts_engine.dart`:`load(7 路径, threads)` → `generate(text, refSamples, refRate, numSteps, seed) → GeneratedAudio`。参考样本在主 isolate 用 `WavReader` 解出后以 TransferableTypedData 传入。
- `lib/tts/wav_reader.dart`:纯 Dart 解 WAV(RIFF/WAVE,`fmt ` PCM=1 或 EXTENSIBLE 0xFFFE,Int16 小端 → Float32List)。

### 5.3 服务(ChangeNotifier,`AppDependencies` 接线 + `app.dart` MultiProvider)
- `lib/audio/mic_recorder.dart`:`MicRecorder` 抽象 + `RecordMicRecorder`。`startStream(16kHz pcm16bits mono)`(对话流)/ `start(path, wav, 24000)`(克隆参考)。
- `lib/asr/asr_service.dart`:`ensureLoaded()`(按 `settings.asrModelId` resolve+load)+ `recognize(samples, sr)`。
- `lib/voiceprint/voiceprint_service.dart`:`enroll(name, note?, 多段采样)`/`identify`/`remove`/`speakers`;嵌入+备注经 dva `voiceprints` 持久化,启动 restore。
- `lib/llm/llm_client.dart`+`llm_service.dart`:`DioLlmClient.streamChat({baseUrl, apiKey, model, messages, cancel})` → POST `${baseUrl}/chat/completions`,`responseType: stream`,body `{model, messages, stream:true, temperature:0.7}`;`data.stream.transform(utf8.decoder).transform(LineSplitter())` 逐行:`data: ` 前缀→jsonDecode→`choices[0].delta.content`,`[DONE]` 结束,跳过空行。**utf8.decoder 必须状态化(跨 TCP 块的多字节字符)**。
- `lib/voiceclone/voice_cloning_service.dart`:档案 `CloneVoiceProfile{id,name,referenceWavPath,sampleRate,createdAt}`;`createProfile`(录 24kHz 参考)/`deleteProfile`/`synthesize(text, profile)`;dva `clones` 持久化。
- `lib/conversation/conversation_service.dart`:编排 + `isReadyForConversation` + `downloadInitialModels(onProgress)`。

### 5.4 对话编排(说话人感知,VAD 常开)
状态机:
```dart
enum ConversationPhase { idle, listening, asr, identifying, thinking, speaking, error }
// idle--点"开始对话"(权限+启动 mic流+VAD)-->listening
// listening(VAD 常开,段出自动)-->asr-->identifying-->thinking(LLM流)-->speaking(TTS,停mic)-->listening(播完自动恢复)
// error-->idle; stop() 任意态中止; mute/unmute
```
每轮 `onVadSegment(samples)`:
1. `asr.ensureLoaded` + recognize → 空文本忽略回 listening。
2. `voiceprint.identify(samples,16000)` → speakerName(空=未知)。
3. 追加用户消息(徽章:名字/未知)到**该说话人独立历史**。
4. 构建 LLM:`系统提示 + 当前说话人:{name|未知用户} + 该说话人备注 + 该说话人多轮历史`;未知=**访客模式**(不带任何已注册记忆,通用回复,可选提示注册)。
5. 流式累积 → `TextChunker` 分块 → 按所选声音合成播放 → 播完恢复 mic。
6. 历史持久化:`Map<说话人, List<Message>>`(含 `__guest__` 桶)。

声音路由(sealed `ConversationVoice` = Model{modelId,sid} | Clone{cloneId}):模型声音走共享 `TtsEngine`;克隆走 `cloning.synthesize`。共用对话专属 `SequentialAudioPlayer`;**播放前先 `streamingService.stop()`** 防与合成页重叠。

### 5.5 一键初始化
`isReadyForConversation = vad已下载 && asr已下载 && 至少一个对话声音可用(TTS模型音已下载或存在克隆音)`。未就绪显示初始化卡片(三件套勾选 + 一键下载 + 进度 + 取消/重试);对 `kDefaultConversationModelIds` 中未下载项逐个 `ModelManager.downloadModel`(幂等);完成后自动 `setAsrModelId(paraformer)` + `setConversationVoice(model, piper)`(已有用户 TTS 选择则保留)。支持部分就绪增量。

### 5.6 UI
- `main_shell.dart`:3 个 Tab(合成 / 对话 / 设置),`IndexedStack` 常驻各页;`SynthesizePage.onNavigateToSettings`/`ConversationPage.onNavigateToSettings` → `_switchTo(2)`。
- `conversation_page.dart`:初始化卡片(未就绪)→ 状态胶囊 + 当前说话人胶囊 + 聊天气泡(用户徽章/时间戳/流式助手文本)+ 开始/停止 + 静音 + 声音选择器 + 清空历史;**Header = 左侧历史入口 + 中间音频/文本模式切换 + 右侧设置按钮**;音频模式仅显示最后一轮、文本模式显示全部并带输入框;长按删除单条。**不复用** `SpeakingBubblesView`。
- `history_page.dart`(push):单一时间线历史浏览 + 「加载更早」分页 + 长按删除单条。
- `tts_settings_page.dart`:两级(大类 ListTile → 子页),子页含各自模型下载;通用页含清理缓存。
- `clone_voices_page.dart`(push):克隆音列表 + 新建(命名→录 3–10s 参考)+ 删除。
- `voiceprint_page.dart`:说话人列表 + 注册(整页 + 圆形居中录音按钮,支持连续注册多个)+ 测试识别 + 删除。

### 5.7 设置与持久化
`TtsSettings`+`SettingsState` 新增:llmBaseUrl(`https://api.deepseek.com/v1`)、llmApiKey、llmModel(`deepseek-v4-flash`/`deepseek-v4-pro`;LLM 页内置 DeepSeek/Moonshot/智谱/通义千问服务商预设 + 自定义)、llmSystemPrompt、asrModelId、voiceprintThreshold(0.6)、vadThreshold(0.5)/vadMinSilence(0.5)/vadMaxSpeech(15)、conversationVoiceType(model|clone)/conversationModelVoiceId/conversationCloneId/conversationSid。
dva 新命名空间:`clones`、`voiceprints`(含备注);注册进 `app_dva.dart`。**会话历史改用 SQLite**(`sqflite`,`version`+`onUpgrade` 版本化迁移),见 `conversation_store.dart`。

**2026-09-29 追加的三个设置**(改法照抄 `asrModelId` 的"五处":`tts_settings.dart` 字段+getter → `load()` 恢复
→ setter 三步(写字段→`notifyListeners`→`_dispatch`)→ `app_models.dart` 的 `SettingsState` 字段 + `fromJson`
+ `toJson` + reducer):

| 字段 | 默认 | 含义 |
|---|---|---|
| `voiceprintModelId` | null | 当前声纹模型 id。**只存 id**,不保证仍存在/已下载 —— 解析与回落(取首个已下载的声纹模型)归 `VoiceprintService.currentModelId` |
| `voiceprintGateEnabled` | false | 对话声纹门禁:只有声纹库中注册过的人能触发对话 |
| `requireAuthForEnroll` | true | 注册/删除声纹、调阈值前是否要求设备认证 |

声纹档案(`voiceprints` 命名空间的 items)新增两个键:`modelId`(**老数据没有此键 → 一律归入
`kLegacyVoiceprintModelId`**)、`cloneId`(绑定的克隆音,可空)。items 是宽松 `Map<String,dynamic>`,
所以 `VoiceprintsState` 本身无需改动。

### 5.8 l10n 键(zh+en 同步,gen-l10n)
conversationTab、startConversation/stopConversation、listening/recognizing/thinking/speaking、speakerUnknown、currentSpeaker(占位符)、currentSpeakerChip(占位符)、guestMode、registerHint、speakerNoteHint、micMuted/micUnmuted、cloneVoicesTitle、recordReferenceHint、voiceprintTitle、enrollSpeaker、identifyTest、conversationSettingsTitle、llmBaseUrl/ApiKey/Model/SystemPrompt、asrModelLabel、vadThreshold/vadMinSilence、voiceprintThreshold、micPermissionDenied、模型种类标签(语音识别/声纹/克隆/VAD)、emptyAsrText、clearConversation、sendError/llmError、initModelsTitle、initModelsHint、initReady、downloadInitialModels、initProgress(占位符)、initRetry、initDone。

---

## 六、实施阶段(每阶段可验证)

- [x] **0 写入 TODO.md**:本文件即交接文档(已完成)。
- [x] **1 重构(无行为变化)**:`ModelKind`/`downloadFormat`/`rawFileName`、抽 `IsolateBridge`(含单向/事件通道)并重构 `SherpaTtsEngine`、加 `wav_reader`。验证:现有 test+patrol 全绿(58 test)。
- [x] **2 目录/下载泛化**:新增 5 项模型、resolver 按 kind、manager raw 分支、管理页标签、设置页过滤。验证:resolver 各 kind 单测、manager raw 路径单测(`test/model_kind_test.dart`)。
- [x] **3 录音基建**:`MicRecorder` 流式+落盘+权限;`wav_reader_test` 与 `wav_encoder` 往返。
- [x] **4 VAD**:`VadEngine` 流式+段回调(`TransferableTypedData` 零拷贝)。真机静音/说话切换待设备验证。
- [x] **5 ASR**:`AsrEngine`+`AsrService`+`asrModelId` 设置。
- [x] **6 声纹**:`SpeakerEngine`+`VoiceprintService`+注册/识别/删除+持久化。
- [x] **7 克隆**:`PocketTtsEngine`+`VoiceCloningService`+克隆音管理 UI。
- [x] **8 LLM**:`LlmClient/Service`+SSE 解析+`llm_client_test`(mock dio 喂 `data:`/`[DONE]`/UTF-8 跨块)。
- [x] **9 对话集成+UI**:`ConversationService`(VAD 常开+按人记忆+一键初始化)、对话页、子页、Tab 接线、l10n 重生成;widget 测试全 fake(`conversation_page_test`/`conversation_service_test`)。
- [ ] **10 验证收尾**:真机全流程;`patrol_test/conversation_test.dart` 已编写(需 Android 设备/模拟器运行);截图。
- [x] **11 声纹能力扩展(2026-09-29)**:① 双声纹模型选择(录制页可选+记住上次选择;档案按模型隔离;
  识别跨模型并集);② 对话声纹门禁(识别提到 ASR 之前;未注册者不转写/不落库/不问 LLM,只播拒绝语;
  白名单空时 fail-closed 拒绝启动);③ 按说话人切克隆音色;④ 声纹写操作的设备认证(`local_auth`)。
  详见[第九节](#九声纹能力扩展2026-09-29)。**验证状态**:`flutter test` 87 项全绿、`flutter analyze` 干净、
  Android debug APK 构建通过;**真机项未验证**(见[第八节](#八验证)末尾)。
- [x] **12 嵌入基建(v1.0.2)**:✅ 已完成。**实际走的是 `flutter_embedder` 而非 `flutter_onnxruntime`**(后者与 sherpa 的 ORT 符号版本冲突,见坑 19)。自研 WordPiece 分词器已实现并设备验证(31 测试),但**生产路径已被插件内置的 HF tokenizers 取代**;本实现保留为 **KbChunker 的 token 预算参照物**(见其文件头说明),**不要删**:`wordpiece_tokenizer.dart`(纯 Dart,读 `tokenizer.json`)+
  对照 Python 的单测;`embedding_engine.dart`(ORT 抽象 + `flutter_onnxruntime` 实现 + 批处理)+
  假实现;`ModelKind.embedding` + `rawFiles` 多文件下载 + resolver 分支 + ModelScope 源。
  **验证**:分词单测;多文件下载;同义/异义相似度自测(真机跑一次真实模型)。
- [x] **13 向量存储 + 知识库(v1.0.2)**:✅ 已完成(AppDatabase 迁移 6 测试 + KnowledgeService 14 测试):DB 升版本 + `kb_documents`/`kb_chunks`;
  `KbChunker`(**不得复用 `TextChunker`**)+ 单测;`KnowledgeService`(导入/切块/异步回填/检索);
  知识库管理页 + **检索试跑**。
- [x] **14 短期记忆(v1.0.2)**:✅ 已完成(17 测试):`session_id` 迁移 + `session_summaries`;会话分段(>30min);
  增量滚动摘要(水位线 / 失败静默 / 无 LLM 降级)。
  **验证**:断言 LLM 调用次数随轮数**线性**增长(防 O(n²) 全量重摘要回归)。
- [x] **15 长期记忆(v1.0.2)**:✅ 已完成(25 测试):`memories` 表;`MemoryService`(LLM 抽取 / ADD-UPDATE-NONE 去重 /
  检索);按说话人过滤注入;**未知说话人零抽取零注入**;「记住这条」。
- [x] **16 编排 + 接线 + UI(v1.0.2)**:✅ 已完成(编排器 21 测试 + 集成 7 测试 + 页面 7 widget 测试):`ContextAssembler`(分节/预算/裁剪优先级/防朗读标记);
  `_buildLlmMessages` **改 async**;记忆与知识库两个设置子页 + 记忆管理页;l10n 重生成。
- [ ] **17 验证收尾(v1.0.2)**:**部分完成** —— `flutter test` **290 项全绿**、`flutter analyze` 干净、debug APK 构建通过;:`flutter test` 全绿 + `flutter analyze` 干净 + debug APK 构建;
  真机全流程(见 `docs/敏捷开发/v1.0.2 APP设计内容.md` 第十三节);README 更新(新依赖、
  新模型源、隐私边界)。**未验证项**:ModelScope 应用内下载稳定性、真机推理速度、阈值实测校准。

## 七、风险与坑(实施必读)

1. **常开麦克风**:TTS 播报期间必须停 mic 防自听反馈(播完自动恢复);前台应用,不做后台常驻;Android 会显示麦克风指示。
2. **Pocket 解压后体积大**(压缩 98MB → 数百 MB);各引擎独立懒加载,避免同时常驻。克隆引擎仅在选择克隆音时 load。
3. **声纹/VAD 是裸 onnx**:`ModelManager` 的 rawFile 分支必须跳过 bzip2 魔数校验与解压,勿对 `silero_vad.onnx`/eres2net.onnx 走解压路径。
4. **`SpeakerEmbeddingExtractor` 用 `OnlineStream`**(不是 `OfflineStream`,勿照抄 ASR worker);`while(isReady){})` 忙等会阻塞 worker 事件循环 → bridge 必须串行,勿并发调用 speaker 引擎。
5. **SSE 解析**:多字节 UTF-8 跨 TCP 块必须状态化 `utf8.decoder`;处理 `data: [DONE]`、空 keepalive `data:` 行、provider 错误 payload;401/空 key 转友好错误。
6. **DeepSeek 模型 id**:`deepseek-v4-flash` / `deepseek-v4-pro`,存于设置 `llmModel` 字段;baseUrl 默认 `https://api.deepseek.com/v1`(OpenAI 兼容),LLM 页内置 DeepSeek/Moonshot/智谱/通义千问服务商预设 + 自定义。
7. **l10n**:键必须同时写 `app_zh.arb` 和 `app_en.arb`,否则 gen 失败;占位符需 `@key` 元数据。
8. **现有测试**:`AppDependencies` 只加可选参数;`TtsModel`/`ResolvedModelPaths` 新字段带默认值 → 现有构造不破坏。实施前 grep 是否有断言 `ModelCatalog.all.length` 或"全部 multi-speaker"的测试。
9. **IndexedStack 保持各 Tab 存活**:任何 sherpa isolate 不得在对话页 build 时 spawn(引擎全部懒加载);对话播报前 `streamingService.stop()`。
10. **API key 明文存 SharedPreferences**(flutter_dva)——demo 可接受,README 注明。
11. PocketTTS 零样本无需参考文本;参考音频 3–10s、单声道、float[-1,1],模型自会重采样到其格式。
12. `record` 包权限用 `hasPermission()`/`requestPermission()`;Android minSdk ≥23。

**2026-09-29 追加(声纹扩展相关,全部踩过或有明确理由)**:

13. **两个声纹模型的嵌入不可互换,且维度相同(都是 192)→ 混用不会报错**。`SpeakerEmbeddingManager`
    内部只是个 `{name → 向量}` 扁平表,不带模型标识。把 A 模型的嵌入喂进 B 模型的 manager,识别会返回
    结果但分数是噪音 —— 这是**静默错误**,最难查。所以:档案必须按模型分桶;引擎的每个方法都必须显式
    传 `modelId`;worker 里槽不存在要**报错**而不是回落到某个默认模型。
14. **`load` 之后才能同步档案**。worker 的 `load` 无条件重建该槽的 manager,所以"灌档案"必须发生在其后
    (此时目标是空 manager,全量写入不会重复注册)。反过来,只要没 load 就不能同步 —— `addMulti` 的幂等性
    完全依赖这个顺序。Dart 侧读不到 manager 内部状态,做不了增量同步,只能每次 load 后全量重灌。
15. **`local_auth` 在 Android 要求宿主 Activity 是 `FlutterFragmentActivity`**。继承 `FlutterActivity` 时
    `authenticate()` 直接抛 `PlatformException`,功能静默失效(被 `isSupported()` 判为不可用 →
    提示"设备认证不可用")。另需 `USE_BIOMETRIC` 权限;iOS 需 `NSFaceIDUsageDescription`。
    Windows 走 Windows Hello,**桌面端可用性未验证**。
16. **门禁/认证的判据要与实际语义一致**。踩过的坑:门禁 fail-closed 一开始用"当前模型的档案数",
    但识别是**跨模型并集**,于是只注册在另一个模型下的人(明明认得出)会被拒绝启动。改用 `hasAnyProfiles`。
    同理 `profileOf` 要跨桶兜底,否则"认出了人却不注入备注"。**改动识别语义时,所有依赖它的判据都要跟着查一遍。**
17. **"弹了认证但不拦写入"等于没守**。阈值滑块最初只在 `onChangeStart` 弹认证,`onChanged` 照样落值 ——
    用户取消认证也能改。修正:`onChanged` 里同步检查 `appLock.isUnlocked`,没通过就不写(滑块弹回原位)。
    **凡是守卫,都要问一句"没通过时到底拦住了什么"。**

## 八、验证

- **单元**:wav 往返;resolver 各 kind;pocket 7 文件形状;speaker/vad 裸 onnx;manager raw 分支;vad 流式段回调;asr/voiceprint/cloning service(假引擎);llm_client(mock dio SSE);conversation_service(全假:VAD 段驱动状态迁移/按说话人历史隔离与恢复/未知说话人访客模式/提示词注入身份与备注/声音路由/错误路径/初始化)。
- **Widget**:对话页(初始化卡片四态、麦按钮状态、说话人徽章、流式气泡、静音开关)。
- **Patrol**:`app_smoke_test` 不受 Tab 增加影响 + 新增 `conversation_test.dart`(假 MicRecorder 流式吐 PCM,假 VAD/ASR/LLM/引擎,复用 `test/support/fakes.dart` 与 `buildPatrolTestDeps` 模式)。
- **真机全流程**:① 清缓存首进对话页→一键下载三件套→自动配置→开始对话;② 注册张三/李四(各填备注)→分别对话:回复个性化(备注生效、直呼姓名)、历史互不串扰;③ 未注册第三人→访客模式,通用回复、不泄已注册记忆;④ 说话→静音自动转写→DeepSeek 流式→语音回复→播完自动恢复聆听;⑤ 选克隆音(录 5s 参考)→以克隆音色回复;⑥ 播报时静音、中途 stop、初始化中途取消/重试;⑦ 杀进程重启:克隆/声纹(含备注)/按说话人历史持久、初始化不重复提示。

### 2026-09-29 追加的验证

**已自动验证(本机跑过)**:
- `flutter test` **87 项全绿**(原 71 项 + 新增 16 项)。新增用例分布:
  - `test/voiceprint_models_test.dart`(9 项):目录声明序与 `byKind` 默认不变、档案按模型隔离(同名两模型各存各的)、
    识别跨模型并集、异名冲突以当前模型为准、只用有档案的模型加载(不为空桶 spawn 引擎)、切换后重同步与
    `ensureLoaded` 幂等(`loadCalls` 序列)、无模型时 `currentModelId == null` / 注册抛错、设置指向已删模型时回落、
    编解码往返 + 老数据迁到 `kLegacyVoiceprintModelId`、绑定克隆音与重录保留绑定。
  - `test/conversation_service_test.dart`(3 项):门禁 fail-closed 拒绝启动、未注册者不跑 ASR/不落库/不问 LLM
    (断言 `asr.recognizeCalls == 0`)、白名单内的人正常对话。
  - `test/enroll_page_test.dart`(3 项):无模型时显示提示不出下拉、下拉初值 = 上次选择且切换写回设置、
    **键盘弹出(400×520 + 320px insets)不溢出**。
  - `test/persistence_test.dart`:三个新设置往返 + 默认值(门禁默认关、认证保护默认开);声纹档案的
    `modelId`/`cloneId` 往返。
  - `test/model_kind_test.dart`:CAMPPlus 走裸 onnx 分支;`test/support/fakes.dart`:`FakeSpeakerEngine` 改为
    按模型分桶记录、新增 `FakeAppLockService`、`FakeAsrEngine.recognizeCalls`。
- `flutter analyze lib test patrol_test`:**无问题**。
- `flutter build apk --debug`:**成功**(验证 `FlutterFragmentActivity` 与 `USE_BIOMETRIC` 改动可编译)。

**仍未验证(需真机 / 需联网,本机做不了)**:
1. **campplus 在 app 内实际下载**:URL 与体积已用 curl 核实(`3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx`,
   28,281,138 字节,直连 302→200),但"设置页点下载 → ready"这条路径没跑过。
2. **设备认证真机行为**:Android 指纹/人脸、Windows Hello 可用与不可用两种情况各走一遍,确认不可用时
   弹说明而非崩溃。**Windows 端最可能出意外**(`local_auth_windows`)。
3. **门禁端到端**:带真麦克风 + 真 ASR:开启门禁 → 本人说话有回应、他人说话只播拒绝语且**不产生 LLM 请求**。
4. **跨重启恢复两个桶**:两个模型各注册一个人 → 杀进程 → 重开 → 管理页能看到两批人且互不串。
   (`ensureStoreLoaded` 的 dva 分支在单测里走不到 —— 测试中 `dvaStore()` 恒为 null。)
5. **按人切音**:给两个说话人绑不同克隆音,确认回话音色随说话人切换。
6. 对话门禁的**拒绝语实际播报效果**(文案、停麦时机、播完自动恢复聆听)。

## 九、声纹能力扩展(2026-09-29)

原第一~九阶段把声纹做成了**只读旁路**:每段语音识别出说话人后只把名字与备注注入 LLM 上下文,
不拒绝、不分流、不换声音;而且声纹模型写死为 `byKind(speaker)` 取到的第一个,用户不可选。
本轮补齐四件事。

### 9.1 双声纹模型选择

- 目录新增 CAMPPlus(见 2.2 表)。**顺序必须保持 ERes2Net 在前**(`byKind` 取声明序首个 = 未选过时的默认)。
- 录制页(`enroll_page.dart`)下拉可选,**选完写回设置 = "记住上次选择"**。
- 档案按模型分桶:`VoiceprintService` 内部是 `Map<modelId, Map<name, VoiceprintProfile>>`(嵌套 Map 而非
  复合键 —— 键空间天然分层,正确性不依赖对用户输入的名字做任何清洗)。
- **识别是跨模型并集**:对每个"有档案且已下载"的模型各跑一遍(`extract` + `search`),因为每个模型有自己的
  嵌入空间、同一个向量不能跨模型比较。多个模型匹配到**不同名字**时以当前模型为准,同名字直接返回。
  好处是"在哪个模型下注册都认得出";代价是识别时可能加载两个 onnx(只为有档案的模型加载,没有档案的不碰)。
- **`profileOf` 跨桶兜底**:因为识别是并集,若 `profileOf` 只查当前模型桶,就会出现"认出了人却不注入备注"。
- 两个守卫语义分开:`_storeLoaded`(只守"从 dva 读一次")与 `_readyModelIds`(守"引擎里有该模型槽且档案已同步")。
- 编解码抽成纯静态函数 `decodeItems` / `encodeProfiles` —— 测试里 `dvaStore()` 恒为 null,不抽出来这条
  恢复路径就零覆盖(含老数据迁移)。
- **顺带修掉一个既有 bug**:原 `_restoreFromStore` 挂在 `ensureLoaded` 里,而后者要先有已下载的模型,导致
  冷启动时声纹管理页显示"尚未注册"(且删掉模型后档案永远读不出来)。现在拆出 `ensureStoreLoaded()`,
  在 `AppDependencies.init` 里**只读档案、不加载 onnx**。

### 9.2 对话声纹门禁

- `_handleSegment` 里把**声纹识别提到 ASR 之前**:identify 只需要音频段、不需要文本,提前后拒绝时
  **根本不触发 ASR + LLM** —— 门禁从"多花算力"变成"省算力"。
- 未通过:播本地合成的拒绝语(**不走 LLM**),落回 listening,**不落库**(未知说话人的语音不写 SQLite)。
  复用 `_speakReply`,它已处理停麦防自听反馈与播完恢复麦。
- **fail-closed**:门禁开着但一个声纹都没注册时,`start()` 拒绝启动并给出可见原因(状态栏胶囊显示
  `voiceprintGateNoProfiles`)。判据是 `hasAnyProfiles`(**任何模型下**注册过)而不是 `hasProfiles`
  (当前模型桶)—— 因为识别是跨模型并集,用当前模型判断会把明明能通过的人挡在门外。
- 拒绝语文案由 UI 按当前语言注入 `service.voiceprintGateReply`(服务层拿不到 l10n)。

### 9.3 按说话人切克隆音色

`VoiceprintProfile.cloneId` + `VoiceprintService.bindClone`。`_currentVoice()` 先查说话人绑定的克隆音
(绑定存在且克隆音还在才生效),没有才回落到全局设置。`_synthesizeChunk` 已按 `_currentVoice()` 的结果分派,
无需改动。绑定入口在声纹管理页(每个档案一个按钮,弹克隆音列表)。不设全局开关:绑定本身就是显式 opt-in。

### 9.4 声纹写操作的设备认证

- 依赖 `local_auth ^3.0.2`。抽象成可注入的 `AppLockService`(`lib/utils/app_lock_service.dart`),
  真实实现 `LocalAuthAppLockService`,测试用 `FakeAppLockService`。
- `authenticate` 用 `biometricOnly: false`(允许系统 PIN/密码兜底,否则没录指纹的设备直接锁死);
  `ensureUnlocked` 带**内存解锁会话**(默认 5 分钟)—— 必须有,否则连续注册多个人要反复按指纹,
  滑块之类的高频操作更是不可用。
- 守卫点:录入保存、删除档案、声纹阈值滑块。统一走 `lib/pages/voiceprint/utils/voiceprint_auth.dart`
  的 `ensureVoiceprintAuth`。
- **滑块是真守不是装饰**:`onChangeStart` 弹认证,`onChanged` 里同步检查 `appLock.isUnlocked`,
  没通过就不落值(滑块弹回原位)。只弹认证不拦写入等于没守。
- 设备认证不可用(`!isSupported`):弹说明对话框,由用户**显式**关闭 `requireAuthForEnroll` 才继续,
  绝不静默放行。`MissingPluginException` / `PlatformException` 一律归入"不可用",不能冒泡成崩溃。
- 平台配置(缺一不可,已就位):Android `USE_BIOMETRIC` 权限 + `MainActivity` 继承
  `FlutterFragmentActivity`;iOS `NSFaceIDUsageDescription`。

### 9.5 ⚠️ 这套东西不是安全边界(必须写进代码注释与 README)

对话门禁与录入认证都是**便利性/礼貌性防护**。四条理由:① 3 秒录音即可重放通过,而本应用的采样恰好
就是硬编码 3 秒(`record_samples.dart`);② 本应用自带 PocketTTS 零样本克隆,拿到样本即可合成授权人声音;
③ 判定是 192 维嵌入的余弦阈值,是同人/异人权衡点而非密码学的对错;④ 嵌入以**明文 JSON** 落盘
(dva ReduxPersistor,非 Keystore/Keychain),本机读出即可注入他人嵌入冒充。

**真正的信任根是录入**(谁能录入谁就能过门),所以认证重点放在录入侧。**未做(Phase 2)**:把嵌入搬进
`flutter_secure_storage` —— dva 是整库 JSON 持久化,要单独搬 `voiceprints` 桶,牵扯 `_persist` /
`ensureStoreLoaded`,另开工单。

---

## 十、本版收口追加(2026-09-29 同批次)

用户在验收时提出的四点,已一并实现:

### 10.1 就绪判定按模式区分

早期两种模式共用一个 `isReadyForConversation`(三件套就绪),于是只用 LLM 的**文本模式也必须先下
~250MB 本地模型**。现在 `ConversationService` 多两个谓词:

```dart
bool get isReadyForTextMode  => _settings.isLlmConfigured;              // 零本地模型
bool get isReadyForAudioMode => isReadyForConversation && _settings.isLlmConfigured;
```

- **`isReadyForConversation` 语义不变**(仅模型维度),`start()` 也**不加** LLM 前置检查 ——
  保留"未配 Key 则起得来、命中 LLM 才报错"的运行时路径(有测试覆盖)。
- `ConversationPage` **必须同时 `watch<TtsSettings>()`**:改 Key 走设置的 `notifyListeners()`,
  不触发服务通知,不 watch 就卡在初始化卡片上出不去。
- `InitCard` 改为按模式与缺口渲染:文本模式只给"配置大模型"(不给下载入口);音频模式在
  "模型已齐但缺大模型"时显示"还差配置大模型",**不再显示全打勾、无前进路径的下载列表**。

### 10.2 大模型配置列表化

单组 `baseUrl/apiKey/model` 换服务商就覆盖上一家 Key。现在:

- 新增 `lib/data/models/llm_config.dart`:`LlmConfig{id,name,baseUrl,apiKey,model,systemPrompt}`
  + `llmPresets` + `resolveLlmConfigs`(纯函数)+ `providerOfBaseUrl`。
  **服务商不单独存字段**(由 baseUrl 反查),避免第二处可能漂移的状态。
- `SettingsState` 新增 `List<Map<String,dynamic>> llmConfigs` + `activeLlmConfigId`,
  单个 `setLlmConfigs` reducer 同时写列表与启用项,并把启用项**镜像**进旧的四个扁平字段
  (唯一写点;镜像让降级回旧版本仍能读到配置)。旧扁平字段从此只作**迁移读取源**。
- **兼容 getter 是关键取舍**:`TtsSettings.llmBaseUrl/llmApiKey/llmModel/llmSystemPrompt`
  保持同名、改为解析"启用配置" → `llm_client.dart` / `llm_service.dart` / `conversation_service.dart`
  / `app_dependencies.dart` **全部零改动**,11 处测试的 `setLlmApiKey('k')` 也无需改写。
  兼容 setter 同理:写启用项,无配置则先种子化。
- **恒有 ≥1 条配置**:`load()` 与"无配置时的写入"两处兜底;只剩一条时禁用删除。
- 迁移判据不只看 API Key —— 只改过地址还没填 Key 的用户同样算"配过"。
- UI:`llm_section.dart` 改为列表页 + 新的 `llm_config_edit_page.dart`(草稿式表单,保存才写)。
- **`TextFieldSetting` 补了 `didUpdateWidget`**:否则切服务商自动填充的地址/模型在输入框里
  **看不见**(controller 只在 initState 建过)。守卫**两个条件都要**:
  `widget.initial != oldWidget.initial && widget.initial != _controller.text` ——
  只比后者的话,用户打字期间父级任何一次 rebuild 都会把内容覆盖回旧值。顺带加了 `minLines`。

### 10.3 合成页初始化卡片

`lib/pages/synthesize/sections/synth_init_card.dart`(新)。没模型时不再只靠"点发送后弹 SnackBar",
而是显示卡片:区分"未选过模型"(推荐 `kDefaultSynthModelId`)与"选了没下载",一键下载并启用,
另有"更多模型"跳设置。**不内嵌完整 TTS 列表**(最大 349MB 的 Kokoro 不适合当初始化默认项)。

> ⚠️ **两条硬约束**(踩过,`IndexedStack` 会同时构建三个 Tab,该卡片与对话页卡片同处一棵树):
> 1. 主按钮 key **必须避开 `initDownloadButton`**,否则对话页的 `findsOneWidget/findsNothing` 断言挂。
> 2. 静置态**不能有不确定进度条**(`value: null`),否则 `pumpAndSettle` 永不收敛。

### 10.4 空状态提示文案

`speaking_bubbles_view.dart` 的空状态原本是**无 style 的裸 `Text`**(继承全强度 `inkPrimary`)。
改为 `AppText.tertiary(AppText.caption)` + `textAlign: center` + 32 水平内边距,
并在 ARB 的子句间插 `\n` 保证两行。

### 10.5 本批次新增测试(87 → 112)

`test/llm_config_test.dart`(12)、`test/llm_section_test.dart`(5)、`test/synthesize_init_test.dart`(3)、
`conversation_service_test.dart` +3、`conversation_page_test.dart` +1(文本模式门)、
`persistence_test.dart` 改写大模型断言(原来那条**空转通过** —— `llmBaseUrl` 的默认值恰好等于断言值)
并新增旧字段往返。

---

## 十一、v1.0.2 规划(2026-09-29 追加)

**完整设计见 `docs/敏捷开发/v1.0.2 APP设计内容.md`**(自足,含流水线图、SQL 建表、提示词格式、
UI/l10n、验证清单)。本节只记**决策、已核实事实与坑**,便于在本文件内一站式交接。

### 11.1 目标与边界

给应用补上**记忆与知识**层。三块:本地知识库(KB)、本地短期记忆(STM)、本地长期记忆(LTM)。

- **向量计算完全离线**(本地 ONNX 嵌入模型);**记忆抽取与回答生成用在线 LLM**。
  即"**检索离线、提炼与生成在线**" —— LLM 仍是唯一联网组件,该定位不变。
- 三者语义**不可互相替代**,必须分开存、分开删:
  - **STM** = 当前会话工作记忆 = 最近 N 轮原文(v1.0.1 已有)+ **更早轮次的滚动增量摘要**(新增)。
    **不是新的消息存储** —— 原文只存 `conversation_messages`,STM 是它的压缩视图(摘要 + 水位线)。
  - **LTM** = **关于某个人的、跨会话成立的短事实**,挂**说话人**(与 v1.0.1 声纹能力咬合)。
  - **KB** = **用户主动导入的文档**。与 LTM 的本质差别:KB 是用户显式给的资料,LTM 是从对话推断的。

### 11.2 新增依赖与模型(全部已核实)

| 组件 | 选型 | 已核实事实 |
|---|---|---|
| ONNX 运行时 | `flutter_onnxruntime` **^1.8.5** | ORT 1.23.0;≥1.5.1 满足 16KB 页面对齐;2026 年持续维护 |
| 嵌入模型 | `Xenova/bge-small-zh-v1.5` → `onnx/model_quantized.onnx` | **24,010,842 B**;512 维;int8 |
| 文件导入 | `file_picker` **^13.1.0** | 走 Android SAF,免存储权限 |

**下载源用 ModelScope(不用 hf-mirror)**:

| 源 | 实测 |
|---|---|
| `huggingface.co` 直连 | ❌ **无响应(被墙)** |
| `hf-mirror.com` | ✅ 302→200 |
| **`modelscope.cn`** | ✅ **推荐**,4 文件全 `200` |

基址 `https://modelscope.cn/models/Xenova/bge-small-zh-v1.5/resolve/master`,四文件:
`onnx/model_quantized.onnx` = 24,010,842 · `tokenizer.json` = 439,125 · `vocab.txt` = 109,540 · `config.json` = 716。

**已实测的下载行为**(决定能否复用现有下载器):
- `Range: bytes=0-1023` → **`HTTP/1.1 206 Partial Content`** ⇒ **断点续传可用**,
  现有 `HttpModelDownloader` 的 dio Range 续传逻辑**零改动复用**。
- 前 16 字节 = `\b\006\022\r o n n x . q u a n t i z`(ONNX protobuf,`producer_name="onnx.quantize"`)
  ⇒ **真模型文件,非拦截页**。这类校验照抄现有 bzip2 魔数校验的做法。

**排除项**:`onnxruntime`(gtbluesky,最新 1.4.1)—— 有**未修复的 Android `libonnxruntime.so`
dlopen 失败**(issue #28,2024-12 报出至 2025-11 未解)与 `MergeNativeLibsTask` 重复库报错。**勿选。**

### 11.3 向量化流水线(全部参数来自仓库配置文件,非记忆)

```
文本 → WordPiece 分词 → input_ids/attention_mask/token_type_ids([1,L] int64)
     → OrtSession.run → last_hidden_state [1,L,512]
     → 取 [CLS](token 0)的 512 维                    ← CLS 池化
     → L2 归一化(单位向量 ⇒ 余弦 = 点积)
     → Float32List(512) ⇒ Uint8List(2048 B) 存 SQLite BLOB
```

| 参数 | 值 | 来源 |
|---|---|---|
| 嵌入维度 | **512** | `config.json` `hidden_size` / `1_Pooling` `word_embedding_dimension` |
| 最大长度 | **512**(含 `[CLS]`/`[SEP]` ⇒ 内容 ≤ **510**) | `config.json` `max_position_embeddings` |
| 池化 | **`pooling_mode_cls_token: true`**,`mean_tokens: false` | `1_Pooling/config.json` |
| 中文切分 | `tokenize_chinese_chars: true`(按字切) | `tokenizer_config.json` |
| 词表 | 21128(BERT-small,4 层/8 头) | `config.json` |

**分词器自实现**(纯 Dart 读 `tokenizer.json`):BasicTokenizer(CJK 逐字切/标点切/空白切)+
WordPiece(贪心最长匹配,续接前缀 `##`,未命中 `[UNK]`)。**验收:分词结果与 Python `transformers`
对照**(取 5–10 条样本固化进单测)。

**必须批处理**:`[B, L]` 一次前向跑 8–16 块。逐块调用 ⇒ 1000 块 = 1000 次前向,
单块 512 token 在手机上约 50–200ms,**合计 1–3 分钟**。

### 11.4 存储与检索

**沿用同一个数据库文件** `sherpa_tts/conversation.db`,`SqliteConversationStore` 的 `_version`
提升 + 在 `_migrations` 追加建表(该文件已有版本化迁移骨架,新增表不动老数据)。

```sql
kb_documents(id, title, source_path, imported_at, char_count, chunk_count, embedded_count)
kb_chunks(id, doc_id, seq, text, embedding BLOB NULL, dim, model_id)
  INDEX idx_kb_chunks_pending ON kb_chunks(embedding) WHERE embedding IS NULL
memories(id, speaker, kind, content, embedding BLOB, dim, model_id,
         confidence, source_msg_id, created_at, updated_at)
session_summaries(session_id PK, summary, summarized_up_to_id, updated_at)
```

- **`embedding` 可空是核心**:支持"导入瞬时完成、嵌入后台回填"(11.5)。
- **`model_id` 不可省**:换模型后旧向量与新向量**不可比且维度相同、不报错**(与坑 13 同构)。
  检索只取 `model_id = 当前模型`;不匹配按"未嵌入"处理并提示重建索引。
- `conversation_messages` **增 `session_id` 列**(`ALTER TABLE ADD COLUMN`,老数据回填当前 session)。
- **不用 SQLite FTS5**:Android 系统 SQLite 在 **minSdk 23 不保证 FTS5**;且本项目检索是向量不是关键词。

**检索 = 内存暴力点积**(单位向量 ⇒ 余弦 = 点积):

| 规模 | 内存 | 单查询乘加 | 量级 |
|---|---|---|---|
| 1,000 块 | 2 MB | 51 万 | 亚毫秒 |
| 10,000 块 | 20 MB | 512 万 | 数毫秒 |
| 50,000 块 | 100 MB | 2,560 万 | 数十毫秒 |

**1 万块以内暴力检索延迟不可感知**;ANN(HNSW/IVF)在此规模只带来构建成本、内存开销与
"近似召回漏掉正确块"的新失败模式。**不引 sqlite-vec / 向量数据库**。
**规模上限:~5 万块之后再考虑 ANN 或按文档分页。**

### 11.5 关键取舍

1. **异步嵌入回填**:导入**只同步落文本**(`embedding = NULL`),用户立刻看到文档;
   嵌入在后台批量回填。检索只取已嵌入的块 ⇒ 未索引完的文档**部分可检索**,列表显示
   "索引中 3/12"。任务可取消、可断点续。避免让用户对着转圈对话框等 1–3 分钟。
2. **切块必须新写 `KbChunker`,不得复用 `TextChunker`**。后者服务 TTS(首句 `1+4+10` 词、
   后续整句 ≤20 词),目标是朗读自然;对检索是错的语义边界(块太碎 ⇒ 语义不完整、命中率低)。
   `KbChunker`:标题/空行段落优先 → 超长按句末标点二次切 → 相邻**重叠 ~15%** → 硬上限 **510 token**。
3. **STM 增量摘要**:`session_id` 在 `start()` 时若距上次活动 **> 30 分钟**则新建;
   未摘要消息 ≥ 10 条时取最老 10 条 **+ 已有摘要** → 新摘要 → 更新水位线。
   **必须增量** —— 全量重摘要是 O(n²) token 消耗。
4. **LTM 抽取每 4 轮批量一次**(单轮上下文不足以推出稳定事实),输入"最近若干轮 +
   该说话人已有记忆 top-k",输出 `[{op: ADD|UPDATE|NONE, id?, kind, content}]`。
   **不去重会无限膨胀且自相矛盾**(三个月后会有五条"用户在减肥"与互相冲突的饮食偏好)。
5. **未知说话人零抽取零注入**(硬约束)。与 v1.0.1 访客模式一致;否则把张三的记忆注入
   给陌生人 = **跨人信息泄漏**,而且听起来极自然、极难察觉。判据看**当前识别结果**,
   不看"库里有谁的记忆"。
6. **`ContextAssembler` 预算编排**(本版核心,`_buildLlmMessages` **改 async**):

```
总预算 B(默认 4000 token 估算)
├─ ① 系统提示 / ② 身份+备注      固定,不裁剪
├─ ③ 知识库 top-k                ≤ 1200
├─ ④ 长期记忆 top-k              ≤ 600
├─ ⑤ 会话摘要(STM)              ≤ 500
└─ ⑥ 最近 N 轮原文               剩余,且至少保留最近 4 轮
裁剪顺序(先砍离当下最远的):③ KB → ④ LTM → ⑤ 摘要 → ⑥ 最近 N 轮
```
   token 用启发式估算(中文 ~1 字/token,`est ≈ chars / 1.6`)+ **预留 20% 余量**;
   不为此引 tokenizer 依赖 —— **预算只需"不超太多",不需精确**(要写进代码注释)。

7. **检索失败一律降级为不注入**,绝不打断对话(同门禁"不卡死对话"原则)。

### 11.6 新增设置(照抄 `asrModelId` 的"五处"模式)

`memoryEnabled`(true)、`memoryExtractInterval`(4)、`memoryTopK`(6)、`kbEnabled`(true)、
`kbTopK`(4)、`kbScoreThreshold`(**0.45,猜测值,须实测校准**)、`embeddingModelId`(null)、
`contextBudgetTokens`(4000)。

### 11.7 追加坑位(18–39)

**依赖与构建**

18. **别选错 onnxruntime 包**:gtbluesky `onnxruntime` 1.4.1 有未修复的 Android dlopen 失败;
    用 `flutter_onnxruntime` ≥1.8.5。
19. ☠️ **`sherpa_onnx` 与 `flutter_onnxruntime` 在同一 APK 内【无法共存】—— 本地 ONNX 文本嵌入方案已证伪**
    这一条改写过**两次**,前两版都是错的,此处只保留已实测证实、可复现的结论。
    **过程留痕(避免后人重走)**:① 先误判为"`.so` 名不同、静态链接 ⇒ 共存安全";
    ② 构建失败后误判为"选较新的那份即可"(`pickFirsts`),构建虽通过,
    **但 App 一启动插件注册就失败**:
    ```
    dlopen failed: cannot locate symbol "OrtGetApiBase" referenced by
      ".../base.apk!/lib/x86_64/libonnxruntime4j_jni.so"
      at ai.onnxruntime.OnnxRuntime.load → FlutterOnnxruntimePlugin.onAttachedToEngine
    ```
    **真正根因:符号版本化(ELF symbol versioning),不是符号缺失。**
    两份 ORT 都**导出**了 `OrtGetApiBase`(`.dynsym` 里 DEFINED/GLOBAL),所以
    `grep`/`nm` 一类的检查**看起来一切正常** —— 这也是前两次误判的来源。
    它们真正的差别在版本节点:

    | 制品 | 定义的版本节点 | 需要的版本节点 |
    |---|---|---|
    | 插件 ORT `onnxruntime-android` 1.23.0 | `VERS_1.23.0` | — |
    | sherpa 自带 ORT 1.27.1 | `VERS_1.27.1` | — |
    | 插件 `libonnxruntime4j_jni.so`(消费方) | — | **`libonnxruntime.so@VERS_1.23.0`** |
    | sherpa `libsherpa-onnx-c-api.so`(消费方) | — | **`libonnxruntime.so@VERS_1.27.1`** |

    两侧 soname 都是 `libonnxruntime.so` ⇒ APK 里**只能存在一个文件**;
    而每个消费方都把符号绑到**以自己 ORT 版本命名**的版本节点上
    ⇒ 任一份都**只能满足一个消费方**。`pickFirsts` / 选版本 / Gradle 排除**统统无解**。
    Android 链接器的报错**只打印基础符号名**(`OrtGetApiBase`)、**不打印版本节点**,
    这是本条最坑的地方。

    **⇒ 结论:`flutter_onnxruntime` 已从 `pubspec.yaml` 移除,`pickFirsts` 已撤销。**
    本地检索改用**纯 Dart BM25**(零原生依赖、零模型、完全离线)。
    **凡"想再引入一个 ONNX 运行时"的念头,先回来看这一条。**
    另:早期版本还有一条与之无关的坑(gtbluesky `onnxruntime` 1.4.1 的 Android
    dlopen 失败,issue #28),所以那个包同样不能用。
    **体积估算修正**:原"~15–25MB/ABI 叠加"不成立 —— 因为根本不可能两份共存。

    **附:`flutter_embedder` 也已评估(2026-09-29 实测),结论是"有机会但代价高,暂不采用"。**
    它与上面那个包的关键差异是**可能绕开冲突**:
    `rust/Cargo.toml` 里 `ort = { version = "2.0.0-rc.11", features = ["load-dynamic"] }`
    —— ORT 由 Rust 在**运行时 `dlopen` 按名字加载**,不走 AAR 的 `libonnxruntime4j_jni.so`。
    因此理论上可以**不引入 `onnxruntime-android`,直接指向 sherpa 已在 APK 里的那份
    ORT 1.27.1**(ORT C API 向后兼容:按 v23 请求由 1.27 满足;`dlsym` 取的是默认版本符号)。
    功能上也对得上:内置 HF `tokenizers`(可取代自研 WordPiece),且明确支持
    **BGE + CLS 池化**。
    **但实测两点卡住**:
    ① **内置 cargokit 在本项目工具链上编不过** —— `cargokit/gradle/plugin.gradle` 用了
       **Gradle 9 已移除**的 `project.exec()`,报
       `Could not find method exec() for arguments [...] on project ':flutter_embedder'`;
       本项目是 **Gradle 9.1.0 + AGP 9.0.1**(降 Gradle 不现实,AGP 9 要求 Gradle 9)。
       要用它必须**把插件 vendor 成 path 依赖并改这段脚本**(换成 Gradle 9 的
       `ExecOperations` / `providers.exec`)。
    ② **需要 Rust 工具链**(cargokit 从源码编译 Rust cdylib;本机无
       `cargo`/`rustc`/`rustup`/`cargo-ndk`)。`cargokit_options.yaml` 里有
       `use_precompiled_binaries: true`,但**未验证**是否真发布了各 ABI 的预编译产物。
    ③ 且 0.1.7、最后发布 2026-01-20(已 8 个月)、0.1.x 早期版本。
    **⇒ 当时结论 = 先修 cargokit + 装 Rust + 再赌 ort crate 与 sherpa 那份 ORT 的兼容性。**

    ✅ **2026-09-29:这条路已走通并在模拟器上实测通过**,结论修正为【采用】。见下方 19.1。

### 19.1 `flutter_embedder` 方案已实测通过(2026-09-29)

**核心赌注成立**:`ort` crate 的 `load-dynamic` **能加载 sherpa 已打进 APK 的那份
`libonnxruntime.so`(1.27.1)**,因此**不需要引入 `onnxruntime-android`**,
同 soname + 符号版本节点的死结被绕开。设备实测(Android 17 / x86_64 模拟器):

| 项 | 结果 |
|---|---|
| `initFlutterEmbedder(path: 'libonnxruntime.so')` | ✅ **33ms** |
| 建会话 + 首次推理 | ✅ 120ms |
| 维度 / L2 归一化 / 确定性 | ✅ 512 维、单位向量、可重复 |
| **语义判别力** | ✅ 同义 **0.75–0.81** vs 异义 **0.24–0.27** |
| 性能(372 字符块) | n=1 128ms/条;n=16 均摊 **80.5ms/条**(模拟器,真机更快) |
| 超过 512 token 的输入 | ✅ **响亮失败**(不静默截断) |

⇒ 1000 块索引约 80s(模拟器)/ 20–40s(真机),配合**异步 + 可中断 + 断点续**的后台回填可接受。

**随之而来的新坑位(46 起)**

46. **嵌入是同步 FFI,必须跑在后台 isolate**。`BgeEmbedder.embed()` 返回
    `List<Float32List>`(**不是 `Future`**),Rust FFI 同步调用会**阻塞所在 isolate**:
    单次 ~128ms、全量索引 ~80s,在 UI isolate 上调用即卡死/ANR。
    复用本仓库既有的"隔离区"模式(该 isolate 内需自行 `RustLib.init()` 并建自己的 embedder)。
47. **插件不会替你截断**。输入超过模型 `max_position_embeddings`(512 token)时 ORT 在
    Add 节点报 `Attempting to broadcast an axis by a dimension other than 1. 512 by N`。
    这是**响亮失败**(好过静默丢内容),但**调用方必须自己切块** ——
    正好由 `KbChunker` 预算 500(且用**字符数当 token 数上界**,中文约 1:1,永不越界)守住。
48. **构建前置条件变重了(本版最大协作成本)**:`flutter_embedder` 走源码编译需要
    ① **Rust 工具链** + ② **MinGW-w64(gcc,作宿主机链接器)** + ③ rustup
    **`default-host` 必须是 `x86_64-pc-windows-gnu`**(cargokit 用裸名 `stable` 调 rustup,
    默认宿主为 msvc 时会报 `toolchain 'stable-x86_64-pc-windows-msvc' is not installed`)+
    ④ **Android NDK 目录下要有 `package.xml`**(cargokit 靠它判断 NDK 是否已安装;
    本机 NDK 只有 `source.properties`,已手工补)。
    **换机器 / 重装 SDK 都要重做 ③④,否则构建失败。**
49. **本插件通过 Gitee fork + git 依赖引入,补丁以 commit 形式存在 fork 里**。
    fork:`https://gitee.com/liuhong1happy/flutter_embedder`(基于上游 0.1.7),
    补丁提交 `d5b6433`(说明见该仓库的 `PATCHES.md`):
    ① `project.exec()` → `providers.exec{}.result.get()`(Gradle 9 已移除前者);
    ② 三处 `java.nio.file.Path` → `String`(`providers.exec` 需序列化参数);
    ③ `compileSdkVersion 33` → `36`、`minSdkVersion 19` → `23`、Java 8 → 17。

    **为什么不用 vendor 也不用 submodule**:
    vendor 会把 1.4MB / ~300 个第三方文件塞进仓库;submodule 则要求每个克隆者记得
    `--recurse-submodules`,且补丁仍要另行维护 —— 两者都没解决"补丁放哪"的问题。
    fork + git 依赖让补丁变成 fork 里的 commit(有历史、可 diff、可 rebase 上游),
    仓库里只留一行 ref。**Gitee 而非 GitHub**:本环境 github 直连不可靠(实测
    HTML 页面无响应、代理 403),而 gitee 可达。
    ⚠️ **pubspec 里用 HTTPS 而非 SSH 地址**:HTTPS 可匿名读取,CI/同事无需配密钥;
    SSH(`git@gitee.com:...`)只在**推送补丁**时需要。
    ⚠️ **ref 必须钉 commit sha,不要用分支名** —— 否则上游一动,构建内容就悄悄变了。
    上游是 **0.1.7、最后发布 2026-01-20(已 8 个月)**;升级上游时把新版合进 fork、
    重打补丁、再更新 ref。
50. **`flutter_rust_bridge` 的 Dart 侧必须钉死 `2.11.1`**。插件 Rust 侧钉
    `=2.11.1`,Dart 侧只声明 `^2.11.1` 会被解析到更新版,运行时抛
    `codegen version (2.11.1) should be the same as runtime version (2.13.0)`。
    已在 `pubspec.yaml` 用 `dependency_overrides` 钉住。
51. ⚠️ **"预编译产物"那条路有个未查明根因的 bug(已绕开,未修)**:
    走预编译时产物**下载成功却没进 APK** —— cargokit 把输出目录落到了插件源码树的
    `android/src/main/jniLibs/arm64-v8a/`(空目录),于是 Gradle 静默打了不含该库的包,
    **构建"成功"但 APK 里根本没有 `libflutter_embedder.so`**。
    当前对策是 `cargokit_options.yaml` 里 `use_precompiled_binaries: false` **强制源码编译**,
    路径自然正确。**代价是每台机器都要有 Rust**(见坑 48)。
    若能查明并修掉这个 bug,即可恢复"下载预编译、免装 Rust"的快路径 —— **值得做**。
52. **隐式耦合**:嵌入依赖 APK 内存在名为 `libonnxruntime.so` 的库(sherpa 提供)。
    将来 sherpa 改名或不再打包,嵌入会在**运行时**才失败 ⇒ 需要**启动自检**。
53. `cargokit_options.yaml` 里的 `verbose_logging: true` 是排查期临时开的,**应关掉**(已关)。
54. ⚠️ **重构时别破坏 `??` 的短路求值 —— 它承担着"测试不碰 path_provider"的职责**。
    `AppDependencies.init()` 里原本是:
    ```dart
    final conversationStore = _conversationStore ??
        SqliteConversationStore(await _conversationDbPathProvider());
    ```
    `??` 短路 ⇒ 注入了内存 store 时**根本不会**调用 `_conversationDbPathProvider()`,
    而它默认走 `path_provider`,在单元测试里抛 `MissingPluginException`。
    引入 `AppDatabase` 时我把 `await` 挪到了 `??` 外面,变成**无条件调用**,
    于是**所有注入了内存 store 的测试全挂**(报的就是上面那个异常)。
    现写法显式保留惰性(见 init 里的注释与 `appDatabase` 为何可空)。
    **教训:凡是"注入替身就跳过真实依赖"的地方,依赖惰性求值的代码都不能随手外提。**
55. ☠️ **不要给本项目加 `integration_test` dev 依赖 —— 它会直接搞坏 release 构建。**
    实测:加了 `integration_test`(SDK 包)之后,`flutter build apk --release` 报
    `compileReleaseJavaWithJavac` 失败:
    ```
    GeneratedPluginRegistrant.java:34: 程序包 dev.flutter.plugins.integration_test 不存在
    GeneratedPluginRegistrant.java:54: 程序包 pl.leancode.patrol 不存在
    ```
    机制:该文件由 Flutter 生成在 `android/app/src/main/java/io/flutter/plugins/`
    (**未被 git 跟踪**),加入新 dev 依赖会触发它重新生成,而重新生成的版本把
    **dev-only 插件也写了进去**;release 变体的 classpath 里没有这些插件类 ⇒ 编译不过。
    (只有 `patrol` 时不会触发;加了 `integration_test` 就会。)
    **已验证**:去掉该依赖后 release 立刻构建成功(153.2 MB)。
    ⇒ **设备侧测试一律放 `patrol_test/`**(项目本来就用 patrol,且不受此影响)。
    本版把嵌入引擎的设备验证按此原则迁到了 `patrol_test/embedding_test.dart`。
20. **首次构建需 Maven Central**(插件拉 ORT 原生库)。
    ✅ **2026-09-29 实施实测:已被现有配置覆盖,不再是风险** —— `android/settings.gradle.kts`
    的 `dependencyResolutionManagement` 里早就配了**阿里云镜像**
    (aliyun google/central/public + google + mavenCentral),ORT AAR 顺利拉取,
    `~/.gradle/caches` 下 4 个 ABI 的 `libonnxruntime.so` 全部就位
    (armeabi-v7a / arm64-v8a / x86 / **x86_64**)。**x86_64 在 ⇒ 模拟器可做真机验证。**
21. Android 需 `android/app/proguard-rules.pro`:`-keep class ai.onnxruntime.** { *; }`。

**嵌入正确性(全是"不报错只变差"型)**

22. **池化用 CLS 不是 mean**。mean 池化一样能算出 512 维、一样能存能检索,只是**排序整体劣化**,
    无任何异常可看。依据 `1_Pooling/config.json`。
23. **`do_lower_case` 两份配置互相矛盾**(实测,已定案):候选三源 ——
    `sentence_bert_config.json` = `true` vs `tokenizer_config.json` = **`false`**
    vs **`tokenizer.json` 的 `normalizer.lowercase` = `false`**。
    取 **false**:`tokenizer.json` 是运行时的**权威**来源,另两处与之矛盾的是
    sentence-transformers 写入的遗留默认值。
    ✅ **并已用行为证实**:真词表下 `Hello` → `[101, 100, 102]`,**100 = `[UNK]`**
    (词表里只有小写 `hello`)。若误按 lowercase=true 处理会先折叠成 `hello` 并命中其 id
    —— 这条已固化为回归用例(`test/wordpiece_tokenizer_test.dart`)。
24. **必须 L2 归一化**,否则"点积当余弦"是错的,且**排序看起来还算合理**。
25. **ONNX 外置数据陷阱**:`onnx-community/bge-small-zh-v1.5-ONNX` 是 `.onnx`(**168,002 B**,仅图)
    + `.onnx_data`(**23,774,208 B**,权重)拆分格式,ORT 要求两者**同名同目录**,
    只下 `.onnx` 必然加载失败。**用 `Xenova/bge-small-zh-v1.5` 单文件版**,并在 resolver
    断言 embedding 目录不出现 `_data` 伴生文件。
26. **超长必须截断到 510 token**。
27. **换嵌入模型后旧向量必须废弃**(`model_id` 不匹配即视为未嵌入)。

**原生资源**

28. `OrtSession.close()` / `OrtValue.dispose()` **不在 Dart GC 管辖内**。批量循环漏 `dispose`
    会稳定泄漏原生堆直至 OOM,而 **Dart 侧内存曲线看不出来**。循环写 `try/finally`。
29. **嵌入引擎空闲必须卸载**(session 常驻约 100MB);沿用"各引擎独立懒加载"原则,
    **不得在页面 build 时加载**(坑 9)。

**设计与语义**

30. **不得复用 `TextChunker` 做知识库切块**(见 11.5-2)。
31. **未知说话人零 LTM 抽取 + 零注入**(见 11.5-5)—— 必须有回归测试守住。
32. **知识库/记忆检索失败一律降级为不注入**。
33. **提示词必须要求不要念出 `[1]` 这类引用标记** —— 回复会被 TTS 朗读,
    用户会**听见"资料方括号一"**。这是语音场景独有的坑,文本聊天里根本不会暴露。
34. **STM 摘要必须增量**(水位线),全量重摘要 O(n²)。
35. **摘要/抽取失败静默跳过**,绝不阻塞对话、绝不弹错。
36. **`_buildLlmMessages()` 改 async** 会波及 `test/conversation_service_test.dart` 现有断言;
    先改签名再跑测试,别等最后一并发现。
37. **导入要有体积与算力上限**(单文件上限 + 批大小上限),防一次导入把手机算爆。
38. **KB 与 LTM 分开存、分开删**(表与入口都分开),合并会导致"删记忆顺带删资料"。
39. **编辑器编码兜底**:UTF-8 为主,失败试 GBK(中文 txt 常见),再失败给可读错误。

### 11.8 本版新增的隐私边界(必须写进 README)

⚠️ 与"声纹不是安全因子"(v1.0.1)并列的**第二条边界**:

1. **知识库与长期记忆的内容会发给第三方 LLM**。本版把"送出去的数据"从"当前对话"扩大到
   "用户的文档片段与关于用户的持久事实"。**这是本版最大的隐私面变化。**
   注入的是**检索命中的片段**而非整库 —— 但命中片段同样可能含敏感信息。
2. **KB 与记忆明文落盘**(SQLite,非加密),本机可读。
3. **记忆抽取额外消耗用户自付的 API token**,且每次抽取都会把已有记忆 top-k 一起发送。
   开关默认开,但设置页必须说明。
4. **未知说话人不注入任何长期记忆** —— 本版唯一一条真正的隔离保证,需回归测试守住(同 11.5-5)。

### 11.9 实施期实测结果与新增坑位(2026-09-29 实施中)

**已实测通过(不再是"规划中的假设")**

| 项 | 结果 |
|---|---|
| 依赖解析 | `flutter pub get` 通过;新增包仅 `flutter_onnxruntime`、`file_picker` 及其平台实现 + `cross_file`/`win32`/`xml`/`petitparser`/`dbus`/`ffi_leak_tracker`。**`jni`/`jni_flutter` 是既有依赖**(来自 `record` 7.x),不是本版引入 |
| ORT 原生库 | 阿里云镜像生效,4 个 ABI 的 `libonnxruntime.so` 全部就位(**x86_64 在 ⇒ 模拟器可验证**) |
| 模型下载 | **ModelScope 直连实测 `http=200`,`24,010,842 B`(与 API 报的字节数精确一致),`2.59s` 下完**,魔数 = ONNX protobuf |
| 分词器 | **与 transformers.js(官方 Rust tokenizers,同源 HF Python)在 20 条文本上逐 token 完全一致**(中文逐字/中英混排/中英标点/空白/数字/600+ 字长文)。31 项单测全绿 |

**新增坑位(40 起)**

40. **插件对 `List<int>` 会推断成 `Int32List`,而 BERT 要 int64**。`OrtValue.fromList` 按数值
    范围推断类型,落在 Int32 内就转 `Int32List` ⇒ 模型拒绝或**静默算错**。
    **必须显式传 `Int64List`**(`embedding_engine.dart` 已如此)。
41. **输出张量整体跨 method channel 回传,`B` 与 `L` 直接决定传输开销**。插件的
    `runInference` 返回后还要 `getOrtValueData` 取数据,而 `last_hidden_state` 是 `[B,L,512]`
    —— L=510、B=1 时单条就是 **262,144 个数**。原计划"批处理摊薄成本"的假设**必须实测复核**:
    批大摊薄推理次数,但放大传输量,存在最优点。
    **`batchSize` 与 `maxTokens` 是性能旋钮,默认值须由真机实测决定**(见阶段 17)。
42. **检索的 `minScore` 不设默认阈值**。起先默认 `0.0`,导致反向向量(-1.0)被静默滤掉,
    调用方"传了候选却拿不到候选"且看不出原因。现改为哨兵常量
    `kNoScoreThreshold = double.negativeInfinity` —— **过滤是调用方的显式决定**,
    业务阈值(`kbScoreThreshold = 0.45`)属于设置层。
43. **切块器的两个 off-by-one(均被测试抓出,已修)**:
    ① `_splitBlocks` 曾给每行无条件补 `\n`,使**最后一块多出一个源文本里不存在的换行**,
    `charEnd` 越界(321 > 320);
    ② 为处理 CRLF 而剥离 `\r` 后,`text.length` 不再等于块在源文本中的跨度,
    导致**所有块区间整体短算、相邻块之间出现未覆盖空隙**。
    定案:**内部文本必须与源文本逐字符对应**(偏移才算得准),`\r` 只在产出
    `KbChunk.text` 时清理。
    → 由此确立一条硬性不变量并立了回归用例:**每个块的 `0 <= charStart < charEnd <= 文档长度`**。
44. **知识库切块的不变量是"不丢内容"**,不是"切得整齐"。切块出错时用户完全无感
    (只是"检索不到那一句"),所以测试用**字符区间并集覆盖全文非空白字符**来守
    (`expectFullCoverage`),而不是靠肉眼看块数。
45. ⚠️ **`flutter test integration_test/` 里 `path_provider` 不可用**(实测踩到)。
    `path_provider_android` 2.x 在 Android 上**直接走 `package:jni`**,而
    `flutter test integration_test/xxx.dart -d <设备>` **不执行 app 的 `main()`**
    ⇒ Dart 侧插件(`jni_flutter`)未初始化 ⇒
    `getApplicationDocumentsDirectory()` 抛 **`No JNI instance is available`**。
    **patrol 走真实 `main()`,所以既有 patrol 测试从不暴露这个问题** —— 只有新加
    integration_test 才会踩。
    对策:设备侧测试**不要用 `path_provider`**,直接写应用私有目录。已从源码确认路径:
    `getApplicationDocumentsPath()` = `context.getDir("flutter", MODE_PRIVATE)`
    ⇒ **`/data/user/0/<pkg>/app_flutter`**;
    `getApplicationSupportPath()` = `context.filesDir` ⇒ `/data/user/0/<pkg>/files`
    (**两者不是一回事,别写混**)。见 `integration_test/embedding_spike_test.dart`。
46. ⚠️ **patrol 用例名里不能出现 `/`**(实测踩到,代价是"整轮 0 个用例")。
    Android Test Orchestrator 拿用例名当文件名去 `openFileOutput('<用例名>.txt')`,
    名字里带路径分隔符 ⇒ `IllegalArgumentException: File ... contains a path separator`
    ⇒ **Orchestrator 自己被杀**,最终只报回
    `Total: 0` + `Instrumentation run failed due to Process crashed`。
    **看起来像 App 崩了,其实一个用例都没跑**,而且 Dart 侧没有任何堆栈 ——
    真相只在 `adb logcat` 里的 `AndroidTestOrchestrator` 一行。
    对策:用例描述用 `+`、`→`、`;`,**不要用 `/`**。
    (`patrol_test/embedding_test.dart` 原来的 "加载 / 语义 / 后台 isolate 不阻塞 UI" 就踩了这个 ——
    整轮 0 用例、且看起来像 App 崩溃;改成 `加载 + 语义 + ...` 后设备实测通过,
    含 ModelScope 真实下载 24.5MB + 后台 isolate 不阻塞校验。)

---

## 关键文件清单

- 修改:`lib/models/tts_model.dart`、`lib/data/model_catalog.dart`、`lib/data/model_files_resolver.dart`、`lib/data/model_manager.dart`、`lib/app_dependencies.dart`、`lib/app.dart`、`lib/ui/main_shell.dart`、`lib/ui/tts_settings_page.dart`、`lib/models/tts_settings.dart`、`lib/dva/app_models.dart`、`lib/dva/app_dva.dart`、`lib/tts/tts_streaming_service.dart`、`pubspec.yaml`、`android/app/src/main/AndroidManifest.xml`、`android/app/build.gradle.kts`(minSdk)、`lib/l10n/app_zh.arb`+`app_en.arb`
- 新增:`lib/tts/isolate_bridge.dart`、`lib/tts/wav_reader.dart`、`lib/tts/vad_engine.dart`、`lib/tts/asr_engine.dart`、`lib/tts/speaker_engine.dart`、`lib/tts/pocket_tts_engine.dart`、`lib/audio/mic_recorder.dart`、`lib/asr/asr_service.dart`、`lib/voiceprint/voiceprint_service.dart`、`lib/llm/llm_client.dart`、`lib/llm/llm_service.dart`、`lib/voiceclone/voice_cloning_service.dart`、`lib/conversation/conversation_message.dart`、`lib/conversation/conversation_store.dart`、`lib/conversation/conversation_service.dart`、`lib/ui/conversation_page.dart`、`lib/ui/history_page.dart`、`lib/ui/clone_voices_page.dart`、`lib/ui/voiceprint_page.dart`、`lib/ui/widgets/conversation_bubble.dart`
- 删除:`lib/ui/model_manage_page.dart`、`lib/ui/conversation_settings_page.dart`(模型管理/对话设置已并入设置页两级结构)。

**2026-09-29 声纹扩展涉及的文件**(路径以实际仓库为准,上表用的是旧目录约定):

- 新增:`lib/utils/app_lock_service.dart`(设备认证抽象 + local_auth 实现)、
  `lib/pages/voiceprint/utils/voiceprint_auth.dart`(写操作前的认证守卫,三处共用)、
  `test/voiceprint_models_test.dart`、`test/enroll_page_test.dart`。
- 主要修改:`lib/utils/voiceprint_service.dart`(分桶 + 跨模型识别 + 纯编解码 + `ensureStoreLoaded`)、
  `lib/utils/engines/speaker_engine.dart`(按 modelId 分槽)、`lib/utils/conversation_service.dart`
  (识别提前到 ASR 前、门禁、按人切音)、`lib/data/model_catalog.dart`(CAMPPlus + `speakers()` +
  `kLegacyVoiceprintModelId`)、`lib/data/models/tts_settings.dart` + `lib/data/dva/app_models.dart`
  (三个新设置)、`lib/pages/voiceprint/`(录制页/管理页/识别弹窗)、
  `lib/pages/settings/sections/voiceprint_section.dart`、`lib/pages/conversation/components/status_bar.dart`
  (门禁错误文案)、`lib/data/app_dependencies.dart`(注入 `appLock` + 启动读声纹档案)、
  `lib/l10n/app_zh.arb` + `app_en.arb`、`pubspec.yaml`(`local_auth`)、
  `android/app/src/main/AndroidManifest.xml` + `MainActivity.kt`、`ios/Runner/Info.plist`、
  `test/support/fakes.dart` 与全部构造 `AppDependencies` 的测试文件(注入 `FakeAppLockService`)。

**2026-09-29 v1.0.2 规划涉及的文件**(尚未创建/修改,规划清单):

- 新增:
  - `lib/utils/memory/wordpiece_tokenizer.dart`(纯 Dart BERT 分词器)
  - `lib/utils/memory/embedding_engine.dart`(ORT 抽象 + `flutter_onnxruntime` 实现 + 批处理)
  - `lib/utils/memory/vector_store.dart`(SQLite BLOB 存取 + 暴力点积 top-k)
  - `lib/utils/memory/kb_chunker.dart`(**独立于 `text_chunker.dart`**)
  - `lib/utils/memory/knowledge_service.dart`(导入/切块/异步回填/检索)
  - `lib/utils/memory/session_memory_service.dart`(会话分段 + 滚动增量摘要)
  - `lib/utils/memory/memory_service.dart`(LTM 抽取 / ADD-UPDATE-NONE 去重 / 检索)
  - `lib/utils/memory/context_assembler.dart`(**预算编排,本版核心**)
  - `lib/data/models/memory_item.dart`、`lib/data/models/kb_document.dart`
  - `lib/pages/knowledge/knowledge_page.dart`(+ 检索试跑)、`lib/pages/memory/memory_page.dart`
  - `test/wordpiece_tokenizer_test.dart`、`test/kb_chunker_test.dart`、
    `test/knowledge_service_test.dart`、`test/memory_service_test.dart`、
    `test/context_assembler_test.dart`、`patrol_test/knowledge_test.dart`
- 主要修改:
  - `lib/data/models/tts_model.dart`(`ModelKind.embedding` + `ModelRawFile` + `rawFiles` 多文件)
  - `lib/data/model_catalog.dart`(嵌入模型条目 + ModelScope 基址常量 + `kDefaultEmbeddingModelId`)
  - `lib/data/model_files_resolver.dart` / `model_manager.dart`(embedding 分支 + 多文件 raw 下载
    + `_data` 伴生文件断言)
  - `lib/data/conversation_store.dart`(DB 升版本 + `_migrations` 追加:KB/LTM/摘要表 +
    `conversation_messages.session_id`)
  - `lib/utils/conversation_service.dart`(`_buildLlmMessages` **改 async** + 检索注入 + 抽取触发)
  - `lib/data/models/tts_settings.dart` + `lib/data/dva/app_models.dart`(8 个新设置,五处模式)
  - `lib/data/app_dependencies.dart` + `lib/app.dart`(接线 + MultiProvider)
  - `lib/pages/settings/sections/`(记忆 / 知识库两个新子页)+ `lib/pages/settings/settings_page.dart`
  - `lib/l10n/app_zh.arb` + `app_en.arb`、`pubspec.yaml`(`flutter_onnxruntime`、`file_picker`)、
    新增 `android/app/proguard-rules.pro`、`README.md`(模型源 + 隐私边界)
