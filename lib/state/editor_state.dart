import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' show Player, Media;
import 'package:uuid/uuid.dart';

import '../engine/audio_server.dart';
import '../engine/exporter.dart';
import '../engine/ffmpeg.dart';
import '../engine/frame_server.dart';
import '../io/dal_file.dart';
import '../io/media_resolver.dart';
import '../models/model.dart';
import 'settings.dart';

const _uuid = Uuid();
String newId() => _uuid.v4().substring(0, 8);

/// One undo step = a serialized project snapshot.
class _UndoStep {
  final String label;
  final String json;
  _UndoStep(this.label, this.json);
}

class EditorState extends ChangeNotifier {
  Settings settings;

  Project project = Project(name: 'Untitled');
  String? projectPath; // .dal path
  String projectDir = '';
  bool dirty = false;
  MediaResolver? resolver;

  late FrameServer frameServer;
  late AudioServer audioServer;
  late Exporter exporter;
  Player? audioPlayer;

  // selection
  final Set<String> selectedClips = {};
  String? selectedAssetId;
  String? get selectedClipId => selectedClips.length == 1
      ? selectedClips.first
      : null;

  // playback
  String activeSequenceId = '';
  int playhead = 0;
  bool playing = false;
  double playRate = 0; // signed multiplier; 0 = paused
  int? inPoint, outPoint;
  bool fullscreenPreview = false;
  final frameImage = ValueNotifier<ui.Image?>(null);
  int? displayedFrame;
  final Set<int> _decoding = {};
  final Map<int, ui.Image> _imageCache = {};
  final List<int> _imageLru = [];

  // ui
  double timelineZoom = 14; // px per second multiplier base (see view)
  int timelineScroll = 0;
  String tool = 'select'; // select, razor, ripple, slip, slide
  String? statusMessage;
  Timer? _playTimer;
  Timer? _autosave;
  final List<_UndoStep> _undo = [];
  final List<_UndoStep> _redo = [];
  List<String> clipboard = []; // serialized clips
  final Map<String, Uint8List> _thumbCache = {};
  final Map<String, List<double>> _waveCache = {};
  final Set<String> offlineAssets = {};
  int previewW = 0, previewH = 0;

  List<String> get undoLabels => _undo.map((e) => e.label).toList();
  List<String> get redoLabels => _redo.map((e) => e.label).toList();

  EditorState(this.settings) {
    FFmpeg.ffmpegPath = settings.ffmpegPath;
    FFmpeg.ffprobePath = settings.ffprobePath;
    _initServers();
    _newProject();
    _autosave =
        Timer.periodic(Duration(seconds: settings.autosaveSec), (_) => _autoSave());
  }

  Sequence? get sequence => project.sequenceById(activeSequenceId);
  double get fps => project.fpsValue;

