import 'dart:convert';
import 'dart:io';

/// Persisted app settings, stored as JSON in the platform config dir.
class Settings {
  String ffmpegPath;
  String ffprobePath;
  double previewScale; // 0.25, 0.5, 1.0
  int cacheMb;
  bool useProxies;
  int proxyWidth;
  bool snapping;
  int snapThresholdPx;
  int autosaveSec;
  bool autoGenerateProxies;
  String theme; // 'dark'
  String accent; // hex
  bool audioScrub;
  int defaultTransitionFrames;
  String exportDir;
  String layout; // json of dock layout
  Map<String, String> shortcuts; // command -> key combo string

  Settings({
    this.ffmpegPath = 'ffmpeg',
    this.ffprobePath = 'ffprobe',
    this.previewScale = 0.5,
    this.cacheMb = 2048,
    this.useProxies = false,
    this.proxyWidth = 960,
    this.snapping = true,
    this.snapThresholdPx = 12,
    this.autosaveSec = 60,
    this.autoGenerateProxies = false,
    this.theme = 'dark',
    this.accent = '#e8b32c',
    this.audioScrub = false,
    this.defaultTransitionFrames = 24,
    this.exportDir = '',
    this.layout = '',
    Map<String, String>? shortcuts,
  }) : shortcuts = shortcuts ?? {};

  static File _file() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Platform.isWindows
        ? '${Platform.environment['APPDATA']}\\dartalive'
        : '$home/.config/dartalive';
    Directory(dir).createSync(recursive: true);
    return File('$dir/settings.json');
  }

  static Settings load() {
    try {
      final j = jsonDecode(_file().readAsStringSync()) as Map<String, dynamic>;
      return Settings.fromJson(j);
    } catch (_) {
      return Settings();
    }
  }

  Future<void> save() async {
    await _file().writeAsString(
        const JsonEncoder.withIndent('  ').convert(toJson()));
  }

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        ffmpegPath: j['ffmpeg'] as String? ?? 'ffmpeg',
        ffprobePath: j['ffprobe'] as String? ?? 'ffprobe',
        previewScale: (j['previewScale'] as num?)?.toDouble() ?? 0.5,
        cacheMb: j['cacheMb'] as int? ?? 2048,
        useProxies: j['useProxies'] as bool? ?? false,
        proxyWidth: j['proxyWidth'] as int? ?? 960,
        snapping: j['snapping'] as bool? ?? true,
        snapThresholdPx: j['snapPx'] as int? ?? 12,
        autosaveSec: j['autosave'] as int? ?? 60,
        autoGenerateProxies: j['autoProxy'] as bool? ?? false,
        theme: j['theme'] as String? ?? 'dark',
        accent: j['accent'] as String? ?? '#e8b32c',
        audioScrub: j['audioScrub'] as bool? ?? false,
        defaultTransitionFrames: j['defTrans'] as int? ?? 24,
        exportDir: j['exportDir'] as String? ?? '',
        layout: j['layout'] as String? ?? '',
        shortcuts: (j['shortcuts'] as Map?)
                ?.map((k, v) => MapEntry('$k', '$v')) ??
            {},
      );

  Map<String, dynamic> toJson() => {
        'ffmpeg': ffmpegPath,
        'ffprobe': ffprobePath,
        'previewScale': previewScale,
        'cacheMb': cacheMb,
        'useProxies': useProxies,
        'proxyWidth': proxyWidth,
        'snapping': snapping,
        'snapPx': snapThresholdPx,
        'autosave': autosaveSec,
        'autoProxy': autoGenerateProxies,
        'theme': theme,
        'accent': accent,
        'audioScrub': audioScrub,
        'defTrans': defaultTransitionFrames,
        'exportDir': exportDir,
        'layout': layout,
        'shortcuts': shortcuts,
      };
}
