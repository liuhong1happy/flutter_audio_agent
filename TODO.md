# TODO / 主计划 — 语音对话 + 声音克隆 + 声纹识别(自足交接文档)

> 更新日期:2026-08-23
> 本文件是**自足交接文档**:包含功能清单、实施追踪、以及全部已核实的实现知识(sherpa_onnx API 签名、模型 URL/体积、现有代码地图、设计决策、坑位)。在任意新机器上仅凭本文件即可实施,无需本机缓存或记忆。
> 关联:详细 TTS 现状见 `docs/敏捷开发/v1.0.0 APP设计内容.md`、`README.md`。

---

## 〇、一句话目标

给 flutter_tts_demo(现为纯离线 TTS,仅用 sherpa_onnx `OfflineTts` 的 vits/kokoro 族)新增**「语音对话」**核心页(VAD 常开免按 → 离线 ASR → 声纹识别说话人 → 在线 LLM → TTS 语音回复),并附带**声音克隆**(配置型,PocketTTS 零样本克隆音,对话可选发音)与**声纹识别**(对话中自动识别说话人,非独立 Tab)。

### 已确认决策(不要改)
- **LLM = DeepSeek V4 Flash 在线版**(OpenAI 兼容 API,`chat/completions` 流式)。这是**唯一联网组件**;ASR/TTS/克隆/声纹/VAD 全部离线。
- 平台 **Android 优先**(v1 只在 Android 验证;iOS 本期不做,但代码尽量平台无关)。
- 对话页做**一键初始化**:未就绪时显示三件套(VAD/ASR/TTS)卡片,一键下载默认模型并自动配置。
- 克隆与声纹为**配置型能力**,不对应独立底部 Tab;底部导航共 4 个 Tab(合成 / 模型 / 对话 / 设置)。
- 说话人识别深度 = **个性化对话 + 按人记忆**:身份注入 LLM 提示词、每位说话人独立对话历史、未知说话人访客模式。**不做**按说话人换发音(超范围)。

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
| speaker | 3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k | `speaker-recongition-models`(基址名是官方这个拼写,带 typo)下 **裸 `….onnx`** | 39,593,761 | 单文件 onnx,无解压 |
| vad | silero_vad | `asr-models` 下 **裸 `silero_vad.onnx`** | ~629,000 | 单文件 onnx,无解压,仅 16kHz |
| pocket | sherpa-onnx-pocket-tts-int8-2026-01-26 | `tts-models` 下同名 tar.bz2 | 98,336,520 | 解压含 `lm_flow.int8.onnx`、`lm_main.int8.onnx`、`encoder.onnx`(**fp32**)、`decoder.int8.onnx`、`text_conditioner.onnx`、`vocab.json`、`token_scores.json` |

基址常量(新增到 `model_catalog.dart`):
```dart
const String kAsrModelsReleaseBase = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models';
const String kSpeakerModelsReleaseBase = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models';
```

**默认对话三件套** `kDefaultConversationModelIds = {vad: 'silero_vad', asr: 'sherpa-onnx-paraformer-zh-2023-09-14', tts: 'vits-piper-zh_CN-xiao_ya-medium-int8'}`(TTS 用目录最小 14MB,下载快)。

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

- **入口**:`lib/main.dart` → `initDva` → `lib/app.dart`(`MaterialApp` + `MultiProvider` 暴露 settings/modelManager/streamingService)→ `lib/ui/main_shell.dart`(底部导航 + IndexedStack,3 Tab:合成/模型/设置;跨 Tab 用回调,**无命名路由**,仅 `model_manage_page` 弹窗用 `Navigator.pop`)。
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
- `tts_settings_page` 声音下拉过滤 `kind==tts`;`model_manage_page` 非 TTS 显示种类标签。

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
- `main_shell.dart`:第 4 Tab「对话」(`IndexedStack` 插 `ConversationPage`;设置页索引 2→3;`SynthesizePage.onNavigateToSettings` 改 `_switchTo(3)`)。
- `conversation_page.dart`:初始化卡片(未就绪)→ 状态胶囊 + 当前说话人胶囊 + 聊天气泡(用户徽章/流式助手文本)+ 开始/停止对话 + 静音开关 + 声音选择器(模型音+克隆音)+ 清空历史;AppBar 动作 `Navigator.push`(本仓库首次引入,无需命名路由)进子页。**不复用** `SpeakingBubblesView`。
- `clone_voices_page.dart`(push):克隆音列表 + 新建(命名→录 3–10s 参考)+ 删除。
- `voiceprint_page.dart`(push):说话人列表 + 注册(名字+备注+录 2–3 段)+ 测试识别 + 删除。
- `conversation_settings_page.dart`(push):LLM(baseUrl/ApiKey/模型/系统提示)、ASR 模型下拉、VAD 阈值/静音时长、声纹阈值滑块。

