import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import '../models/model.dart';
import '../io/media_resolver.dart';
import 'ffmpeg.dart';
import 'graph.dart';

/// Renders timeline frames via ffmpeg to an mjpeg pipe, caches them in an
/// LRU map, and hands them to the UI for decode/display. The renderer always
/// works forward from a requested position; playback consumes cached frames
/// at project rate while the server runs ahead as fast as it can.
class FrameServer {
  Project Function() project;
  MediaResolver Function() resolver;

  /// Preview scale (0.25, 0.5, 1.0).
  double scale;
  bool useProxies;

  FrameServer(this.project, this.resolver,
      {this.scale = 0.5, this.useProxies = false});

  Process? _proc;
  Sequence? _seq;
  int _renderHead = 0; // next frame the ffmpeg process will emit
  int _renderStart = 0;
  bool _building = false;
  final ListQueue<Uint8List> _jpegBuf = ListQueue();
  BytesBuilder _inflight = BytesBuilder();

  /// frame index -> jpeg bytes
  final Map<int, Uint8List> _cache = {};
  final ListQueue<int> _lru = ListQueue();
  int cacheBytes = 0;
  int maxCacheMb = 2048;

  final _frameCtr = StreamController<int>.broadcast();
  Stream<int> get onFrame => _frameCtr.stream;

  int _graphVersion = 0;
  int get graphVersion => _graphVersion;

  /// Call when the timeline/project changed so we drop stale frames.
  void invalidate({bool hard = false}) {
    _graphVersion++;
    _killProc();
    if (hard) {
      _cache.clear();
      _lru.clear();
      cacheBytes = 0;
      _jpegBuf.clear();
    }
  }

  void _killProc() {
    _proc?.kill();
    _proc = null;
    _jpegBuf.clear();
    _inflight = BytesBuilder();
  }

  /// Returns cached jpeg for [frame] if present.
  Uint8List? cached(int frame) => _cache[frame];

  bool hasFrame(int f) => _cache.containsKey(f);

  /// Ensure rendering progresses toward covering frames >= [frame].
  /// The server restarts only when [frame] is outside the current forward
  /// pass or when the requested sequence changed.
  void ensure(Sequence seq, int frame) {
    final needsRestart = _proc == null ||
        _seq?.id != seq.id ||
        frame < _renderStart ||
        frame > _renderHead + 5;
    if (!needsRestart || _building) return;
    _restart(seq, frame);
  }

  Future<void> _restart(Sequence seq, int start) async {
    _killProc();
    _seq = seq;
    _renderStart = start;
    _renderHead = start;
    _building = true;
    try {
      final end = max(seq.duration, start + 1);
      final w = max(16, (project().width * scale).round() & ~1);
      final h = max(16, (project().height * scale).round() & ~1);
      final gb = GraphBuilder(
        project: project(),
        resolver: resolver(),
        width: w,
        height: h,
        useProxies: useProxies,
      )..enableHwaccel();
      final g = gb.build(seq, start, end, audio: false);
      final args = <String>[
        '-hide_banner', '-loglevel', 'error',
        ...g.inputArgs,
        '-filter_complex', g.filterComplex,
        '-map', '[${g.videoLabel}]',
        '-f', 'image2pipe',
        '-vcodec', 'mjpeg',
        '-q:v', '4',
        '-',
      ];
      final p = await Process.start(FFmpeg.ffmpegPath, args);
      _proc = p;
      var emitted = start;
      p.stdout.listen((chunk) {
        _inflight.add(chunk);
        final data = _inflight.takeBytes();
        var off = 0;
        // scan for jpeg SOI/EOI pairs
        while (true) {
          final soi = _find(data, [0xFF, 0xD8], off);
          if (soi < 0) break;
          final eoi = _find(data, [0xFF, 0xD9], soi + 2);
          if (eoi < 0) {
            _inflight.add(data.sublist(soi));
            break;
          }
          final jpg = Uint8List.fromList(data.sublist(soi, eoi + 2));
          _put(emitted, jpg);
          emitted++;
          _renderHead = emitted;
          off = eoi + 2;
        }
      }, onDone: () {}, onError: (_) {});
      p.stderr.drain<void>();
    } finally {
      _building = false;
    }
  }

  int _find(List<int> d, List<int> pat, int from) {
    outer:
    for (var i = from; i < d.length - 1; i++) {
      for (var j = 0; j < pat.length; j++) {
        if (d[i + j] != pat[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  void _put(int frame, Uint8List jpg) {
    if (_cache.containsKey(frame)) return;
    _cache[frame] = jpg;
    _lru.addLast(frame);
    cacheBytes += jpg.length;
    final cap = maxCacheMb * 1024 * 1024;
    while (cacheBytes > cap && _lru.isNotEmpty) {
      final f = _lru.removeFirst();
      final v = _cache.remove(f);
      if (v != null) cacheBytes -= v.length;
    }
    _frameCtr.add(frame);
  }

  /// A single still frame at [frame] — used when paused/scrubbing to a
  /// specific spot without streaming.
  Future<Uint8List?> still(Sequence seq, int frame) async {
    if (_cache.containsKey(frame)) return _cache[frame];
    ensure(seq, frame);
    // wait briefly for the frame
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 25));
      final j = _cache[frame];
      if (j != null) return j;
    }
    return _cache[frame];
  }

  void dispose() {
    _killProc();
    _frameCtr.close();
  }
}
