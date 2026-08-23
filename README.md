# flutter_tts_demo

基于 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 的跨平台(Android / iOS)离线文本转语音演示应用。

## 功能

1. **底部 Tab 布局** — 合成 / 对话 / 设置三个平级 Tab,`IndexedStack` 常驻各页,播放中切换不中断。
2. **文本转语音(聊天式界面)** — 底部输入框;每次发送 = 一条气泡(整段文本),正在读的气泡内
   **逐词高亮**(卡拉OK式);点击气泡可重新朗读该条。
3. **统一设置中心(两级)** — 设置页首页为各大类 ListItem(语音合成 / 语音识别 / VAD /
   声纹识别 / 大模型 / 通用),点击进入子页配置各自参数 + **各自模型下载**;通用页含清理缓存。
4. **语音对话(双模式)** — 第 2 Tab「对话」:
   - **音频模式**:语音 → 离线 ASR → 声纹识别 → 在线 LLM → TTS 语音回复,仅显示最后一轮;
   - **文本模式**:打字 → 在线 LLM 纯文本回复(不转 TTS),显示全部历史。
   会话历史为**单一时间线**(多说话人,未知说话人访客模式),存 SQLite 并按时间排序、分页。
5. **声音克隆** — PocketTTS 零样本克隆音(录 3–10s 参考)。
6. **声纹识别** — 3D-Speaker 声纹注册(整页 + 圆形居中录音按钮,支持连续注册多个说话人)/ 识别 / 删除。
7. **多服务商 LLM** — OpenAI 兼容接口,内置 DeepSeek(`deepseek-v4-flash`/`deepseek-v4-pro`)/
   Moonshot(Kimi)/ 智谱(GLM)/ 通义千问(Qwen)预设,可自定义 baseUrl / apiKey / 模型。
8. **历史浏览 + 管理** — 对话页 Header 左侧历史入口,分页「加载更早」;长按气泡删除单条消息。

> **隐私说明**:LLM 是唯一联网组件(OpenAI 兼容第三方服务);ASR/TTS/克隆/声纹/VAD 全部离线。
> API Key 明文存于本地 SharedPreferences(demo 可接受,请勿提交真实 key 到仓库)。

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
| 应用图标 | `assets/icon/app_icon.svg`(含 TTS 信息)→ PNG,`flutter_launcher_icons` 生成各尺寸 |
| 集成测试 | `patrol ^4.9.0` |

> 注:`jieba_flutter` 以硬编码路径 `assets/dict.txt` 通过 `rootBundle` 加载词典,
> 因此仓库内 `assets/` 已复制其 `dict.txt` / `prob_emit.txt`(来源:jieba_flutter 包 assets,Apache-2.0)。

## 内置模型目录

下载前缀(按种类):`tts-models`(TTS/克隆)、`asr-models`(ASR/VAD)、`speaker-recongition-models`(声纹)。

| 模型 | 音色 | 大小 | 采样率 | 说明 |
|---|---|---|---|---|
| vits-piper-zh_CN-xiao_ya-medium-int8 | 1 | ~13MB | 22.05kHz | 默认,最小最快 |
| vits-zh-hf-fanchen-C | 187 | ~114MB | 16kHz | 通用中文多音色 |
| vits-melo-tts-zh_en | 1 | ~159MB | 44.1kHz | 中英混读(MIT) |
| vits-zh-hf-theresa | 804 | ~115MB | 22.05kHz | 音色最多 |
| kokoro-multi-lang-v1_0 | 53 | ~333MB | 24kHz | 最佳中英混读(Apache-2.0) |

国内网络访问 GitHub 较慢时,可在 **TTS 设置 → 下载镜像** 切换镜像前缀。

## 快速开始

```bash
flutter pub get
flutter run            # 需已连接 Android 设备/模拟器(或配置 iOS 模拟器)
```

首次使用:设置 → 语音合成 下载 `Piper 晓雅(int8)` 并选择 → 主页输入文本合成;
对话功能在 设置 → 对话初始化(或对话页一键下载三件套)后使用。

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
├── data/                         # 数据处理
│   ├── models/                   # TtsModel / TtsSettings / ConversationMessage
│   ├── dva/                      # flutter_dva:app_models + app_dva
│   └── (model_catalog / downloader / manager / resolver / extractor / app_paths / conversation_store)
├── utils/                        # 其他帮助方法 + 服务 + 引擎
│   ├── engines/                  # tts / vad / asr / speaker / pocket 引擎
│   └── (services / 文本管线 / wav / isolate_bridge / 播放器 / llm / mic)
└── l10n/                         # gen-l10n 生成(勿手改)
test/                             # 单元测试 + widget 冒烟(fakes 见 test/support/)
patrol_test/                      # Patrol 集成测试(app_smoke / conversation / settings)
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

```bash
dart pub global activate patrol_cli
patrol doctor                       # 校验环境
patrol test -t patrol_test/app_smoke_test.dart       # 合成链路(需 Android 设备/模拟器)
patrol test -t patrol_test/conversation_test.dart    # 对话双模式(音频 + 文本)
patrol test -t patrol_test/settings_test.dart        # 设置两级结构 + 各分类子页 + 清理缓存
```

- Android 原生配置:`android/app/build.gradle.kts` 配了 `PatrolJUnitRunner` +
  AndroidX Test Orchestrator;`MainActivityTest.java` 位于
  `android/app/src/androidTest/java/top/ued17/tts/`。
- 测试通过 `patrol_test/test_deps.dart` 注入假下载器/假引擎/假播放器,不依赖真实网络与模型。
- **iOS**:patrol 的 iOS UI 测试目标需在 macOS + Xcode 上配置(骨架见
  `ios/RunnerUITests/RunnerUITests.m`),本仓库已含该文件。

#### 截图

测试内通过 `patrol_test/screenshot_helper.dart` 的 `takeScreenshot(tester, name)`
用 `RepaintBoundary` + `toImage()` 把当前界面保存为 PNG,写入应用文档目录
`.../app_flutter/screenshots/<name>.png`。跑完测试后用 `--no-uninstall` 保留 App 再拉取:

```bash
patrol test -t patrol_test/app_smoke_test.dart -d emulator-5554 --no-uninstall
# 拉取截图(Windows,替换包名为你的 applicationId)
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

## 平台说明

- **Android**:applicationId 为 `top.ued17.tts`(注:`top.17ued.tts` 不符合 Android 包名规则
  ——段不能以数字开头,已作此调整);minSdk 提至 23(`record` 包要求,语音对话/克隆用麦克风);
  sherpa-onnx 通过 federated 插件打包原生 `.so`。
  Gradle 依赖在国内网络下的下载问题已通过 `android/settings.gradle.kts` 的阿里云镜像与
  `android/gradle/wrapper/gradle-wrapper.properties` 的腾讯镜像解决。
- **iOS**:bundle id `top.ued17.tts`;deployment target 13+/A12+;Flutter 3.44 使用
  Swift Package Manager 集成插件。Windows 环境无法构建 iOS,请在 macOS 上执行
  `flutter build ios` / patrol iOS 测试验证。

## 许可

- 应用代码:MIT(见 LICENSE)。
- TTS 模型各自携带许可(见模型目录 `LICENSE` 文件);kokoro 依赖 eSpeak-ng(GPL-3.0),
  商用前请进行法务评估。
