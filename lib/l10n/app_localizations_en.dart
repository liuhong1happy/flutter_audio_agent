// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Flutter TTS Demo';

  @override
  String get synthesizeTab => 'Synthesize';

  @override
  String get settingsTab => 'Settings';

  @override
  String get modelsTab => 'Models';

  @override
  String get statusReady => 'Model ready';

  @override
  String get statusNoModel => 'No model selected';

  @override
  String get statusNotDownloaded => 'Model not downloaded';

  @override
  String get phaseIdle => 'Ready';

  @override
  String get phasePreparing => 'Preparing…';

  @override
  String get phaseSynthesizing => 'Synthesizing…';

  @override
  String phasePlaying(int current, int total) {
    return 'Playing $current/$total';
  }

  @override
  String phasePaused(int current, int total) {
    return 'Paused $current/$total';
  }

  @override
  String get phaseFinished => 'Finished';

  @override
  String get phaseError => 'Error';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get stop => 'Stop';

  @override
  String get send => 'Send';

  @override
  String get loadingModel => 'Loading…';

  @override
  String get inputHint => 'Enter text to read…';

  @override
  String get emptyTextError => 'Please enter text';

  @override
  String get genericError => 'Something went wrong';

  @override
  String get goSettings => 'Go to settings';

  @override
  String get settingsTitle => 'TTS Settings';

  @override
  String get sectionModel => 'Model';

  @override
  String get noModelDownloaded => 'No model downloaded yet';

  @override
  String get noModelHint => 'Download a model first, then select it here.';

  @override
  String get goModel => 'Download';

  @override
  String get selectModelLabel => 'Select model';

  @override
  String modelSpeakerCount(String name, int count) {
    return '$name ($count voices)';
  }

  @override
  String get modelNotSelected =>
      'No model selected. Select one before synthesizing.';

  @override
  String speakerLabel(int sid) {
    return 'Speaker (sid $sid)';
  }

  @override
  String speedLabel(String speed) {
    return 'Speed ${speed}x';
  }

  @override
  String silenceLabel(int percent) {
    return 'Inter-sentence silence $percent%';
  }

  @override
  String threadLabel(int threads) {
    return 'Inference threads $threads';
  }

  @override
  String get downloadSource => 'Download source';

  @override
  String get mirrorSourceLabel => 'Download source (proxy fallback)';

  @override
  String get mirrorAuto => 'Auto (proxy + direct fallback)';

  @override
  String get mirrorCustom => 'Custom mirror prefix';

  @override
  String get mirrorPrefixLabel => 'Mirror prefix (e.g. https://ghfast.top/)';

  @override
  String get autoScroll => 'Auto-scroll while reading';

  @override
  String get modelManageTitle => 'Model management';

  @override
  String diskUsage(String mb) {
    return 'Disk ${mb}MB';
  }

  @override
  String get clearAll => 'Clear all cache (delete all models)';

  @override
  String get clearAllTitle => 'Clear all cache';

  @override
  String get clearAllConfirm =>
      'This deletes all downloaded models and audio cache, and resets download status.\nThis cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirmClear => 'Clear';

  @override
  String get deleteModel => 'Delete model';

  @override
  String get cancelDownload => 'Cancel';

  @override
  String get download => 'Download';

  @override
  String get bubblesEmptyHint =>
      'Enter text and tap Send. Bubbles appear here.';

  @override
  String get statsToggle => 'Stats ▸';

  @override
  String get statTokenize => 'Tokenize';

  @override
  String get statFirstAudio => 'First';

  @override
  String get statSynthesis => 'Synth';

  @override
  String get statPlayback => 'Play';

  @override
  String get statTotal => 'Total';

  @override
  String statsLine(
    String tokenize,
    String first,
    String synthesis,
    String playback,
    String total,
  ) {
    return 'Tokenize $tokenize · First $first · Synth $synthesis · Play $playback · Total $total';
  }

  @override
  String get streamingEmptyHint =>
      'Enter text and tap to synthesize. Segments highlight here.';
}
