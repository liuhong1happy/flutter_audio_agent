# flutter_tts_demo

基于 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 的跨平台(Android / iOS)离线文本转语音演示应用。

## 功能

1. **底部 Tab 布局** — 合成 / 对话 / 设置三个平级 Tab,`IndexedStack` 常驻各页,播放中切换不中断。
2. **文本转语音(聊天式界面)** — 底部输入框;每次发送 = 一条气泡(整段文本),正在读的气泡内
   **逐词高亮**(卡拉OK式);点击气泡可重新朗读该条。没有可用模型时显示**初始化卡片**
   (推荐最小体积的模型,一键"下载并启用"),而不是等用户点了发送才报错。
3. **统一设置中心(两级)** — 设置页首页为各大类 ListItem(语音合成 / 语音识别 / VAD /
   声纹识别 / 大模型 / 通用),点击进入子页配置各自参数 + **各自模型下载**;通用页含清理缓存。
4. **语音对话(双模式)** — 第 2 Tab「对话」:
   - **音频模式**:语音 → 离线 ASR → 声纹识别 → 在线 LLM → TTS 语音回复,仅显示最后一轮;
   - **文本模式**:打字 → 在线 LLM 纯文本回复(不转 TTS),显示全部历史。
   两种模式的就绪条件**不同**:文本模式只用 LLM,**一个本地模型都不用下载**;音频模式才需要
   VAD/ASR/TTS 三件套。两种模式都需要配好大模型。
   会话历史为**单一时间线**(多说话人,未知说话人访客模式),存 SQLite 并按时间排序、分页。
5. **声音克隆** — PocketTTS 零样本克隆音(录 3–10s 参考)。对话中可选**模型音色或克隆音**,
   也可把克隆音**绑定到某位说话人**——谁说话就用谁的克隆音回话。
6. **声纹识别(双模型)** — 3D-Speaker 的两个声纹模型(ERes2Net / CAMPPlus)可在录入时选择并
   记住上次选择;**档案按模型隔离**(同一名字可在两个模型下各存一份),识别时对每个有档案的
   模型各跑一遍取匹配。注册(整页 + 圆形居中录音按钮,支持连续注册多个)/ 识别 / 删除 / 测试识别。
7. **对话声纹门禁** — 开启后只有声纹库中注册过的人能触发对话:未注册者**不转写、不入库、
   不问 LLM**,只播本地合成的拒绝语。(识别先于 ASR,所以拒绝比放行更省算力。)
8. **声纹写操作保护** — 注册 / 删除声纹、调声纹阈值前要求设备认证(指纹 / 人脸 / 系统 PIN,
   `local_auth`),避免本机任何人都能注册声纹后通过识别。
9. **多服务商 LLM(配置列表)** — OpenAI 兼容接口。大模型是**可逐条添加的配置列表**
   (如"工作 / 个人"各一条),每条含 地址 / API Key / 模型 / **系统提示词**,其中**一条启用**
   为默认;对话只走启用那条。切换服务商(DeepSeek / Moonshot(Kimi)/ 智谱(GLM)/ 通义千问(Qwen))
   会替换该条的地址与默认模型,也支持完全自定义。系统提示词可选,留空用内置人设。
10. **历史浏览 + 管理** — 对话页 Header 左侧历史入口,分页「加载更早」;长按气泡删除单条消息。

> **隐私说明**:LLM 是唯一联网组件(OpenAI 兼容第三方服务);ASR/TTS/克隆/声纹/VAD 全部离线。
> API Key 明文存于本地 SharedPreferences(demo 可接受,请勿提交真实 key 到仓库)。
>
> ⚠️ **声纹不是安全因子**:`local_auth` 门禁与对话门禁都只是**便利性防护**,不是安全边界。
> 具体原因:① 3 秒录音即可重放通过,而本应用的采样恰好就是硬编码 3 秒;② 本应用自带
> PocketTTS 零样本克隆,拿到样本即可合成授权人声音;③ 判定是 192 维嵌入的余弦阈值,是
> 同人/异人的权衡点而非密码学的对错;④ 嵌入以**明文 JSON** 落盘(dva ReduxPersistor,不是
> Keystore/Keychain),本机读出即可注入他人嵌入冒充。对话内容会发给第三方 LLM,若涉及敏感
> 信息,请勿把声纹当作唯一门禁。

## 技术栈

