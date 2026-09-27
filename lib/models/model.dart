import 'dart:convert';

/// Core project model. Times on the timeline are integer frames at the
/// sequence's frame rate. Source clip in/out points are stored in seconds
/// because FFmpeg seeks by time anyway.

class Rational {
  final int num;
  final int den;
  const Rational(this.num, this.den);
  double get value => num / den;
  factory Rational.fromJson(Map<String, dynamic> j) =>
      Rational(j['n'] as int, j['d'] as int);
  Map<String, dynamic> toJson() => {'n': num, 'd': den};
  @override
  String toString() => '$num/$den';
}

enum TrackKind { video, audio }

enum AssetType { video, audio, image, color, title, sequence }

enum InterpMode { linear, hold }

class Keyframe {
  int frame; // local clip frame
  double value;
  InterpMode interp;
  Keyframe(this.frame, this.value, {this.interp = InterpMode.linear});
  factory Keyframe.fromJson(Map<String, dynamic> j) => Keyframe(
        j['f'] as int,
        (j['v'] as num).toDouble(),
        interp: InterpMode.values[j['i'] as int? ?? 0],
      );
  Map<String, dynamic> toJson() =>
      {'f': frame, 'v': value, 'i': interp.index};
}

/// Evaluates a (possibly keyframed) parameter list at a local frame.
double evalKeyframes(List<Keyframe>? keys, int frame, double fallback) {
  if (keys == null || keys.isEmpty) return fallback;
  if (keys.length == 1 || frame <= keys.first.frame) return keys.first.value;
  if (frame >= keys.last.frame) return keys.last.value;
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i];
    final b = keys[i + 1];
    if (frame >= a.frame && frame <= b.frame) {
      if (a.interp == InterpMode.hold || a.frame == b.frame) return a.value;
      final t = (frame - a.frame) / (b.frame - a.frame);
      return a.value + (b.value - a.value) * t;
    }
  }
  return keys.last.value;
}

/// Turns a keyframe list into a piecewise-linear ffmpeg expression over the
/// local clip time variable `t` (seconds). Returns null when static.
String? keyframesToExpr(List<Keyframe>? keys, double fps, double staticVal) {
  if (keys == null || keys.length < 2) return null;
  // Build nested if(between(t,...)) expression.
  String seg(double v) => v.toStringAsFixed(6);
  String expr = seg(keys.last.value);
  for (var i = keys.length - 2; i >= 0; i--) {
    final a = keys[i];
    final b = keys[i + 1];
    final t0 = a.frame / fps;
    final t1 = b.frame / fps;
    String piece;
    if (a.interp == InterpMode.hold || t1 <= t0) {
      piece = seg(a.value);
    } else {
      // linear ramp between t0 and t1
      piece =
          '(${seg(a.value)}+(${seg(b.value)}-(${seg(a.value)}))*(t-${t0.toStringAsFixed(6)})/${(t1 - t0).toStringAsFixed(6)})';
    }
    expr =
        'if(lt(t,${t1.toStringAsFixed(6)}),$piece,$expr)';
  }
  return expr;
}

class ClipEffect {
  String id;
  String effectId;
  bool enabled;
  Map<String, dynamic> values;
  Map<String, List<Keyframe>> keyframes;
  ClipEffect({
    required this.id,
    required this.effectId,
    this.enabled = true,
    Map<String, dynamic>? values,
    Map<String, List<Keyframe>>? keyframes,
  })  : values = values ?? {},
        keyframes = keyframes ?? {};

  double numVal(String k, double def) {
    final v = values[k];
    if (v is num) return v.toDouble();
    return def;
  }

  String strVal(String k, String def) {
    final v = values[k];
    if (v is String) return v;
    return def;
  }

  double at(String k, int localFrame, double fps, double def) =>
      evalKeyframes(keyframes[k], localFrame, numVal(k, def));

  factory ClipEffect.fromJson(Map<String, dynamic> j) => ClipEffect(
        id: j['id'] as String,
        effectId: j['e'] as String,
        enabled: j['on'] as bool? ?? true,
        values:
            (j['v'] as Map?)?.map((k, v) => MapEntry(k as String, v)) ?? {},
        keyframes: (j['k'] as Map?)?.map((k, v) => MapEntry(
                k as String,
                (v as List)
                    .map((e) => Keyframe.fromJson(e as Map<String, dynamic>))
                    .toList())) ??
            {},
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'e': effectId,
        if (!enabled) 'on': enabled,
        'v': values,
        if (keyframes.isNotEmpty)
          'k': keyframes.map(
              (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList())),
      };

