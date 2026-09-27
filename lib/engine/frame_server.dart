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
  int _gen = 0;

  /// frame index -> jpeg bytes
  final Map<int, Uint8List> _cache = {};
  final ListQueue<int> _lru = ListQueue();
  int cacheBytes = 0;
  int maxCacheMb = 2048;

  final _frameCtr = StreamController<int>.broadcast();
  Stream<int> get onFrame => _frameCtr.stream;

  /// Call when the timeline/project changed so stale frames are dropped.
  void invalidate() {
    _gen++;
    _killProc();
    _cache.clear();
    _lru.clear();
    cacheBytes = 0;
  }

  void _killProc() {
    _proc?.kill();
    _proc = null;
  }

  /// Returns cached jpeg for [frame] if present.
  Uint8List? cached(int frame) => _cache[frame];

  bool hasFrame(int f) => _cache.containsKey(f);

  /// Ensure rendering progresses toward covering frames >= [frame].
  void ensure(Sequence seq, int frame) {
    final needsRestart = _proc == null ||
        _seq?.id != seq.id ||
        frame < _renderStart ||
        frame > _renderHead + 5 ||
        (frame < _renderHead && !_cache.containsKey(frame));
    if (!needsRestart || _building) return;
    _building = true; // synchronous so a second ensure can't double-start
    _restart(seq, frame, _gen);
  }

  Future<void> _restart(Sequence seq, int start, int gen) async {
    _killProc();
    _seq = seq;
    _renderStart = start;
    _renderHead = start;
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
        '-hide_banner', '-loglevel', 'error', '-nostdin',
        ...g.inputArgs,
        '-filter_complex', g.filterComplex,
        '-map', '[${g.videoLabel}]',
        '-f', 'image2pipe',
        '-vcodec', 'mjpeg',
        '-q:v', '4',
        '-',
      ];
      final p = await Process.start(FFmpeg.ffmpegPath, args);
      if (gen != _gen) {
        p.kill(); // invalidated while starting
        return;
      }
      _proc = p;
      var emitted = start;
      final inflight = BytesBuilder(); // per-render buffer
      p.stdout.listen((chunk) {
        if (gen != _gen) return; // stale process output
        inflight.add(chunk);
        final data = inflight.takeBytes();
        var off = 0;
        // scan for jpeg SOI/EOI pairs
        while (true) {
          final soi = _find(data, [0xFF, 0xD8], off);
          if (soi < 0) {
            // keep a trailing lone 0xFF — could be a split SOI marker
            if (data.isNotEmpty && data[data.length - 1] == 0xFF) {
              inflight.add(data.sublist(data.length - 1));
            }
            break;
          }
          final eoi = _find(data, [0xFF, 0xD9], soi + 2);
          if (eoi < 0) {
            inflight.add(data.sublist(soi));
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
    if (!_frameCtr.isClosed) _frameCtr.add(frame);
  }

  /// A single still frame at [frame] — used when paused/scrubbing to a
  /// specific spot without streaming.
  Future<Uint8List?> still(Sequence seq, int frame) async {
    if (_cache.containsKey(frame)) return _cache[frame];
    ensure(seq, frame);
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 25));
      final j = _cache[frame];
      if (j != null) return j;
    }
    return _cache[frame];
  }

  void dispose() {
    _gen++;
    _killProc();
    _frameCtr.close();
  }
}