### 5.7 设置与持久化
`TtsSettings`+`SettingsState` 新增:llmBaseUrl(`https://api.deepseek.com/v1`)、llmApiKey、llmModel(`deepseek-chat`;用户可填其"V4 Flash"标识)、llmSystemPrompt、asrModelId、voiceprintThreshold(0.6)、vadThreshold(0.5)/vadMinSilence(0.5)/vadMaxSpeech(15)、conversationVoiceType(model|clone)/conversationModelVoiceId/conversationCloneId/conversationSid。
dva 新命名空间:`clones`、`voiceprints`(含备注)、`conversation`(按说话人分桶);注册进 `app_dva.dart`。

### 5.8 l10n 键(zh+en 同步,gen-l10n)
conversationTab、startConversation/stopConversation、listening/recognizing/thinking/speaking、speakerUnknown、currentSpeaker(占位符)、currentSpeakerChip(占位符)、guestMode、registerHint、speakerNoteHint、micMuted/micUnmuted、cloneVoicesTitle、recordReferenceHint、voiceprintTitle、enrollSpeaker、identifyTest、conversationSettingsTitle、llmBaseUrl/ApiKey/Model/SystemPrompt、asrModelLabel、vadThreshold/vadMinSilence、voiceprintThreshold、micPermissionDenied、模型种类标签(语音识别/声纹/克隆/VAD)、emptyAsrText、clearConversation、sendError/llmError、initModelsTitle、initModelsHint、initReady、downloadInitialModels、initProgress(占位符)、initRetry、initDone。

---

## 六、实施阶段(每阶段可验证)

- [ ] **0 写入 TODO.md**:本文件即交接文档(已完成)。
- [ ] **1 重构(无行为变化)**:`ModelKind`/`downloadFormat`/`rawFileName`、抽 `IsolateBridge`(含单向/事件通道)并重构 `SherpaTtsEngine`、加 `wav_reader`。验证:现有 test+patrol 全绿。
- [ ] **2 目录/下载泛化**:新增 5 项模型、resolver 按 kind、manager raw 分支、管理页标签、设置页过滤。验证:resolver 各 kind 单测、manager raw 路径单测;手动下载声纹+VAD 确认 ready。
- [ ] **3 录音基建**:`MicRecorder` 流式+落盘+权限;`wav_reader_test` 与 `wav_encoder` 往返。
- [ ] **4 VAD**:`VadEngine` 流式+段回调单测(合成 PCM 断言 SpeechSegment);真机静音/说话切换。
- [ ] **5 ASR**:`AsrEngine`+`AsrService`+`asrModelId` 设置。
- [ ] **6 声纹**:`SpeakerEngine`+`VoiceprintService`+注册/识别/删除+持久化。
- [ ] **7 克隆**:`PocketTtsEngine`+`VoiceCloningService`+克隆音管理 UI。
- [ ] **8 LLM**:`LlmClient/Service`+SSE 解析+`llm_client_test`(mock dio 喂 `data:`/`[DONE]`/UTF-8 跨块)。
- [ ] **9 对话集成+UI**:`ConversationService`(VAD 常开+按人记忆+一键初始化)、对话页、子页、Tab 接线、l10n 重生成;widget 测试全 fake(初始化卡片四态:未就绪/就绪/下载中/完成)。
- [ ] **10 验证收尾**:真机全流程;patrol 扩展 `conversation_test.dart`;截图。

## 七、风险与坑(实施必读)