| 组件 | 方案 |
|---|---|
| 框架 | Flutter 3.44.0 / Dart 3.12.0 |
| TTS 引擎 | `sherpa_onnx ^1.13.6`(离线 `OfflineTts`,后台 isolate 合成) |
| 文本归一化 | `num2text`(纯 Dart,数字/金额/年份转中文读法)+ 引擎内置 `ruleFsts` |
| 分词/分句 | 标点分句 + `jieba_flutter` 长句词边界切块 |
| 模型下载 | `dio` 流式下载 + `archive` 解压 tar.bz2 |
| 播放 | `audioplayers`(WAV 顺序播放) |
| 状态/持久化 | `flutter_dva`(dva 模型 + ReduxPersistor,配置/克隆/声纹)+ `provider`(运行时 ChangeNotifier) |
| 会话历史 | `sqflite`(SQLite,`version`+`onUpgrade` 版本化迁移,单一时间线 + 分页) |
| 设备认证 | `local_auth ^3.0.2`(声纹档案写操作前校验指纹/人脸/PIN,`biometricOnly: false` 允许 PIN 兜底) |
| 应用图标 | `assets/icon/app_icon.svg`(含 TTS 信息)→ PNG,`flutter_launcher_icons` 生成各尺寸 |
| 集成测试 | `patrol ^4.9.0` |

> 注:`jieba_flutter` 以硬编码路径 `assets/dict.txt` 通过 `rootBundle` 加载词典,
> 因此仓库内 `assets/` 已复制其 `dict.txt` / `prob_emit.txt`(来源:jieba_flutter 包 assets,Apache-2.0)。

## 内置模型目录

下载前缀(按种类):`tts-models`(TTS/克隆)、`asr-models`(ASR/VAD)、`speaker-recongition-models`(声纹;
基址名是官方 release 的拼写,带 typo,勿"纠正")。全部条目定义在 `lib/data/model_catalog.dart`。

| 种类 | 模型 | 音色 | 大小 | 采样率 | 说明 |
|---|---|---|---|---|---|
| TTS | vits-piper-zh_CN-xiao_ya-medium-int8 | 1 | ~13MB | 22.05kHz | 默认,最小最快 |
| TTS | vits-zh-hf-fanchen-C | 187 | ~114MB | 16kHz | 通用中文多音色 |
| TTS | vits-melo-tts-zh_en | 1 | ~159MB | 44.1kHz | 中英混读(MIT) |
| TTS | vits-zh-hf-theresa | 804 | ~115MB | 22.05kHz | 音色最多 |
| TTS | kokoro-multi-lang-v1_0 | 53 | ~333MB | 24kHz | 最佳中英混读(Apache-2.0) |
| ASR | sherpa-onnx-paraformer-zh-2023-09-14 | — | ~223MB | 16kHz | 对话默认中文识别 |
| ASR | sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17 | — | ~155MB | 16kHz | 中英日韩粤,附情绪/语种 |
| 声纹 | 3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k | — | ~38MB | 16kHz | 192 维声纹嵌入,**默认** |
| 声纹 | 3dspeaker_speech_campplus_sv_zh-cn_16k-common | — | ~27MB | 16kHz | 192 维声纹嵌入,跨域更稳 |
| VAD | silero_vad | — | ~0.6MB | 16kHz | 语音活动检测 |
| 克隆 | sherpa-onnx-pocket-tts-int8-2026-01-26 | — | ~94MB | 24kHz | PocketTTS 零样本克隆 |

> **两个声纹模型的嵌入不可互换**:两者维度同为 192,所以混用不会报错,但识别分数会变成噪音。
> 应用层用"档案按模型分桶"来避免这一点——换模型不会让已注册的人失效,但同名档案在两个模型下
> 是两份独立的记录(`lib/utils/voiceprint_service.dart`)。

国内网络访问 GitHub 较慢时,可在 **TTS 设置 → 下载镜像** 切换镜像前缀。

## 快速开始

```bash
flutter pub get
flutter run            # 需已连接 Android 设备/模拟器(或配置 iOS 模拟器)
```

首次使用:设置 → 语音合成 下载 `Piper 晓雅(int8)` 并选择 → 主页输入文本合成;
对话功能在 设置 → 对话初始化(或对话页一键下载三件套)后使用。

声纹:设置 → 声纹识别 → 下载至少一个声纹模型(ERes2Net 或 CAMPPlus,可都下)→
「注册说话人」录入(每段 2 秒以上,录 2–3 段)。之后对话中会自动识别说话人并把名字与备注
注入 LLM 上下文;想要门禁就在同一页打开「声纹门禁」。**注册/删除声纹前会要求设备认证**,
设备没设指纹/PIN 时会弹说明让你显式关闭该保护(不会静默放行)。