  ClipEffect clone(String newId) => ClipEffect.fromJson(
      jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>)
    ..id = newId;
}

enum TransitionKind {
  dissolve,
  wipeLeft,
  wipeRight,
  wipeUp,
  wipeDown,
  slideLeft,
  slideRight,
  slideUp,
  slideDown,
  circle,
  radial,
  pixelize,
  fadeBlack,
  fadeWhite,
}

class ClipTransition {
  TransitionKind kind;
  int duration; // frames
  ClipTransition({this.kind = TransitionKind.dissolve, this.duration = 12});
  factory ClipTransition.fromJson(Map<String, dynamic> j) => ClipTransition(
        kind: TransitionKind.values[j['k'] as int? ?? 0],
        duration: j['d'] as int? ?? 12,
      );
  Map<String, dynamic> toJson() => {'k': kind.index, 'd': duration};
}

class Clip {
  String id;
  String assetId;
  int position; // timeline frames
  int duration; // timeline frames
  double offsetSec; // source in-point, seconds
  double speed;
  bool enabled;
  String? name;
  String? linkGroup; // links audio+video clips for selection
  ClipTransition? transition; // head transition overlapping previous clip
  List<ClipEffect> effects;

  Clip({
    required this.id,
    required this.assetId,
    required this.position,
    required this.duration,
    this.offsetSec = 0,
    this.speed = 1.0,
    this.enabled = true,
    this.name,
    this.linkGroup,
    this.transition,
    List<ClipEffect>? effects,
  }) : effects = effects ?? [];

  int get end => position + duration;

  /// Seconds of source media consumed by this clip.
  double sourceSpan(double projectFps) => duration / projectFps * speed;
  double sourceOut(double projectFps) => offsetSec + sourceSpan(projectFps);

  factory Clip.fromJson(Map<String, dynamic> j) => Clip(
        id: j['id'] as String,
        assetId: j['a'] as String,
        position: j['p'] as int,
        duration: j['d'] as int,
        offsetSec: (j['o'] as num?)?.toDouble() ?? 0,
        speed: (j['s'] as num?)?.toDouble() ?? 1.0,
        enabled: j['on'] as bool? ?? true,
        name: j['n'] as String?,
        linkGroup: j['g'] as String?,
        transition: j['t'] == null
            ? null
            : ClipTransition.fromJson(j['t'] as Map<String, dynamic>),
        effects: (j['fx'] as List?)
                ?.map((e) => ClipEffect.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'a': assetId,
        'p': position,
        'd': duration,
        if (offsetSec != 0) 'o': offsetSec,
        if (speed != 1.0) 's': speed,
        if (!enabled) 'on': enabled,
        if (name != null) 'n': name,
        if (linkGroup != null) 'g': linkGroup,
        if (transition != null) 't': transition!.toJson(),
        if (effects.isNotEmpty)
          'fx': effects.map((e) => e.toJson()).toList(),
      };

  Clip clone(String newId) => Clip.fromJson(
      jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>)
    ..id = newId;
}

class Track {
  String id;
  TrackKind kind;
  String name;
  bool muted;
  bool hidden;
  bool locked;
  double gain; // linear
  double pan; // -1..1
  List<Clip> clips;

  Track({
    required this.id,
    required this.kind,
    String? name,
    this.muted = false,
    this.hidden = false,
    this.locked = false,
    this.gain = 1.0,
    this.pan = 0,
    List<Clip>? clips,
  })  : name = name ?? '',
        clips = clips ?? [];

  List<Clip> get sorted =>
      List.of(clips)..sort((a, b) => a.position.compareTo(b.position));

  int get end =>
      clips.fold(0, (m, c) => c.end > m ? c.end : m);