  String get displayTime {
    final f = playhead;
    final t = Duration(milliseconds: (f / fps * 1000).round());
    final ff = (f % fps.round()).toString().padLeft(2, '0');
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.inHours)}:${two(t.inMinutes % 60)}:${two(t.inSeconds % 60)}:$ff';
  }

  // ------------------------------------------------------------------
  // project lifecycle
  // ------------------------------------------------------------------

  bool _serversReady = false;

  void _newProject() {
    project = Project(name: 'Untitled', fps: const Rational(60, 1));
    final seq = Sequence(id: newId(), name: 'Sequence 1');
    seq.tracks.addAll([
      Track(id: newId(), kind: TrackKind.video, name: 'V3'),
      Track(id: newId(), kind: TrackKind.video, name: 'V2'),
      Track(id: newId(), kind: TrackKind.video, name: 'V1'),
      Track(id: newId(), kind: TrackKind.audio, name: 'A1'),
      Track(id: newId(), kind: TrackKind.audio, name: 'A2'),
    ]);
    project.sequences.add(seq);
    project.mainSequenceId = seq.id;
    activeSequenceId = seq.id;
    projectPath = null;
    projectDir = '';
    dirty = false;
    _undo.clear();
    _redo.clear();
    selectedClips.clear();
    playhead = 0;
    if (_serversReady) {
      _rebuildServers();
    } else {
      _serversReady = true;
    }
    notifyListeners();
  }

  void newProject() {
    stopPlayback();
    _newProject();
  }

  Future<void> openProject(String path) async {
    stopPlayback();
    try {
      final p = await DalFile.read(path);
      project = p;
      projectPath = path;
      projectDir = File(path).parent.path;
      resolver = MediaResolver(projectDir);
      offlineAssets.clear();
      offlineAssets.addAll(await resolver!.resolveAll(p));
      activeSequenceId = p.mainSequenceId;
      if (p.sequenceById(activeSequenceId) == null &&
          p.sequences.isNotEmpty) {
        activeSequenceId = p.sequences.first.id;
      }
      playhead = 0;
      dirty = false;
      _undo.clear();
      _redo.clear();
      selectedClips.clear();
      _thumbCache.clear();
      _waveCache.clear();
      _rebuildServers();
      _precacheMedia();
      notifyListeners();
    } catch (e) {
      statusMessage = 'Open failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Adopt an imported project (e.g. from .kdenlive). [sourcePath] is the
  /// original file; media resolves relative to its directory.
  void loadImportedProject(Project p, String sourcePath) {
    stopPlayback();
    project = p;
    projectDir = File(sourcePath).parent.path;
    resolver = MediaResolver(projectDir);
    projectPath = null;
    for (final a in p.assets) {
      if (a.relPath != null) {
        p.resolvedPaths[a.id] = resolver!.toAbsolute(a.relPath!);
      }
    }
    resolver!.resolveAll(p).then((missing) {
      offlineAssets
        ..clear()
        ..addAll(missing);
      notifyListeners();
    });
    activeSequenceId = p.mainSequenceId.isNotEmpty
        ? p.mainSequenceId
        : (p.sequences.isNotEmpty ? p.sequences.first.id : '');
    playhead = 0;
    dirty = true;
    _undo.clear();
    _redo.clear();
    selectedClips.clear();
    _thumbCache.clear();
    _waveCache.clear();
    _rebuildServers();
    _precacheMedia();
    notifyListeners();
  }

  Future<void> saveProject([String? path]) async {
    final target = path ?? projectPath;
    if (target == null) return;
    await DalFile.write(target, project);
    projectPath = target;
    projectDir = File(target).parent.path;
    resolver ??= MediaResolver(projectDir);
    dirty = false;
    statusMessage = 'Saved $target';
    notifyListeners();
  }

  void _autoSave() async {
    if (!dirty || projectPath == null) return;
    try {
      await DalFile.write('$projectPath.autosave.dal', project);
    } catch (_) {}
  }

  void _initServers() {
    resolver ??= MediaResolver(
        projectDir.isEmpty ? Directory.current.path : projectDir);
    frameServer = FrameServer(() => project, () => resolver!,
        scale: settings.previewScale, useProxies: settings.useProxies)
      ..maxCacheMb = settings.cacheMb;
    audioServer = AudioServer(() => project, () => resolver!);
    exporter = Exporter(() => project, () => resolver!);
    audioPlayer = Player();
  }

  void _rebuildServers() {
    resolver ??= MediaResolver(
        projectDir.isEmpty ? Directory.current.path : projectDir);
    try {
      frameServer.dispose();
      audioServer.dispose();
    } catch (_) {}
    frameServer = FrameServer(() => project, () => resolver!,
        scale: settings.previewScale, useProxies: settings.useProxies)
      ..maxCacheMb = settings.cacheMb;
    audioServer = AudioServer(() => project, () => resolver!);
    exporter = Exporter(() => project, () => resolver!);
    audioPlayer?.dispose();
    audioPlayer = Player();
    frameImage.value = null;
    displayedFrame = null;
  }

  // ------------------------------------------------------------------
  // undo / redo
  // ------------------------------------------------------------------

  void pushUndo(String label) {
    _undo.add(_UndoStep(label, jsonEncode(project.toJson())));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  /// Run [mut] inside an undo step. Marks dirty + notifies.
  void edit(String label, void Function() mut) {
    pushUndo(label);
    mut();
    _afterEdit();
  }

  /// For continuous drags: capture snapshot once, then apply mutations
  /// without pushing further steps until [endGesture].
  void beginGesture(String label) => pushUndo(label);
  void duringGesture() {
    _afterEdit();
  }
  void endGesture() => _afterEdit();

  void _afterEdit() {
    dirty = true;
    frameServer.invalidate();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    _redo.add(_UndoStep(s.label, jsonEncode(project.toJson())));
    _restore(s.json);
    statusMessage = 'Undo ${s.label}';
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final s = _redo.removeLast();
    _undo.add(_UndoStep(s.label, jsonEncode(project.toJson())));
    _restore(s.json);
    statusMessage = 'Redo ${s.label}';
    notifyListeners();
  }

  void _restore(String json) {
    final rp = project.resolvedPaths;
    project = Project.fromJson(jsonDecode(json) as Map<String, dynamic>);
    project.resolvedPaths = rp;
    selectedClips.removeWhere((id) => !_clipExists(id));

    dirty = true;
    notifyListeners();
  }

  bool _clipExists(String id) {
    for (final s in project.sequences) {
      for (final t in s.tracks) {
        if (t.clips.any((c) => c.id == id)) return true;
      }
    }
    return false;
  }

  // ------------------------------------------------------------------
  // media import
  // ------------------------------------------------------------------

  Future<MediaAsset?> importFile(String path,
      {void Function(String)? onStatus}) async {
    resolver ??= MediaResolver(projectDir.isEmpty ? File(path).parent.path : projectDir);
    onStatus?.call('Probing $path');
    final probe = await FFmpeg.probe(path);
    if (probe == null) {
      statusMessage = 'ffprobe failed on $path';
      notifyListeners();
      return null;
    }
    final info = FFmpeg.parseProbe(probe);
    if (info == null) return null;
    final stat = await File(path).stat();
    onStatus?.call('Hashing $path');
    final hash = await MediaResolver.hashFile(path);
    final type = info.hasVideo
        ? AssetType.video
        : (info.hasAudio ? AssetType.audio : AssetType.image);
    final asset = MediaAsset(
      id: newId(),
      type: type,
      name: path.split('/').last,
      relPath: resolver!.toRelative(path),
      fileName: path.split('/').last,
      hash: hash,
      fileSize: stat.size,
      durationSec: info.duration,
      width: info.width,
      height: info.height,
      fps: info.fps,
      sampleRate: info.sampleRate,
      channels: info.channels,
      hasVideo: info.hasVideo,
      hasAudio: info.hasAudio,
    );
    project.resolvedPaths[asset.id] = path;
    project.assets.add(asset);
    dirty = true;
    notifyListeners();
    _cacheThumb(asset, path);
    _cacheWave(asset, path);
    return asset;
  }

  MediaAsset addColorClip(String name, String color) {
    final a = MediaAsset(
        id: newId(),
        type: AssetType.color,
        name: name,
        color: color,
        durationSec: 5,
        hasVideo: true);
    project.assets.add(a);
    dirty = true;
    notifyListeners();
    return a;
  }

  MediaAsset addTitleClip(String name, Map<String, dynamic> title) {
    final a = MediaAsset(
        id: newId(),
        type: AssetType.title,
        name: name,
        title: title,
        durationSec: 5,
        hasVideo: true);
    project.assets.add(a);
    dirty = true;
    notifyListeners();
    return a;
  }

  Sequence newSequence({String? name}) {
    final seq = Sequence(
        id: newId(),
        name: name ?? 'Sequence ${project.sequences.length + 1}');
    seq.tracks.addAll([
      Track(id: newId(), kind: TrackKind.video, name: 'V2'),
      Track(id: newId(), kind: TrackKind.video, name: 'V1'),
      Track(id: newId(), kind: TrackKind.audio, name: 'A1'),
    ]);
    project.sequences.add(seq);
    // create a bin asset for it so it can be dragged into other timelines
    project.assets.add(MediaAsset(
        id: newId(),
        type: AssetType.sequence,
        name: seq.name,
        sequenceId: seq.id,
        durationSec: 0,
        hasVideo: true,
        hasAudio: true));
    dirty = true;
    notifyListeners();
    return seq;
  }

  void openSequence(String id) {
    if (project.sequenceById(id) == null) return;
    stopPlayback();
    activeSequenceId = id;
    playhead = 0;
    frameServer.invalidate(hard: true);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // thumbnails / waveforms
  // ------------------------------------------------------------------

  Uint8List? thumb(String assetId) => _thumbCache[assetId];
  List<double>? wave(String assetId) => _waveCache[assetId];

  void _precacheMedia() {
    for (final a in project.assets) {
      if (a.relPath == null) continue;
      final p = project.resolvedPaths[a.id];
      if (p != null) {
        _cacheThumb(a, p);
        _cacheWave(a, p);
      }
    }
  }

  Future<void> _cacheThumb(MediaAsset a, String path) async {
    if (!a.hasVideo || _thumbCache.containsKey(a.id)) return;
    final t = await FFmpeg.thumbnail(path, a.durationSec * 0.1, 240);
    if (t != null) {
      _thumbCache[a.id] = Uint8List.fromList(t);
      notifyListeners();
    }
  }

  Future<void> _cacheWave(MediaAsset a, String path) async {
    if (!a.hasAudio || _waveCache.containsKey(a.id)) return;
    final w = await FFmpeg.waveform(path);
    if (w != null) {
      _waveCache[a.id] = w;
      notifyListeners();
    }
  }

  /// Timeline filmstrip: several thumbs per clip, cached per asset+index.
  final Map<String, Map<int, Uint8List>> _stripCache = {};
  Uint8List? stripThumb(String assetId, int index) => _stripCache[assetId]?[index];
  void requestStripThumb(MediaAsset a, int index) {
    final path = project.resolvedPaths[a.id];
    if (path == null || !a.hasVideo) return;
    final m = _stripCache.putIfAbsent(a.id, () => {});
    if (m.containsKey(index)) return;
    m[index] = Uint8List(0); // placeholder while loading
    final pos = a.durationSec * (index + 0.5) / 6.0;
    FFmpeg.thumbnail(path, pos, 160).then((t) {
      if (t != null) {
        m[index] = Uint8List.fromList(t);
        notifyListeners();
      } else {
        m.remove(index);
      }
    });
  }

  // ------------------------------------------------------------------
  // playback
  // ------------------------------------------------------------------

  int get seqDuration => sequence?.duration ?? 0;

  void seek(int frame, {bool silent = false}) {
    final d = seqDuration;
    playhead = frame.clamp(0, d == 0 ? 0 : d);
    if (!silent) _showFrame(playhead);
    notifyListeners();
  }

  void seekSeconds(double s) => seek((s * fps).round());

  void togglePlay() {
    if (playing) {
      stopPlayback();
    } else {
      play();
    }
  }

  Future<void> play({double rate = 1}) async {
    final seq = sequence;
    if (seq == null) return;
    stopPlayback(notify: false);
    playing = true;
    playRate = rate;
    frameServer.ensure(seq, playhead);
    if (rate == 1.0 && audioServer != null && audioPlayer != null) {
      final url = await audioServer!.start(seq, playhead);
      if (url.isNotEmpty) {
        await audioPlayer!.open(Media(url), play: true);
      }
    }
    _startPlayTimer();
    notifyListeners();
  }

  void stopPlayback({bool notify = true}) {
    _playTimer?.cancel();
    _playTimer = null;
    playing = false;
    playRate = 0;
    audioPlayer?.stop();
    audioServer.stop();
    if (notify) {
      _showFrame(playhead);
      notifyListeners();
    }
  }

  void _startPlayTimer() {
    final interval = Duration(milliseconds: max(8, (1000 / fps).round()));
    var last = DateTime.now();
    var acc = 0.0;
    _playTimer = Timer.periodic(interval, (_) {
      final now = DateTime.now();
      acc += now.difference(last).inMilliseconds / 1000 * playRate.abs();
      last = now;
      final steps = acc.floor();
      if (steps <= 0) return;
      acc -= steps;
      final dir = playRate >= 0 ? 1 : -1;
      var advanced = false;
      for (var i = 0; i < steps; i++) {
        final next = playhead + dir;
        if (next < 0 || next >= seqDuration) {
          stopPlayback();
          break;
        }
        // only advance if frame cached (or audio-only mode)
        if (frameServer.hasFrame(next) || dir < 0) {
          playhead = next;
          advanced = true;
        } else {
          // renderer behind: hold position, keep consuming
          frameServer.ensure(sequence!, playhead);
          break;
        }
      }
      if (advanced) {
        _showFrame(playhead);
        notifyListeners();
      }
    });
  }

  void _showFrame(int frame) {
    final seq = sequence;
    if (seq == null) return;
    final fs = frameServer;
    fs.ensure(seq, frame);
    final jpg = fs.cached(frame);
    if (jpg != null) _decodeToImage(frame, jpg);
    displayedFrame = frame;
  }

  void _decodeToImage(int frame, Uint8List jpg) async {
    if (_imageCache.containsKey(frame)) {
      frameImage.value = _imageCache[frame];
      return;
    }
    if (_decoding.contains(frame)) return;
    _decoding.add(frame);
    try {
      final codec = await ui.instantiateImageCodec(jpg);
      final fi = await codec.getNextFrame();
      _imageCache[frame] = fi.image;
      _imageLru.add(frame);
      if (_imageLru.length > 300) {
        final old = _imageLru.removeAt(0);
        _imageCache.remove(old)?.dispose();
      }
      if (displayedFrame == frame || frame == playhead) {
        frameImage.value = fi.image;
      }
    } catch (_) {
    } finally {
      _decoding.remove(frame);
    }
  }

  /// Frames the frame-server has for the playhead.
  Uint8List? frameAt(int f) => frameServer.cached(f);



  // ------------------------------------------------------------------
  // selection + editing helpers (thin wrappers that push undo)
  // ------------------------------------------------------------------

  void selectClip(String id, {bool add = false}) {
    if (!add) selectedClips.clear();
    selectedClips.add(id);
    notifyListeners();
  }

  void clearSelection() {
    selectedClips.clear();
    notifyListeners();
  }

  Clip? clipById(String id) {
    for (final s in project.sequences) {
      for (final t in s.tracks) {
        for (final c in t.clips) {
          if (c.id == id) return c;
        }
      }
    }
    return null;
  }

  Track? trackOfClip(String id) {
    final seq = sequence;
    if (seq == null) return null;
    for (final t in seq.tracks) {
      if (t.clips.any((c) => c.id == id)) return t;
    }
    return null;
  }

  void status(String m) {
    statusMessage = m;
    notifyListeners();
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _autosave?.cancel();
    frameServer.dispose();
    audioServer.dispose();
    audioPlayer?.dispose();
    super.dispose();
  }
}
