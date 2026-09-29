# TODO / 主计划 — 语音对话 + 声音克隆 + 声纹识别(自足交接文档)

> 更新日期:2026-09-29
> 本文件是**自足交接文档**:包含功能清单、实施追踪、以及全部已核实的实现知识(sherpa_onnx API 签名、模型 URL/体积、现有代码地图、设计决策、坑位)。在任意新机器上仅凭本文件即可实施,无需本机缓存或记忆。
> 关联:详细设计现状见 `docs/敏捷开发/v1.0.1 APP设计内容.md`(当前版本)、`docs/敏捷开发/v1.0.0 APP设计内容.md`(纯 TTS 基线)、`README.md`。
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

### 2.1 现有 5 项(tts,勿动,列表供参考)
来源基址:`https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models`;代理列表 `kChinaGitHubProxies = ['https://ghfast.top/','https://ghproxy.net/','https://gh-proxy.com/','https://ghps.cc/']`

| id | 说明 | 字节 | speakers | sampleRate |
|---|---|---|---|---|
| vits-piper-zh_CN-xiao_ya-medium-int8 | Piper 晓雅 | 14,016,124 | 1 | 22050 |
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