  /// Clip covering [frame], if any.
  Clip? clipAt(int frame) {
    for (final c in clips) {
      if (frame >= c.position && frame < c.end) return c;
    }
    return null;
  }

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        kind: TrackKind.values[j['k'] as int],
        name: j['n'] as String? ?? '',
        muted: j['m'] as bool? ?? false,
        hidden: j['h'] as bool? ?? false,
        locked: j['l'] as bool? ?? false,
        gain: (j['g'] as num?)?.toDouble() ?? 1.0,
        pan: (j['pn'] as num?)?.toDouble() ?? 0,
        clips: (j['c'] as List?)
                ?.map((e) => Clip.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'k': kind.index,
        if (name.isNotEmpty) 'n': name,
        if (muted) 'm': muted,
        if (hidden) 'h': hidden,
        if (locked) 'l': locked,
        if (gain != 1.0) 'g': gain,
        if (pan != 0) 'pn': pan,
        'c': clips.map((e) => e.toJson()).toList(),
      };
}

class Marker {
  int frame;
  String name;
  int color; // argb
  Marker(this.frame, this.name, {this.color = 0xffffb300});
  factory Marker.fromJson(Map<String, dynamic> j) => Marker(
      j['f'] as int, j['n'] as String? ?? '',
      color: j['c'] as int? ?? 0xffffb300);
  Map<String, dynamic> toJson() => {'f': frame, 'n': name, 'c': color};
}

class Sequence {
  String id;
  String name;
  List<Track> tracks; // video tracks first (index order = top to bottom)
  List<Marker> markers;
  int zoom; // ui state persisted
  int scroll;

  Sequence({
    required this.id,
    required this.name,
    List<Track>? tracks,
    List<Marker>? markers,
    this.zoom = 10,
    this.scroll = 0,
  })  : tracks = tracks ?? [],
        markers = markers ?? [];

  List<Track> get videoTracks =>
      tracks.where((t) => t.kind == TrackKind.video).toList();
  List<Track> get audioTracks =>
      tracks.where((t) => t.kind == TrackKind.audio).toList();

  int get duration => tracks.fold(0, (m, t) => t.end > m ? t.end : m);

  factory Sequence.fromJson(Map<String, dynamic> j) => Sequence(
        id: j['id'] as String,
        name: j['n'] as String? ?? 'Sequence',
        tracks: (j['t'] as List?)
                ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        markers: (j['m'] as List?)
                ?.map((e) => Marker.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        zoom: j['z'] as int? ?? 10,
        scroll: j['s'] as int? ?? 0,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        't': tracks.map((e) => e.toJson()).toList(),
        if (markers.isNotEmpty)
          'm': markers.map((e) => e.toJson()).toList(),
        'z': zoom,
        's': scroll,
      };
}

/// A bin asset. Media files keep a path relative to the project file plus
/// identity info so a missing mount can be relocated.
class MediaAsset {
  String id;
  AssetType type;
  String name;
  String? relPath; // relative to .dal directory
  String? fileName;
  String? hash; // content identity for relocation
  int fileSize;
  double durationSec;
  int width, height;
  double fps;
  int sampleRate, channels;
  bool hasVideo, hasAudio;
  String? color; // #aarrggbb or rrggbb for color clips
  Map<String, dynamic>? title; // title clip data
  String? sequenceId; // for sequence assets
  String? proxyPath; // relative proxy path
  String folderId;
  int? thumbnailStamp; // cache buster
  Map<String, dynamic>? meta; // misc import data

  MediaAsset({
    required this.id,
    required this.type,
    required this.name,
    this.relPath,
    this.fileName,
    this.hash,
    this.fileSize = 0,
    this.durationSec = 0,
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.sampleRate = 0,
    this.channels = 0,
    this.hasVideo = false,
    this.hasAudio = false,
    this.color,
    this.title,
    this.sequenceId,
    this.proxyPath,
    this.folderId = '',
    this.thumbnailStamp,
  });

  bool get isAv =>
      type == AssetType.video || type == AssetType.audio || type == AssetType.image;