知识库与记忆:设置 → 知识库 → 下载嵌入模型(BGE Small 中文,约 24MB)→
「知识库管理」导入文本(或从设置页导入);对话时自动检索并注入相关片段。
设置 → 记忆 可开关长期记忆(它会让每轮对话多消耗一点 LLM token)。

### ⚠️ 构建前置:Android 需要 Rust 工具链

本项目依赖 `flutter_embedder`(本地文本向量化),它用 **cargokit 从源码编译 Rust**,
而且该依赖指向我们的 Gitee fork(见 `pubspec.yaml` 与 `third_party` 相关说明)。
**全新机器上必须先装好下列工具,否则 `flutter build apk` 会失败:**

| 组件 | 版本/说明 |
|---|---|
| Rust | `stable-x86_64-pc-windows-gnu`(Windows)/ 其它平台用默认宿主即可 |
| 宿主机 C 链接器 | Windows 需 **MinGW-w64(gcc)**;Rust 编 build-script 与 proc-macro 要用它 |
| rustup 默认宿主 | Windows 上必须是 gnu:`rustup set default-host x86_64-pc-windows-gnu` |
| Android NDK | 已随 Flutter 安装即可,但**目录下必须有 `package.xml`** |

```bash
# Windows 示例(参考;其它平台用各自包管理器)
winget install Rustlang.Rustup
winget install BrechtSanders.WinLibs.POSIX.UCRT     # gcc
rustup set default-host x86_64-pc-windows-gnu
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
```

> **NDK 的 `package.xml`**:cargokit 用 `<sdk>/ndk/<版本>/package.xml` 是否存在来判断
> "NDK 已安装";本机 NDK 只有 `source.properties` 时会误判为未安装,进而去调
> `sdkmanager`(而 `cmdline-tools` 往往也没装)而报错。若遇到,手动补一个同结构的
> `package.xml` 即可(内容与 `source.properties` 里的版本一致)。
>
> 首次构建会为每个 ABI 各编一遍 Rust,耗时较长;之后有增量缓存会快很多。

## 代码结构

```
lib/
├── main.dart / app.dart          # 入口(initDva + 依赖装配)
├── app_dependencies.dart         # 手工 DI(patrol 测试可注入假实现)
├── components/                   # 全局组件 + 主题令牌
│   └── theme/                    # app_colors / app_spacing / app_text / app_theme
├── hooks/                        # 全局 Hook(预留)
├── mixins/                       # 全局 Mixin(预留)
├── pages/                        # 页面
│   ├── main_shell.dart           # 底部导航骨架
│   ├── synthesize/  conversation/  history/  settings/  clone_voices/  voiceprint/
│   │   └── voiceprint/utils/     # record_samples / voiceprint_auth(写操作前的设备认证守卫)
├── data/                         # 数据处理
│   ├── models/                   # TtsModel / TtsSettings / ConversationMessage
│   ├── dva/                      # flutter_dva:app_models + app_dva
│   └── (model_catalog / downloader / manager / resolver / extractor / app_paths / conversation_store)
├── utils/                        # 其他帮助方法 + 服务 + 引擎
│   ├── engines/                  # tts / vad / asr / speaker(按 modelId 分槽) / pocket 引擎
│   └── (services / app_lock_service / 文本管线 / wav / isolate_bridge / 播放器 / llm / mic)
└── l10n/                         # gen-l10n 生成(勿手改)
test/                             # 单元测试 + widget 冒烟(fakes 见 test/support/)
patrol_test/                      # Patrol 集成测试(app_smoke / conversation / settings /
                                  #   knowledge / memory / context_injection)
scripts/                          # build-android.sh / build-ios.sh / adhocExportOptions.plist
assets/icon/                      # app_icon.svg(设计源)+ app_icon.png(1024)
```

## 文本处理管线(需求 4)

```
原文 → TextNormalizer(num2text)→ 归一化文本(含 sourceMap)
     → TextChunker(标点分句 + jieba 长句切块)→ 片段列表
     → 后台 isolate: OfflineTts.generate(逐段)
     → SequentialAudioPlayer 顺序播放;每段开始播放时更新 currentSegment
     → StreamingTextView 高亮当前片段 + 自动滚动
```

- **归一化**:阿拉伯数字/百分比/年份/金额 → 中文读法;电话上下文与长数字串逐位朗读;
  全角转半角;保留"归一化文本 ↔ 原文"字符级映射,支撑"原文视图"高亮。