1. **常开麦克风**:TTS 播报期间必须停 mic 防自听反馈(播完自动恢复);前台应用,不做后台常驻;Android 会显示麦克风指示。
2. **Pocket 解压后体积大**(压缩 98MB → 数百 MB);各引擎独立懒加载,避免同时常驻。克隆引擎仅在选择克隆音时 load。
3. **声纹/VAD 是裸 onnx**:`ModelManager` 的 rawFile 分支必须跳过 bzip2 魔数校验与解压,勿对 `silero_vad.onnx`/eres2net.onnx 走解压路径。
4. **`SpeakerEmbeddingExtractor` 用 `OnlineStream`**(不是 `OfflineStream`,勿照抄 ASR worker);`while(isReady){})` 忙等会阻塞 worker 事件循环 → bridge 必须串行,勿并发调用 speaker 引擎。
5. **SSE 解析**:多字节 UTF-8 跨 TCP 块必须状态化 `utf8.decoder`;处理 `data: [DONE]`、空 keepalive `data:` 行、provider 错误 payload;401/空 key 转友好错误。
6. **DeepSeek 模型 id**:真实 API 为 `deepseek-chat`/`deepseek-reasoner`;"DeepSeek V4 Flash"是用户自定义标识,存于设置 `llmModel` 字段。baseUrl 默认 `https://api.deepseek.com/v1`(OpenAI 兼容)。
7. **l10n**:键必须同时写 `app_zh.arb` 和 `app_en.arb`,否则 gen 失败;占位符需 `@key` 元数据。
8. **现有测试**:`AppDependencies` 只加可选参数;`TtsModel`/`ResolvedModelPaths` 新字段带默认值 → 现有构造不破坏。实施前 grep 是否有断言 `ModelCatalog.all.length` 或"全部 multi-speaker"的测试。
9. **IndexedStack 保持各 Tab 存活**:任何 sherpa isolate 不得在对话页 build 时 spawn(引擎全部懒加载);对话播报前 `streamingService.stop()`。
10. **API key 明文存 SharedPreferences**(flutter_dva)——demo 可接受,README 注明。
11. PocketTTS 零样本无需参考文本;参考音频 3–10s、单声道、float[-1,1],模型自会重采样到其格式。
12. `record` 包权限用 `hasPermission()`/`requestPermission()`;Android minSdk ≥23。

## 八、验证

- **单元**:wav 往返;resolver 各 kind;pocket 7 文件形状;speaker/vad 裸 onnx;manager raw 分支;vad 流式段回调;asr/voiceprint/cloning service(假引擎);llm_client(mock dio SSE);conversation_service(全假:VAD 段驱动状态迁移/按说话人历史隔离与恢复/未知说话人访客模式/提示词注入身份与备注/声音路由/错误路径/初始化)。
- **Widget**:对话页(初始化卡片四态、麦按钮状态、说话人徽章、流式气泡、静音开关)。
- **Patrol**:`app_smoke_test` 不受 Tab 增加影响 + 新增 `conversation_test.dart`(假 MicRecorder 流式吐 PCM,假 VAD/ASR/LLM/引擎,复用 `test/support/fakes.dart` 与 `buildPatrolTestDeps` 模式)。
- **真机全流程**:① 清缓存首进对话页→一键下载三件套→自动配置→开始对话;② 注册张三/李四(各填备注)→分别对话:回复个性化(备注生效、直呼姓名)、历史互不串扰;③ 未注册第三人→访客模式,通用回复、不泄已注册记忆;④ 说话→静音自动转写→DeepSeek 流式→语音回复→播完自动恢复聆听;⑤ 选克隆音(录 5s 参考)→以克隆音色回复;⑥ 播报时静音、中途 stop、初始化中途取消/重试;⑦ 杀进程重启:克隆/声纹(含备注)/按说话人历史持久、初始化不重复提示。

---

## 关键文件清单

- 修改:`lib/models/tts_model.dart`、`lib/data/model_catalog.dart`、`lib/data/model_files_resolver.dart`、`lib/data/model_manager.dart`、`lib/app_dependencies.dart`、`lib/app.dart`、`lib/ui/main_shell.dart`、`lib/ui/tts_settings_page.dart`、`lib/ui/model_manage_page.dart`、`lib/models/tts_settings.dart`、`lib/dva/app_models.dart`、`lib/dva/app_dva.dart`、`lib/tts/tts_streaming_service.dart`、`pubspec.yaml`、`android/app/src/main/AndroidManifest.xml`、`android/app/build.gradle.kts`(minSdk)、`lib/l10n/app_zh.arb`+`app_en.arb`
- 新增:`lib/tts/isolate_bridge.dart`、`lib/tts/wav_reader.dart`、`lib/tts/vad_engine.dart`、`lib/tts/asr_engine.dart`、`lib/tts/speaker_engine.dart`、`lib/tts/pocket_tts_engine.dart`、`lib/audio/mic_recorder.dart`、`lib/asr/asr_service.dart`、`lib/voiceprint/voiceprint_service.dart`、`lib/llm/llm_client.dart`、`lib/llm/llm_service.dart`、`lib/voiceclone/voice_cloning_service.dart`、`lib/conversation/conversation_service.dart`、`lib/ui/conversation_page.dart`、`lib/ui/clone_voices_page.dart`、`lib/ui/voiceprint_page.dart`、`lib/ui/conversation_settings_page.dart`
