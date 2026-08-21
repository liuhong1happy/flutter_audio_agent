import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Flutter TTS Demo'**
  String get appTitle;

  /// No description provided for @synthesizeTab.
  ///
  /// In zh, this message translates to:
  /// **'合成'**
  String get synthesizeTab;

  /// No description provided for @settingsTab.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTab;

  /// No description provided for @modelsTab.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get modelsTab;

  /// No description provided for @statusReady.
  ///
  /// In zh, this message translates to:
  /// **'已选模型'**
  String get statusReady;

  /// No description provided for @statusNoModel.
  ///
  /// In zh, this message translates to:
  /// **'未选择模型'**
  String get statusNoModel;

  /// No description provided for @statusNotDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'所选模型未下载'**
  String get statusNotDownloaded;

  /// No description provided for @phaseIdle.
  ///
  /// In zh, this message translates to:
  /// **'就绪'**
  String get phaseIdle;

  /// No description provided for @phasePreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备中…'**
  String get phasePreparing;

  /// No description provided for @phaseSynthesizing.
  ///
  /// In zh, this message translates to:
  /// **'合成中…'**
  String get phaseSynthesizing;

  /// 播放中显示当前段/总段数
  ///
  /// In zh, this message translates to:
  /// **'播放中 {current}/{total}'**
  String phasePlaying(int current, int total);

  /// 暂停时显示进度
  ///
  /// In zh, this message translates to:
  /// **'已暂停 {current}/{total}'**
  String phasePaused(int current, int total);

  /// No description provided for @phaseFinished.
  ///
  /// In zh, this message translates to:
  /// **'播放完成'**
  String get phaseFinished;

  /// No description provided for @phaseError.
  ///
  /// In zh, this message translates to:
  /// **'出错'**
  String get phaseError;

  /// No description provided for @pause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get resume;

  /// No description provided for @stop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get stop;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @loadingModel.
  ///
  /// In zh, this message translates to:
  /// **'加载中'**
  String get loadingModel;

  /// No description provided for @inputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入要朗读的文本…'**
  String get inputHint;

  /// No description provided for @emptyTextError.
  ///
  /// In zh, this message translates to:
  /// **'请输入文本'**
  String get emptyTextError;

  /// No description provided for @genericError.
  ///
  /// In zh, this message translates to:
  /// **'发生错误'**
  String get genericError;

  /// No description provided for @goSettings.
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get goSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'TTS 设置'**
  String get settingsTitle;

  /// No description provided for @sectionModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get sectionModel;

  /// No description provided for @noModelDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'尚未下载任何模型'**
  String get noModelDownloaded;

  /// No description provided for @noModelHint.
  ///
  /// In zh, this message translates to:
  /// **'先到模型管理页下载一个模型,再回来选择。'**
  String get noModelHint;

  /// No description provided for @goModel.
  ///
  /// In zh, this message translates to:
  /// **'去下载'**
  String get goModel;

  /// No description provided for @selectModelLabel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get selectModelLabel;

  /// No description provided for @modelSpeakerCount.
  ///
  /// In zh, this message translates to:
  /// **'{name} ({count} 音色)'**
  String modelSpeakerCount(String name, int count);

  /// No description provided for @modelNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择模型,合成前需要先选择。'**
  String get modelNotSelected;

  /// No description provided for @speakerLabel.
  ///
  /// In zh, this message translates to:
  /// **'说话人 (sid {sid})'**
  String speakerLabel(int sid);

  /// speed 为已格式化的语速字符串(如 1.50)
  ///
  /// In zh, this message translates to:
  /// **'语速 {speed}x'**
  String speedLabel(String speed);

  /// No description provided for @silenceLabel.
  ///
  /// In zh, this message translates to:
  /// **'句间静音 {percent}%'**
  String silenceLabel(int percent);

  /// No description provided for @threadLabel.
  ///
  /// In zh, this message translates to:
  /// **'推理线程 {threads}'**
  String threadLabel(int threads);

  /// No description provided for @downloadSource.
  ///
  /// In zh, this message translates to:
  /// **'下载源'**
  String get downloadSource;

  /// No description provided for @mirrorSourceLabel.
  ///
  /// In zh, this message translates to:
  /// **'下载源(国内网络自动回退代理)'**
  String get mirrorSourceLabel;

  /// No description provided for @mirrorAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动(国内代理+直连回退,推荐)'**
  String get mirrorAuto;

  /// No description provided for @mirrorCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义镜像前缀'**
  String get mirrorCustom;

  /// No description provided for @mirrorPrefixLabel.
  ///
  /// In zh, this message translates to:
  /// **'镜像前缀(如 https://ghfast.top/)'**
  String get mirrorPrefixLabel;

  /// No description provided for @autoScroll.
  ///
  /// In zh, this message translates to:
  /// **'自动滚动跟随朗读'**
  String get autoScroll;

  /// No description provided for @modelManageTitle.
  ///
  /// In zh, this message translates to:
  /// **'模型管理'**
  String get modelManageTitle;

  /// mb 为已格式化的 MB 字符串(如 12.3)
  ///
  /// In zh, this message translates to:
  /// **'占用 {mb}MB'**
  String diskUsage(String mb);

  /// No description provided for @clearAll.
  ///
  /// In zh, this message translates to:
  /// **'清理全部缓存(删除所有模型)'**
  String get clearAll;

  /// No description provided for @clearAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'清理全部缓存'**
  String get clearAllTitle;

  /// No description provided for @clearAllConfirm.
  ///
  /// In zh, this message translates to:
  /// **'将删除所有已下载模型与音频缓存,并重置已下载标记。\n此操作不可恢复。'**
  String get clearAllConfirm;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirmClear.
  ///
  /// In zh, this message translates to:
  /// **'确认清理'**
  String get confirmClear;

  /// No description provided for @deleteModel.
  ///
  /// In zh, this message translates to:
  /// **'删除模型'**
  String get deleteModel;

  /// No description provided for @cancelDownload.
  ///
  /// In zh, this message translates to:
  /// **'取消下载'**
  String get cancelDownload;

  /// No description provided for @download.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get download;

  /// No description provided for @bubblesEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'输入文本后点击\"发送\",这里会逐条显示朗读气泡。'**
  String get bubblesEmptyHint;

  /// No description provided for @statsToggle.
  ///
  /// In zh, this message translates to:
  /// **'耗时统计 ▸'**
  String get statsToggle;

  /// No description provided for @statTokenize.
  ///
  /// In zh, this message translates to:
  /// **'分词'**
  String get statTokenize;

  /// No description provided for @statFirstAudio.
  ///
  /// In zh, this message translates to:
  /// **'首词'**
  String get statFirstAudio;

  /// No description provided for @statSynthesis.
  ///
  /// In zh, this message translates to:
  /// **'合成'**
  String get statSynthesis;

  /// No description provided for @statPlayback.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get statPlayback;

  /// No description provided for @statTotal.
  ///
  /// In zh, this message translates to:
  /// **'总'**
  String get statTotal;

  /// 气泡下方耗时统计(各指标为格式化后的时长字符串)
  ///
  /// In zh, this message translates to:
  /// **'分词 {tokenize} · 首词 {first} · 合成 {synthesis} · 播放 {playback} · 总 {total}'**
  String statsLine(
    String tokenize,
    String first,
    String synthesis,
    String playback,
    String total,
  );

  /// No description provided for @streamingEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'输入文本后点击\"合成并播放\",这里会逐句高亮显示朗读进度。'**
  String get streamingEmptyHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