- **引擎归一化兜底**:模型自带的 `number.fst` / `date.fst` / `phone.fst` 经 `ruleFsts` 传给引擎,
  覆盖 App 层未处理的场景(号码、复杂日期)。
- **流式**:引擎无流式 API,采用"首段就绪即播放,后续段边合成边入队"的模拟流式方案。

## 测试

### 单元测试 + Widget 冒烟

```bash
flutter test
```

覆盖:归一化(数字/百分比/年份/电话/全角)、分句/长句切块、以及
"输入 → 合成 → 朗读视图高亮推进"的冒烟链路(使用假引擎/假播放器,无需真实模型)。

### Patrol 集成测试(需求 5)

一条命令跑全套并**自动出截图**(推荐;需已连接 Android 设备/模拟器):

```bash
sh scripts/patrol_e2e.sh                   # 全部 7 个套件,截图默认开
sh scripts/patrol_e2e.sh knowledge memory  # 只跑指定套件(名字可省 _test)
sh scripts/patrol_e2e.sh --no-screenshots  # 关截图:测试内不渲染不落盘,跑完卸载
sh scripts/patrol_e2e.sh -d emulator-5554  # 指定设备(不给则自动取第一个 adb 设备)
```

- **截图默认开**,落在 `screenshots/<套件>/<名字>.png`(`.gitignore` 已忽略);
  每个套件的完整输出在 `build/e2e_logs/<套件>.log`;有套件失败时脚本退出码非 0。
- 截图开关在测试侧是 `takeScreenshot` 里的 `--dart-define=E2E_SCREENSHOTS=false`:
  关掉后它**只跳过渲染与落盘,仍会 `pumpAndSettle`** —— 刻意的,开关不该改变测试时序。
- ⚠️ 开截图时脚本自动带 `--no-uninstall`,并在每个套件跑完后**立刻** adb 拉取:
  `android/app/build.gradle.kts` 配了 `clearPackageData = true`(**每轮跑之前**清空应用数据),
  跑完 App 还会被卸载,不"跑一个拉一个"就什么都留不下。
- 截图拉取走 adb,**只支持 Android**;iOS 模拟器需自行从容器目录取。

单独跑某一个套件(不带截图收集):

```bash
dart pub global activate patrol_cli
patrol doctor                       # 校验环境
patrol test -t patrol_test/app_smoke_test.dart       # 合成链路(需 Android 设备/模拟器)
patrol test -t patrol_test/conversation_test.dart    # 对话双模式(音频 + 文本)
patrol test -t patrol_test/settings_test.dart        # 设置两级结构 + 各分类子页 + 清理缓存
patrol test -t patrol_test/knowledge_test.dart       # v1.0.2 知识库:下载嵌入模型 → 导入 → 索引 → 检索试跑
patrol test -t patrol_test/memory_test.dart          # v1.0.2 长期记忆:对话提炼 → 分组管理 → 删除
patrol test -t patrol_test/context_injection_test.dart # v1.0.2 上下文注入 + 未注册说话人零记忆
```

- Android 原生配置:`android/app/build.gradle.kts` 配了 `PatrolJUnitRunner` +
  AndroidX Test Orchestrator;`MainActivityTest.java` 位于
  `android/app/src/androidTest/java/top/ued17/tts/`。
- 测试通过 `patrol_test/test_deps.dart` 注入假下载器/假引擎/假播放器/假嵌入引擎,
  不依赖真实网络与真实模型(嵌入模型也由假下载器按目录声明的**精确体积**落盘,
  以跑通"多文件 raw 下载 → 逐文件体积校验 → 就绪"这条链路)。
- **iOS**:patrol 的 iOS UI 测试目标需在 macOS + Xcode 上配置(骨架见
  `ios/RunnerUITests/RunnerUITests.m`),本仓库已含该文件。

#### 截图

测试内通过 `patrol_test/screenshot_helper.dart` 的 `takeScreenshot(tester, name)`
用 `RepaintBoundary` + `toImage()` 把当前界面保存为 PNG,写入**设备上**的应用文档目录
`.../app_flutter/screenshots/<name>.png`(**默认就截**,`--dart-define=E2E_SCREENSHOTS=false` 关)。

日常直接用 `sh scripts/patrol_e2e.sh` 即可 —— 它会带 `--no-uninstall` 跑、并在每个套件
结束后立刻把图拉到 `screenshots/<套件>/`。手工拉单张:

```bash
patrol test -t patrol_test/app_smoke_test.dart -d emulator-5554 --no-uninstall
# 拉取截图(Windows,包名替换为你的 applicationId)
adb exec-out run-as top.ued17.tts cat app_flutter/screenshots/01_home.png > 01_home.png
```

> `clearPackageData` 会在每次测试前清空应用数据,因此每轮测试的截图是独立的一套;
> 需要保留截图时请使用 `--no-uninstall`(否则测试结束 App 被卸载,截图一并消失)。

## 构建脚本

参考 masrobo neme-ai-app 的 `scripts/` 结构:

```bash
# Android(默认 arm + arm64 APK,可 `--target-platform` 指定)
sh scripts/build-android.sh

# iOS(需 macOS + Xcode;导出 ad-hoc IPA)
bash scripts/build-ios.sh
```

脚本会:清理 build → `flutter build` → 上传蒲公英 → 通知飞书。
蒲公英/飞书凭据已内置默认值(可被环境变量覆盖):
`PGYER_API_KEY` / `FEISHU_ACCESS_TOKEN` / `FEISHU_TEMPLATE_ID` / `BUILD_CHANNEL_SHORTCUT`。
> 注意:凭据位于脚本内,若仓库对外公开请注意轮换。

## 应用图标

- 设计源:`assets/icon/app_icon.svg`(圆角渐变底 + 声波柱 + "TTS" 字样)。
- 1024 PNG:由 SVG 转换生成(`assets/icon/app_icon.png`)。
- 各平台图标:运行 `dart run flutter_launcher_icons` 生成 Android mipmap 与 iOS AppIcon。

## 隐私边界(务必阅读)

**语音识别 / 合成 / 声纹 / 声音克隆 / 文本向量化全部离线**,不联网。
唯一联网的组件是**大模型(LLM)**,由你自己配置 API Key 并自付费用。

但正因为它联网,以下数据会被发送到第三方 LLM 服务商:

1. **当前对话内容**(含最近若干轮原文)。这是从 v1.0.0 起就有的行为。
2. **检索命中的知识库片段**。注入的是**命中的那几段**(不是整库),
   但命中片段同样可能含敏感信息 —— 导入文档前请先想清楚。
3. **关于当前说话人的长期记忆**。这类"事实"是从对话里推断出来的,同样会随提示词发出。
4. **会话摘要**。它是你对话内容的压缩结果。

另有两点需要注意:

- **知识库、长期记忆、会话摘要都以明文存于本地 SQLite**,未加密。本机可读。
- **长期记忆抽取会额外消耗 token**:每次抽取都会把"最近若干轮 + 已有记忆"一起发给模型。
  可在 设置 → 记忆 关闭。

**跨人隔离**:未识别的说话人**既不产生记忆、也不会被注入任何记忆** ——
即使库里存着别人的记忆。这是本版唯一一条真正的隔离保证,并有回归测试守住。
但请注意:**声纹本身不是安全边界**(可重放、可合成、判定是模糊的),
所以涉及敏感信息时不要把它当作唯一门禁。

## 平台说明

- **Android**:applicationId 为 `top.ued17.tts`(注:`top.17ued.tts` 不符合 Android 包名规则
  ——段不能以数字开头,已作此调整);minSdk 提至 23(`record` 包要求,语音对话/克隆用麦克风);
  sherpa-onnx 通过 federated 插件打包原生 `.so`。
  Gradle 依赖在国内网络下的下载问题已通过 `android/settings.gradle.kts` 的阿里云镜像与
  `android/gradle/wrapper/gradle-wrapper.properties` 的腾讯镜像解决。
  设备认证(`local_auth`)另需两处配置,已就位:`AndroidManifest.xml` 的
  `USE_BIOMETRIC` 权限,以及 `MainActivity` 必须继承 **`FlutterFragmentActivity`**
  (BiometricPrompt 要求 FragmentActivity,继承 `FlutterActivity` 会让 `authenticate()`
  直接抛异常、设备认证被判为不可用)。
- **iOS**:bundle id `top.ued17.tts`;deployment target 13+/A12+;Flutter 3.44 使用
  Swift Package Manager 集成插件。`Info.plist` 已加 `NSFaceIDUsageDescription`(设备认证
  用 Face ID 时必需,缺此键会直接失败)。Windows 环境无法构建 iOS,请在 macOS 上执行
  `flutter build ios` / patrol iOS 测试验证。

## 许可

- 应用代码:MIT(见 LICENSE)。
- TTS 模型各自携带许可(见模型目录 `LICENSE` 文件);kokoro 依赖 eSpeak-ng(GPL-3.0),
  商用前请进行法务评估。
