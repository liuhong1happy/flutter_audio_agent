# TODO / 待办事项

> 更新日期:2026-08-21

## 一、功能待办

- [ ] **iOS 构建与验证**(需 macOS + Xcode):`flutter build ios`、Patrol iOS 测试(`ios/RunnerUITests` SPM 集成)尚未真机/模拟器验证
- [ ] **iOS 蒲公英上传脚本**完整跑通一次
- [ ] **Android release 正式签名**:当前 `build.gradle.kts` 用 debug 签名,生产发布需生成正式 keystore 并配置 `signingConfig`
- [ ] **下载断点续传**:当前下载失败即重试整包,可支持 Range 断点续传(大模型 100~350MB)
- [ ] **多模型并发下载**体验确认:当前每模型独立 CancelToken,理论上可并发,但 UI 一次一个下载按钮,可考虑下载队列
- [ ] **词级时长的真实时间戳**:当前用"字符权重 ∝ 段时长"启发式,若 sherpa-onnx 后续暴露词级时间戳可替换,提升逐词高亮准确性
- [ ] **i18n 本地化**:界面文案目前硬编码中文,可引入 `flutter_localizations` 支持多语言
- [ ] **设置页"自定义镜像"输入**:当前是固定下拉(ghfast.top),可支持用户手动输入任意前缀
- [ ] **模型校验**:下载后仅校验 bzip2 魔数与文件存在;可进一步对 `model.onnx` 做大小/哈希校验
- [ ] **CI 集成**:可接入 Codemagic/GitHub Actions 自动跑单测 + Patrol + 打 tag 自动打包

## 二、代码审查发现(2026-08-21 首轮审查)

> 本轮已完成 19 个单元测试 + Patrol 冒烟;以下为建议优化/修复项,按严重度排序。

### 2.1 需修复

- [ ] **【Bug】历史恢复的气泡点击"重读"无声音**
  - 位置:`lib/tts/tts_streaming_service.dart` `loadHistory()` + `replayUtterance()`
  - 现象:App 重启后从持久化恢复的历史气泡,`segments` 为空;点击重读时 `_synthesizeSegments` 遍历空列表 → 不产生任何音频
  - 建议:`replayUtterance` 中若 `u.segments` 为空,先用 `_chunker.splitWords(u.normalizedText)` + 分块策略重建 segments/words 再合成

### 2.2 建议清理(死代码)

- [ ] **删除 `replaySegment`**(`lib/tts/tts_streaming_service.dart`)——已被 `replayUtterance` 取代,全工程无引用
- [ ] **删除 `ModelManager.effectiveUrl`**(`lib/data/model_manager.dart`)——已被 `downloadCandidates` 取代,无引用
- [ ] **删除 `TtsStreamingService.segmentWords` 公共 getter**——视图已改用 `utterance.allWords`/`utterance.segmentWords`,该 getter 无外部引用

### 2.3 建议完善

- [ ] **widget 冒烟测试补充"发送后输入框清空"断言**
- [ ] **model_manager 多镜像回退单元测试**:验证候选顺序(手动镜像 → 国内代理 → 直连)、失败自动切换、bzip2 魔数校验拒收错误页
- [ ] **`Utterance` 与 `TtsSettings`/`ModelManager` 的双源状态**(ChangeNotifier + dva store)存在漂移风险,建议后续统一收敛为单一事实源
- [ ] **耗时统计 UI 文案**可考虑在长气泡上折叠/展开,避免占空间
- [ ] **`_buildProgressiveChunks` 与 `_addPatternChunks`** 可加注释说明"首句 1+4+10、后续整句、长句 10"的演进背景(已在设计文档记录,代码注释可同步)
- [ ] **性能**:后台 isolate 每次 `generate` 传回 Float32List 有拷贝开销,长文本可评估 `TransferableTypedData` 优化
