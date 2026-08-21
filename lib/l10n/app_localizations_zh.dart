// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Flutter TTS Demo';

  @override
  String get synthesizeTab => '合成';

  @override
  String get settingsTab => '设置';

  @override
  String get modelsTab => '模型';

  @override
  String get statusReady => '已选模型';

  @override
  String get statusNoModel => '未选择模型';

  @override
  String get statusNotDownloaded => '所选模型未下载';

  @override
  String get phaseIdle => '就绪';

  @override
  String get phasePreparing => '准备中…';

  @override
  String get phaseSynthesizing => '合成中…';

  @override
  String phasePlaying(int current, int total) {
    return '播放中 $current/$total';
  }

  @override
  String phasePaused(int current, int total) {
    return '已暂停 $current/$total';
  }

  @override
  String get phaseFinished => '播放完成';

  @override
  String get phaseError => '出错';

  @override
  String get pause => '暂停';

  @override
  String get resume => '继续';

  @override
  String get stop => '停止';

  @override
  String get send => '发送';

  @override
  String get loadingModel => '加载中';

  @override
  String get inputHint => '输入要朗读的文本…';

  @override
  String get emptyTextError => '请输入文本';

  @override
  String get genericError => '发生错误';

  @override
  String get goSettings => '去设置';

  @override
  String get settingsTitle => 'TTS 设置';

  @override
  String get sectionModel => '模型';

  @override
  String get noModelDownloaded => '尚未下载任何模型';

  @override
  String get noModelHint => '先到模型管理页下载一个模型,再回来选择。';

  @override
  String get goModel => '去下载';

  @override
  String get selectModelLabel => '选择模型';

  @override
  String modelSpeakerCount(String name, int count) {
    return '$name ($count 音色)';
  }

  @override
  String get modelNotSelected => '未选择模型,合成前需要先选择。';

  @override
  String speakerLabel(int sid) {
    return '说话人 (sid $sid)';
  }

  @override
  String speedLabel(String speed) {
    return '语速 ${speed}x';
  }

  @override
  String silenceLabel(int percent) {
    return '句间静音 $percent%';
  }

  @override
  String threadLabel(int threads) {
    return '推理线程 $threads';
  }

  @override
  String get downloadSource => '下载源';

  @override
  String get mirrorSourceLabel => '下载源(国内网络自动回退代理)';

  @override
  String get mirrorAuto => '自动(国内代理+直连回退,推荐)';

  @override
  String get mirrorCustom => '自定义镜像前缀';

  @override
  String get mirrorPrefixLabel => '镜像前缀(如 https://ghfast.top/)';

  @override
  String get autoScroll => '自动滚动跟随朗读';

  @override
  String get modelManageTitle => '模型管理';

  @override
  String diskUsage(String mb) {
    return '占用 ${mb}MB';
  }

  @override
  String get clearAll => '清理全部缓存(删除所有模型)';

  @override
  String get clearAllTitle => '清理全部缓存';

  @override
  String get clearAllConfirm => '将删除所有已下载模型与音频缓存,并重置已下载标记。\n此操作不可恢复。';

  @override
  String get cancel => '取消';

  @override
  String get confirmClear => '确认清理';

  @override
  String get deleteModel => '删除模型';

  @override
  String get cancelDownload => '取消下载';

  @override
  String get download => '下载';

  @override
  String get bubblesEmptyHint => '输入文本后点击\"发送\",这里会逐条显示朗读气泡。';

  @override
  String get statsToggle => '耗时统计 ▸';

  @override
  String get statTokenize => '分词';

  @override
  String get statFirstAudio => '首词';

  @override
  String get statSynthesis => '合成';

  @override
  String get statPlayback => '播放';

  @override
  String get statTotal => '总';

  @override
  String statsLine(
    String tokenize,
    String first,
    String synthesis,
    String playback,
    String total,
  ) {
    return '分词 $tokenize · 首词 $first · 合成 $synthesis · 播放 $playback · 总 $total';
  }

  @override
  String get streamingEmptyHint => '输入文本后点击\"合成并播放\",这里会逐句高亮显示朗读进度。';
}