  factory MediaAsset.fromJson(Map<String, dynamic> j) => MediaAsset(
        id: j['id'] as String,
        type: AssetType.values[j['t'] as int],
        name: j['n'] as String? ?? '',
        relPath: j['p'] as String?,
        fileName: j['f'] as String?,
        hash: j['hh'] as String?,
        fileSize: j['s'] as int? ?? 0,
        durationSec: (j['d'] as num?)?.toDouble() ?? 0,
        width: j['w'] as int? ?? 0,
        height: j['h'] as int? ?? 0,
        fps: (j['r'] as num?)?.toDouble() ?? 0,
        sampleRate: j['sr'] as int? ?? 0,
        channels: j['ch'] as int? ?? 0,
        hasVideo: j['v'] as bool? ?? false,
        hasAudio: j['a'] as bool? ?? false,
        color: j['c'] as String?,
        title: (j['ti'] as Map?)?.cast<String, dynamic>(),
        sequenceId: j['q'] as String?,
        proxyPath: j['px'] as String?,
        folderId: j['fo'] as String? ?? '',
        thumbnailStamp: j['ts'] as int?,
      )..meta = (j['m2'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic> toJson() => {
        'id': id,
        't': type.index,
        'n': name,
        if (relPath != null) 'p': relPath,
        if (fileName != null) 'f': fileName,
        if (hash != null) 'hh': hash,
        if (fileSize != 0) 's': fileSize,
        if (durationSec != 0) 'd': durationSec,
        if (width != 0) 'w': width,
        if (height != 0) 'h': height,
        if (fps != 0) 'r': fps,
        if (sampleRate != 0) 'sr': sampleRate,
        if (channels != 0) 'ch': channels,
        if (hasVideo) 'v': hasVideo,
        if (hasAudio) 'a': hasAudio,
        if (color != null) 'c': color,
        if (title != null) 'ti': title,
        if (sequenceId != null) 'q': sequenceId,
        if (proxyPath != null) 'px': proxyPath,
        if (folderId.isNotEmpty) 'fo': folderId,
        if (thumbnailStamp != null) 'ts': thumbnailStamp,
        if (meta != null) 'm2': meta,
      };
}

class BinFolder {
  String id;
  String name;
  String parentId;
  BinFolder({required this.id, required this.name, this.parentId = ''});
  factory BinFolder.fromJson(Map<String, dynamic> j) => BinFolder(
      id: j['id'] as String,
      name: j['n'] as String? ?? '',
      parentId: j['p'] as String? ?? '');
  Map<String, dynamic> toJson() =>
      {'id': id, 'n': name, if (parentId.isNotEmpty) 'p': parentId};
}

class Project {
  static const currentVersion = 1;
  String name;
  int width, height;
  Rational fps;
  int sampleRate;
  List<MediaAsset> assets;
  List<BinFolder> folders;
  List<Sequence> sequences;
  String mainSequenceId;
  Map<String, String> meta; // author, notes, etc.
  // resolved at runtime, never serialized
  Map<String, String> resolvedPaths = {};

  Project({
    required this.name,
    this.width = 1920,
    this.height = 1080,
    this.fps = const Rational(30, 1),
    this.sampleRate = 48000,
    List<MediaAsset>? assets,
    List<BinFolder>? folders,
    List<Sequence>? sequences,
    String? mainSequenceId,
    Map<String, String>? meta,
  })  : assets = assets ?? [],
        folders = folders ?? [],
        sequences = sequences ?? [],
        mainSequenceId = mainSequenceId ?? '',
        meta = meta ?? {};

  double get fpsValue => fps.value;
  int framesFromSeconds(double s) => (s * fpsValue).round();
  double secondsFromFrames(int f) => f / fpsValue;

  Sequence? get mainSequence {
    for (final s in sequences) {
      if (s.id == mainSequenceId) return s;
    }
    return sequences.isEmpty ? null : sequences.first;
  }

  Sequence? sequenceById(String id) {
    for (final s in sequences) {
      if (s.id == id) return s;
    }
    return null;
  }

  MediaAsset? assetById(String id) {
    for (final a in assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: j['name'] as String? ?? 'Untitled',
        width: j['w'] as int? ?? 1920,
        height: j['h'] as int? ?? 1080,
        fps: j['fps'] == null
            ? const Rational(30, 1)
            : Rational.fromJson(j['fps'] as Map<String, dynamic>),
        sampleRate: j['sr'] as int? ?? 48000,
        assets: (j['assets'] as List?)
                ?.map((e) => MediaAsset.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        folders: (j['folders'] as List?)
                ?.map((e) => BinFolder.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        sequences: (j['sequences'] as List?)
                ?.map((e) => Sequence.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        mainSequenceId: j['main'] as String? ?? '',
        meta: (j['meta'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'name': name,
        'w': width,
        'h': height,
        'fps': fps.toJson(),
        'sr': sampleRate,
        'assets': assets.map((e) => e.toJson()).toList(),
        'folders': folders.map((e) => e.toJson()).toList(),
        'sequences': sequences.map((e) => e.toJson()).toList(),
        'main': mainSequenceId,
        'meta': meta,
      };
}

String jsonEncodeClip(Clip c) => jsonEncode(c.toJson());
Clip clipFromJson(String s) =>
    Clip.fromJson(jsonDecode(s) as Map<String, dynamic>);
