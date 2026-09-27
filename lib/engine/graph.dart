import 'dart:io';
import 'dart:math';

import '../models/effects.dart';
import '../models/model.dart';
import '../io/media_resolver.dart';

/// Builds an ffmpeg command (input args + filter_complex) that renders a
/// sequence range to raw frames or an encoder. This same builder powers the
/// preview frame server, thumbnail rendering and final export.
class GraphResult {
  final List<String> inputArgs;
  final String filterComplex;
  final String videoLabel; // e.g. "vout" or '' if no video
  final String audioLabel;
  final int startFrame;
  const GraphResult(this.inputArgs, this.filterComplex, this.videoLabel,
      this.audioLabel, this.startFrame);
}

class _Ctx {
  final StringBuffer filt = StringBuffer();
  final List<String> inputs = [];
  int n = 0;
  void emit(String s) => filt.write('$s;\n');
  String lab() => 'g${n++}';
  int addInput(List<String> args) {
    inputs.addAll(args);
    return inputs.length ~/ 1; // caller tracks real index separately
  }
}

class _ClipIn {
  int index = -1; // ffmpeg input index or -1 for lavfi-in-graph
  String lavfi = ''; // e.g. "color=c=..." source filter used in-graph
}

class GraphBuilder {
  final Project project;
  final MediaResolver? resolver;
  final int width, height;
  final double fps;
  final bool useProxies;

  GraphBuilder({
    required this.project,
    this.resolver,
    int? width,
    int? height,
    double? fps,
    this.useProxies = false,
  })  : width = width ?? project.width,
        height = height ?? project.height,
        fps = fps ?? project.fpsValue;

  _Ctx _ctx = _Ctx();
  int _inputCount = 0;

  String _fmt(double v) => v.toStringAsFixed(6);
  String _c(double t) => t.toStringAsFixed(4);

  /// Resolve a clip's media to an ffmpeg input. For av assets uses -ss/-t
  /// input seeking; images loop; lavfi sources are emitted inside the graph.
  bool _isOffline(MediaAsset a) {
    if (!a.isAv || a.relPath == null) return false;
    if (project.resolvedPaths.containsKey(a.id)) {
      return !File(project.resolvedPaths[a.id]!).existsSync();
    }
    final p = _assetPath(a);
    return p == null || !File(p).existsSync();
  }

  _ClipIn _clipInput(MediaAsset a, double inSec, double durSec) {
    if (a.type == AssetType.video ||
        a.type == AssetType.audio ||
        a.type == AssetType.image) {
      if (_isOffline(a)) {
        return _ClipIn()
          ..lavfi =
              'color=c=0x333333:s=${width}x$height:r=${_c(fps)}:d=${_c(durSec)},format=rgba';
      }
      final path = _assetPath(a);
      final args = <String>[];
      if (a.type == AssetType.image) {
        args.addAll(['-loop', '1', '-framerate', _c(fps), '-t', _c(durSec)]);
      } else {
        args.addAll([
          '-ss', _c(inSec),
          '-t', _c(durSec),
          if (_hwaccel) ...['-hwaccel', 'auto'],
        ]);
      }
      args.addAll(['-i', path ?? '']);
      final idx = _inputCount++;
      _ctx.inputs.addAll(args);
      return _ClipIn()..index = idx;
    }
    if (a.type == AssetType.color) {
      final c = _ffmpegColor(a.color ?? 'black');
      return _ClipIn()
        ..lavfi = 'color=c=$c:s=${width}x$height:r=${_c(fps)}:d=${_c(durSec)}';
    }
    // sequence + title handled by callers
    return _ClipIn();
  }

  bool _hwaccel = false;
  void enableHwaccel() => _hwaccel = true;

  String? _assetPath(MediaAsset a) {
    if (useProxies && a.proxyPath != null && resolver != null) {
      final p = resolver!.toAbsolute(a.proxyPath!);
      return p;
    }
    if (a.relPath == null) return null;
    return resolver?.toAbsolute(a.relPath!) ?? a.relPath;
  }

  static String _ffmpegColor(String s) {
    var v = s.replaceAll('#', '');
    if (v.length == 8) v = v.substring(2); // drop alpha for color= source
    return '0x$v';
  }

  /// Escape a value for use inside a filter_complex option.
  static String esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(':', '\\:')
      .replaceAll(',', '\\,')
      .replaceAll("'", "\\'")
      .replaceAll(';', '\\;')
      .replaceAll('[', '\\[')
      .replaceAll(']', '\\]')
      .replaceAll('%', '\\\\%');

  static String escText(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(':', '\\:')
      .replaceAll("'", '’')
      .replaceAll('%', '\\\\%')
      .replaceAll('\n', ' ');

  /// Build the graph for [seq] frames [start..end). Relative time base: the
  /// returned stream covers [start, end) with PTS starting near 0.
  /// [timeOffset] shifts all clips (for nested sequence clips).
  GraphResult build(Sequence seq, int start, int end,
      {bool audio = true, bool video = true}) {
    _ctx = _Ctx();
    _inputCount = 0;
    final dur = end - start;
    final durSec = dur / fps;

    // ---- video ----
    String vout = '';
    if (video) {
    final vtracks = seq.videoTracks;
    String cur = _ctx.lab();
    _ctx.emit(
        'color=c=black:s=${width}x$height:r=${_c(fps)}:d=${_c(durSec)}[$cur]');
    var baseN = 0;
    for (var ti = vtracks.length - 1; ti >= 0; ti--) {
      final track = vtracks[ti];
      if (track.hidden) continue;
      for (final clip in track.sorted) {
        if (!clip.enabled) continue;
        if (clip.end <= start || clip.position >= end) continue;
        final stream = _emitClipVideo(seq, clip, start, end, 0, null);
        if (stream == null) continue;
        final out = _ctx.lab();
        _ctx.emit(
            '[$cur][$stream]overlay=x=0:y=0:eof_action=pass[$out]');
        cur = out;
        baseN++;
      }
    }
    if (baseN == 0) {
      vout = cur;
    } else {
      vout = 'vout';
      _ctx.emit('[$cur]copy[$vout]');
    }
    }

    // ---- audio ----
    String aout = '';
    final astreams = <String>[];
    if (audio) {
      // audio tracks plus audio-bearing clips on video tracks
      // (nested sequences, sound dropped on V tracks)
      for (final track in seq.tracks) {
        if (track.muted) continue;
        for (final clip in track.sorted) {
          if (!clip.enabled) continue;
          if (clip.end <= start || clip.position >= end) continue;
          final asset = project.assetById(clip.assetId);
          if (asset == null) continue;
          if (track.kind == TrackKind.video &&
              !asset.hasAudio &&
              asset.type != AssetType.sequence) {
            continue;
          }
          if (track.kind == TrackKind.audio && !asset.hasAudio) continue;
          final s = _emitClipAudio(seq, clip, start, end, 0);
          if (s != null) astreams.add(s);
        }
      }
      // video-only clips on video tracks still contribute audio? No: in this
      // model audio lives on audio tracks only.
      if (astreams.isEmpty) {
        aout = 'aout';
        _ctx.emit(
            'anullsrc=cl=stereo:r=${project.sampleRate}:d=${_c(durSec)}[$aout]');
      } else if (astreams.length == 1) {
        aout = 'aout';
        _ctx.emit(
            '[${astreams.first}]aformat=sample_fmts=fltp:sample_rates=${project.sampleRate}:channel_layouts=stereo[$aout]');
      } else {
        aout = 'aout';
        _ctx.emit(
            '${astreams.map((e) => '[$e]').join()}amix=inputs=${astreams.length}:duration=longest:normalize=0,'
            'aformat=sample_fmts=fltp:sample_rates=${project.sampleRate}:channel_layouts=stereo[$aout]');
      }
    }
    return GraphResult(_ctx.inputs, _ctx.filt.toString(), vout, aout, start);
  }

  /// Emit the full video chain for one clip shifted into the render window.
  /// [seqOffset] = position shift in frames for nested sequences.
  /// Returns label of a stream that covers ONLY the clip's window (PTS at
  /// timeline position), or null.
  String? _emitClipVideo(Sequence seq, Clip clip, int winStart, int winEnd,
      int seqOffset, double? parentSpeed) {
    final a = project.assetById(clip.assetId);
    if (a == null) return null;

    final pos = clip.position + seqOffset;
    final clipEnd = pos + clip.duration;
    // visible window of this clip within render range
    final visStart = max(pos, winStart);
    final visEnd = min(clipEnd, winEnd);
    if (visEnd <= visStart) return null;
    final skipFrames = visStart - pos; // frames into the clip we skip
    final visDur = visEnd - visStart;
    final speed = clip.speed * (parentSpeed ?? 1.0);

    // Handle head transition: if a previous clip on the same track abuts,
    // produce a composite xfade stream covering both.
    // (handled by caller path through _emitTransitionPair)
    final durSec = visDur / fps;
    final inSec = clip.offsetSec + (skipFrames / fps) * speed;

    String src;
    if (a.type == AssetType.sequence) {
      // nested sequence: build sub-graph over its own coords
      final sub = project.sequenceById(a.sequenceId ?? '');
      if (sub == null) return null;
      src = _emitSequence(sub, visDur, visStart - pos, speed);
    } else if (a.type == AssetType.title) {
      src = _emitTitle(a, visDur);
    } else if (a.type == AssetType.color) {
      src = _ctx.lab();
      final c = _ffmpegColor(a.color ?? 'black');
      _ctx.emit(
          'color=c=$c:s=${width}x$height:r=${_c(fps)}:d=${_c(durSec)}[$src]');
    } else {
      final inp = _clipInput(a, inSec, durSec + 1 / fps);
      src = _ctx.lab();
      if (inp.index >= 0) {
        _ctx.emit('[${inp.index}:v]fps=${_c(fps)}[$src]');
      } else {
        _ctx.emit('${inp.lavfi}[$src]');
      }
    }

    // normalize to project frame, transparency-capable
    var s = _ctx.lab();
    _ctx.emit(
        '[$src]scale=w=${width}:h=${height}:force_original_aspect_ratio=decrease,'
        'pad=${width}:$height:(ow-iw)/2:(oh-ih)/2:color=black@0,'
        'setsar=1,format=rgba[$s]');

    // effects chain (may segment at keyframes)
    s = _applyVideoEffects(s, clip, visStart - pos, visDur, speed);

    // transition handling
    final track = _findTrack(seq, clip.id);
    final prev = _prevClip(track, clip);
    final tr = clip.transition;
    if (tr != null &&
        prev != null &&
        prev.end == clip.position &&
        prev.enabled &&
        seqOffset == 0) {
      // Build tail extension of prev covering the transition region.
      final dFrames = tr.duration;
      final tail = _emitClipVideoTail(seq, prev, clip, dFrames, winStart, winEnd);
      if (tail != null) {
        // tail covers 2*dFrames (prev tail + its extension); cur covers
        // its full window. Blend happens over the second half of tail.
        final head = s;
        final out = _ctx.lab();
        final xkind = _xfadeName(tr.kind);
        _ctx.emit(
            '[$tail][$head]xfade=transition=$xkind:duration=${_c(dFrames / fps)}:offset=${_c(dFrames / fps)}[$out]');
        s = out;
        // pair output covers [pos - dFrames, pos + visDur): shift left by
        // dFrames so it lands at the right timeline spot.
        return _padToWindow(s, visStart - winStart - dFrames,
            visDur + dFrames);
      }
    }

    // pad the stream with transparent frames so it starts at t=0 of the
    // render window and its content lands at relStart.
    return _padToWindow(s, visStart - winStart, visDur);
  }

  /// Prefix [stream] with [leadFrames] transparent frames so its content
  /// sits at [leadFrames] in window-local time. Negative values shift the
  /// stream earlier (used for transition pairs).
  String _padToWindow(String stream, int leadFrames, int _) {
    var s = stream;
    if (leadFrames < 0) {
      final o = _ctx.lab();
      _ctx.emit('[$s]setpts=PTS-${_c(-leadFrames / fps)}/TB[$o]');
      return o;
    }
    if (leadFrames == 0) return s;
    final pad = _ctx.lab();
    _ctx.emit(
        'color=c=black@0:s=${width}x$height:r=${_c(fps)}:d=${_c(leadFrames / fps)},format=rgba,setsar=1[$pad]');
    final base = _ctx.lab();
    _ctx.emit('[$s]setpts=PTS-STARTPTS[$base]');
    final out = _ctx.lab();
    _ctx.emit('[$pad][$base]concat=n=2:v=1:a=0[$out]');
    return out;
  }

  /// Build the "A-side" of an xfade: prev clip's tail repeated/extended to
  /// cover the transition window [pos-D, pos+D).
  String? _emitClipVideoTail(Sequence seq, Clip prev, Clip cur, int dFrames,
      int winStart, int winEnd) {
    final pa = project.assetById(prev.assetId);
    if (pa == null) return null;
    final a = project.assetById(cur.assetId);
    if (a == null) return null;
    // portion of prev visible in [prev.end - X, prev.end + dFrames]
    // We build a stream covering [pos-D', pos+dur) where the last dFrames of
    // prev play under cur's first dFrames, then cur continues alone.
    // xfade semantics: first input length must be offset+duration; we give
    // prevTail covering [pos-Dpos .. pos+dFrames)?? Simpler: emit prev's last
    // dFrames extended by dFrames frozen/fresh frames => stream of 2*dFrames
    // covering [pos-dFrames, pos+dFrames). xfade(offset=dFrames? no...)
    // xfade joins: out = A[0..offset] + blend[A[offset..offset+d], B[0..d]]
    //          + B[d..]. We want out to cover [pos-dFrames, cur.end):
    // A = prev-tail stream len 2*dFrames (local), offset = dFrames,
    // B = cur stream starting at 0 => out len = 2*dF + curDur - dF.
    // That extends B's stream: but we only want region [pos-dF, pos+dF] then
    // hand off to B continuing. Complicated; instead: emit A-tail as
    // "prev playing its last dFrames then frozen/extra dFrames" and overlay it
    // UNDER cur, while cur's head does the xfade via alpha? For non-dissolve
    // we must xfade. Compromise: transition stream = xfade(prevTail, curHead)
    // covering [pos-dFrames, pos+dFrames); emit curHead = first dFrames of cur.
    // Caller overlays cur full stream too — xfade region would double-cover
    // cur's first dFrames. So instead the caller should have trimmed cur's
    // head. We do it here: return the pair stream covering
    // [pos - dFrames, pos + dFrames) only? Then a gap (pos-dF,pos) is covered
    // by prev's own stream (already emitted), and (pos+dF, end) by cur's —
    // but cur's stream was emitted starting at pos! So we need cur's head
    // shifted: xfade output = dFrames+dFrames+dur-dFrames = dF+dur covering
    // [pos-dF, pos+dur). Since caller over lays cur at pos with full dur:
    // instead we make THIS the whole visible stream: A' = prev tail covering
    // [pos-dF, pos+dF]; B = cur covering [pos, pos+visDur); pair covers
    // [pos-dF, pos+visDur). The xfade offset param counts in A' time.
    // => offset = dFrames (A' spans 2*dFrames, blend starts at its dFrames).
    final tail = _ctx.lab();
    // prev tail stream of length 2*dFrames: last dFrames played + dFrames more
    // (decoded if media exists, else frozen via tpad)
    final needSec = dFrames / fps;
    final tailIn = prev.offsetSec +
        (prev.duration - dFrames) / fps * prev.speed;
    String base;
    if (pa.isAv && pa.relPath != null && !_isOffline(pa)) {
      final canExtend = tailIn + (2 * needSec * prev.speed) <=
          pa.durationSec + 0.05;
      final inp = _clipInput(
          pa,
          max(0, tailIn),
          canExtend ? 2 * needSec + 1 / fps : needSec + 1 / fps);
      base = _ctx.lab();
      if (inp.index >= 0) {
        _ctx.emit('[${inp.index}:v]fps=${_c(fps)}[$base]');
      } else {
        _ctx.emit('${inp.lavfi}[$base]');
      }
      if (!canExtend) {
        final b2 = _ctx.lab();
        _ctx.emit(
            '[$base]tpad=stop_mode=clone:stop=${_c(needSec)}[$b2]');
        base = b2;
      }
    } else {
      // static source (color/title/image rendered as still)
      base = _ctx.lab();
      _ctx.emit(
          'color=c=black@0:s=${width}x$height:r=${_c(fps)}:d=${_c(2 * needSec)}[$base]');
      // Note: for color clips we could repeat the color; keep simple.
    }
    var b = _ctx.lab();
    _ctx.emit(
        '[$base]scale=w=${width}:h=${height}:force_original_aspect_ratio=decrease,'
        'pad=${width}:$height:(ow-iw)/2:(oh-ih)/2:color=black@0,'
        'setsar=1,format=rgba[$b]');
    // prev's effects applied to its tail too (evaluated at its last frames)
    final fakePrev = prev.clone('${prev.id}_tail')
      ..position = prev.position
      ..duration = dFrames * 2;
    b = _applyVideoEffects(b, fakePrev, 0, dFrames * 2, prev.speed);
    final out = _ctx.lab();
    _ctx.emit('[$b]setpts=PTS-STARTPTS[$out]');
    // now the cur stream comes from caller; we return label + let caller xfade
    _pendingTailLabel = out;
    return _pendingTailLabel;
  }

  String _pendingTailLabel = '';

  static String _xfadeName(TransitionKind k) => switch (k) {
        TransitionKind.dissolve => 'fade',
        TransitionKind.wipeLeft => 'wipeleft',
        TransitionKind.wipeRight => 'wiperight',
        TransitionKind.wipeUp => 'wipeup',
        TransitionKind.wipeDown => 'wipedown',
        TransitionKind.slideLeft => 'slideleft',
        TransitionKind.slideRight => 'slideright',
        TransitionKind.slideUp => 'slideup',
        TransitionKind.slideDown => 'slidedown',
        TransitionKind.circle => 'circleopen',
        TransitionKind.radial => 'radial',
        TransitionKind.pixelize => 'pixelize',
        TransitionKind.fadeBlack => 'fadeblack',
        TransitionKind.fadeWhite => 'fadewhite',
      };

  /// Emit a nested sequence's composite covering [durFrames] of sub-sequence
  /// time starting at [subOffset] frames into it, played at [speed].
  String _emitSequence(Sequence sub, int durFrames, int subOffset, double speed) {
    // Build video over sub coords covering [subOffset, subOffset+durFrames)
    final vtracks = sub.videoTracks;
    String cur = _ctx.lab();
    _ctx.emit(
        'color=c=black@0:s=${width}x$height:r=${_c(fps)}:d=${_c(durFrames / fps)}[$cur]');
    for (var ti = vtracks.length - 1; ti >= 0; ti--) {
      final track = vtracks[ti];
      if (track.hidden) continue;
      for (final clip in track.sorted) {
        if (!clip.enabled) continue;
        if (clip.end <= subOffset || clip.position >= subOffset + durFrames) {
          continue;
        }
        final stream = _emitClipVideo(sub, clip, subOffset, subOffset + durFrames, 0, speed);
        if (stream == null) continue;
        final out = _ctx.lab();
        _ctx.emit(
            '[$cur][$stream]overlay=x=0:y=0:eof_action=pass[$out]');
        cur = out;
      }
    }
    return cur;
  }

  /// Emit title clip video: transparent canvas + drawtext chain.
  String _emitTitle(MediaAsset a, int durFrames) {
    var cur = _ctx.lab();
    _ctx.emit(
        'color=c=black@0:s=${width}x$height:r=${_c(fps)}:d=${_c(durFrames / fps)}[$cur]');
    final items = (a.title?['items'] as List?) ?? const [];
    for (final raw in items) {
      final it = (raw as Map).cast<String, dynamic>();
      final kind = it['type'] as String? ?? 'text';
      if (kind == 'rect') {
        // drawbox
        final x = ((it['x'] as num?)?.toDouble() ?? 0) * width;
        final y = ((it['y'] as num?)?.toDouble() ?? 0) * height;
        final w = ((it['w'] as num?)?.toDouble() ?? 0.2) * width;
        final h = ((it['h'] as num?)?.toDouble() ?? 0.1) * height;
        final color = it['color'] as String? ?? 'white';
        final out = _ctx.lab();
        _ctx.emit(
            '[$cur]drawbox=x=${x.round()}:y=${y.round()}:w=${w.round()}:h=${h.round()}:color=$color:t=fill[$out]');
        cur = out;
        continue;
      }
      final text = escText('${it['text'] ?? ''}');
      final size = ((it['size'] as num?)?.toDouble() ?? 0.08) * height;
      final x = ((it['x'] as num?)?.toDouble() ?? 0.5);
      final y = ((it['y'] as num?)?.toDouble() ?? 0.5);
      final color = it['color'] as String? ?? 'white';
      final box = it['box'] == true ? ':box=1:boxcolor=black@0.5:boxborderw=10' : '';
      final out = _ctx.lab();
      _ctx.emit(
          '[$cur]drawtext=text=\'$text\':fontsize=${size.round()}:fontcolor=$color:'
          'x=(w-text_w)*${_c(x)}:y=(h-text_h)*${_c(y)}$box[$out]');
      cur = out;
    }
    return cur;
  }

  /// Apply the clip's video effects. Splits into segments when keyframed
  /// params can't be expressed per-frame.
  /// [localStart]/[localDur] describe the clip-local window rendered.
  String _applyVideoEffects(
      String input, Clip clip, int localStart, int localDur, double speed) {
    final fxs = clip.effects
        .where((e) => e.enabled && (Effects.byId(e.effectId)?.audio == false))
        .toList();
    if (fxs.isEmpty) return input;

    // collect segment boundaries for non-expr keyframed params
    final splits = <int>{};
    for (final fx in fxs) {
      final def = Effects.byId(fx.effectId)!;
      if (def.needsSegments(fx)) {
        for (final e in fx.keyframes.entries) {
          for (final k in e.value) {
            final f = k.frame - localStart;
            if (f > 0 && f < localDur) splits.add(f);
          }
        }
      }
    }
    if (splits.isEmpty || splits.length > 60) {
      if (splits.length > 60) splits.clear();
      return _applyVideoEffectsStatic(
          input, fxs, clip, localStart, localDur, speed);
    }
    final bounds = [0, ...splits.toList()..sort(), localDur];
    final segLabels = <String>[];
    for (var i = 0; i < bounds.length - 1; i++) {
      final s0 = bounds[i], s1 = bounds[i + 1];
      var seg = _ctx.lab();
      _ctx.emit(
          '[$input]trim=start_frame=$s0:end_frame=$s1,setpts=PTS-STARTPTS[$seg]');
      seg = _applyVideoEffectsStatic(
          seg, fxs, clip, localStart + s0, s1 - s0, speed,
          frameOffset: localStart + s0);
      segLabels.add(seg);
    }
    final out = _ctx.lab();
    _ctx.emit(
        '${segLabels.map((e) => '[$e]').join()}concat=n=${segLabels.length}:v=1:a=0[$out]');
    return out;
  }

  /// Emit one segment of video effects. [atFrame] = local frame used for
  /// static (non-expr) keyframed params; expression-capable params become
  /// per-frame expressions over clip-local `t`.
  String _applyVideoEffectsStatic(String input, List<ClipEffect> fxs, Clip clip,
      int localStart, int localDur, double speed,
      {int frameOffset = 0}) {
    var s = input;
    for (final fx in fxs) {
      final def = Effects.byId(fx.effectId);
      if (def == null || def.audio) continue;
      s = _applyVideoEffect(s, fx, def, clip, localDur, frameOffset, speed);
    }
    return s;
  }

  String _v(ClipEffect fx, String p, int atFrame, double def) =>
      _c(fx.at(p, atFrame, fps, def));
  String? _vx(ClipEffect fx, String p, double def) =>
      keyframesToExpr(fx.keyframes[p], fps, def);

  String _applyVideoEffect(String input, ClipEffect fx, EffectDef def, Clip clip,
      int localDur, int atFrame, double speed) {
    String chain(String filter, {String? label}) {
      final out = label ?? _ctx.lab();
      _ctx.emit('[$input]$filter[$out]');
      return out;
    }

    switch (def.id) {
      case 'transform':
        {
          final sx = _vx(fx, 'sx', 1) ?? _v(fx, 'sx', atFrame, 1);
          final sy = _vx(fx, 'sy', 1) ?? _v(fx, 'sy', atFrame, 1);
          final rot = _vx(fx, 'rot', 0) ?? _v(fx, 'rot', atFrame, 0);
          final x = _vx(fx, 'x', 0) ?? _v(fx, 'x', atFrame, 0);
          final y = _vx(fx, 'y', 0) ?? _v(fx, 'y', atFrame, 0);
          final op = _vx(fx, 'op', 1) ?? _v(fx, 'op', atFrame, 1);
          var s = chain(
              "scale=w='iw*($sx)':h='ih*($sy)':eval=frame");
          s = _appendTo(
              s, "rotate=a='$rot*PI/180':ow=rotw(iw):oh=roth(ih):fillcolor=black@0");
          // re-center on canvas with translate, per-frame overlay
          final canvas = _ctx.lab();
          _ctx.emit(
              'color=c=black@0:s=${width}x$height:r=${_c(fps)}:d=${_c(localDur / fps)}[$canvas]');
          final out = _ctx.lab();
          _ctx.emit(
              '[$canvas][$s]overlay=x=\'(main_w-overlay_w)/2+($x)*main_w\':'
              'y=\'(main_h-overlay_h)/2+($y)*main_h\':eval=frame[$out]');
          s = out;
          // opacity via alpha scale expression? colorchannelmixer is static;
          // use geq? too slow. Use 'format=rgba,lutyuv'? For animated opacity
          // we multiply alpha via colorchannelmixer only if static; for expr,
          // use premultiply trick: 'colorchannelmixer' can't. Fallback: use
          // lut over alpha channel expression — lut3d can't per-frame either.
          // Practical: use 'geq' only for alpha? geq is very slow. Instead use
          // fade filter trick not possible. Use 'curves' per-frame? no.
          // Solution: use overlay alpha via 'format=rgba,colorchannelmixer'
          // when static; when animated use volume-like expr on 'premultiply'
          // isn't available. We'll approximate animated opacity using the
          // 'tmix' no... Final choice: use scale 'eval=frame' done, and for
          // opacity use 'colorchannelmixer' static when no keyframes, else a
          // per-frame expression via 'geq' is too slow — use 'lutrgb'? Not
          // per-frame. => use segmentation (declared non-expr).
          s = _appendTo(s, 'colorchannelmixer=aa=$op');
          return s;
        }
      case 'crop':
        {
          final l = fx.numVal('l', 0), r = fx.numVal('r', 0);
          final t = fx.numVal('t', 0), b = fx.numVal('b', 0);
          var s = chain(
              'crop=w=iw*(1-${_c(l + r)}):h=ih*(1-${_c(t + b)}):x=iw*${_c(l)}:y=ih*${_c(t)}');
          s = _appendTo(s,
              'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black@0');
          return s;
        }
      case 'opacity':
        return chain('colorchannelmixer=aa=${_v(fx, 'op', atFrame, 1)}');
      case 'eq':
        return chain(
            'eq=brightness=${_v(fx, 'brightness', atFrame, 0)}:contrast=${_v(fx, 'contrast', atFrame, 1)}:saturation=${_v(fx, 'saturation', atFrame, 1)}:gamma=${_v(fx, 'gamma', atFrame, 1)}:gamma_r=${_v(fx, 'gamma_r', atFrame, 1)}:gamma_g=${_v(fx, 'gamma_g', atFrame, 1)}:gamma_b=${_v(fx, 'gamma_b', atFrame, 1)}');
      case 'levels':
        {
          var s = chain(
              'colorlevels=rimin=${_v(fx, 'rimin', atFrame, 0)}:gimin=${_v(fx, 'rimin', atFrame, 0)}:bimin=${_v(fx, 'rimin', atFrame, 0)}:rimax=${_v(fx, 'rimax', atFrame, 1)}:gimax=${_v(fx, 'rimax', atFrame, 1)}:bimax=${_v(fx, 'rimax', atFrame, 1)}:romin=${_v(fx, 'romin', atFrame, 0)}:gomin=${_v(fx, 'romin', atFrame, 0)}:bomin=${_v(fx, 'romin', atFrame, 0)}:romax=${_v(fx, 'romax', atFrame, 1)}:gomax=${_v(fx, 'romax', atFrame, 1)}:bomax=${_v(fx, 'romax', atFrame, 1)}');
          // colorlevels has no gamma — approximate via eq
          if (fx.numVal('gammaval', 1) != 1) {
            s = _appendTo(s, 'eq=gamma=${_v(fx, 'gammaval', atFrame, 1)}');
          }
          return s;
        }
      case 'colorbalance':
        return chain(
            'colorbalance=rs=${_v(fx, 'rs', atFrame, 0)}:gs=${_v(fx, 'gs', atFrame, 0)}:bs=${_v(fx, 'bs', atFrame, 0)}:rm=${_v(fx, 'rm', atFrame, 0)}:gm=${_v(fx, 'gm', atFrame, 0)}:bm=${_v(fx, 'bm', atFrame, 0)}:rh=${_v(fx, 'rh', atFrame, 0)}:gh=${_v(fx, 'gh', atFrame, 0)}:bh=${_v(fx, 'bh', atFrame, 0)}');
      case 'channelmixer':
        return chain(
            'colorchannelmixer=rr=${_v(fx, 'rr', atFrame, 1)}:rg=${_v(fx, 'rg', atFrame, 0)}:rb=${_v(fx, 'rb', atFrame, 0)}:gr=${_v(fx, 'gr', atFrame, 0)}:gg=${_v(fx, 'gg', atFrame, 1)}:gb=${_v(fx, 'gb', atFrame, 0)}:br=${_v(fx, 'br', atFrame, 0)}:bg=${_v(fx, 'bg', atFrame, 0)}:bb=${_v(fx, 'bb', atFrame, 1)}');
      case 'curves':
        {
          var s = input;
          final m = fx.strVal('master', '');
          if (m.isNotEmpty) {
            s = chain("curves=all='${esc(m)}'");
          }
          final r = fx.strVal('r', '');
          final g = fx.strVal('g', '');
          final b = fx.strVal('b', '');
          if (r.isNotEmpty || g.isNotEmpty || b.isNotEmpty) {
            s = chain(
                "curves=r='${esc(r.isEmpty ? '0/0 1/1' : r)}':g='${esc(g.isEmpty ? '0/0 1/1' : g)}':b='${esc(b.isEmpty ? '0/0 1/1' : b)}'");
          }
          return s;
        }
      case 'hue':
        return chain(
            'hue=h=${_v(fx, 'h', atFrame, 0)}:s=${_v(fx, 's', atFrame, 1)}:b=${_v(fx, 'b', atFrame, 0)}');
      case 'colorcorrect':
        return chain(
            'colorcorrect=saturation=${_v(fx, 'saturation', atFrame, 0)}:analyze=${fx.strVal('analyze', 'manual')}');
      case 'lut3d':
        {
          final f = fx.strVal('file', '');
          if (f.isEmpty) return input;
          final path = resolver?.toAbsolute(f) ?? f;
          return chain(
              "lut3d=file='${esc(path)}':interp=${fx.strVal('interp', 'tetrahedral')}");
        }
      case 'blur':
        {
          final planes = fx.strVal('planes', 'all');
          if (planes == 'luma') {
            return chain(
                'gblur=sigma=${_v(fx, 'sigma', atFrame, 5)}:planes=1');
          }
          return chain('gblur=sigma=${_v(fx, 'sigma', atFrame, 5)}');
        }
      case 'boxblur':
        return chain(
            'boxblur=luma_radius=${_v(fx, 'radius', atFrame, 2)}:luma_power=${_v(fx, 'power', atFrame, 2)}:chroma_radius=${_v(fx, 'radius', atFrame, 2)}:chroma_power=${_v(fx, 'power', atFrame, 2)}');
      case 'sharpen':
        {
          final sz = int.tryParse(fx.strVal('size', '5')) ?? 5;
          final amt = _v(fx, 'amount', atFrame, 1);
          return chain('unsharp=$sz:$sz:$amt:$sz:$sz:$amt');
        }
      case 'denoise':
        return chain(
            'hqdn3d=luma_spatial=${_v(fx, 'luma', atFrame, 4)}:chroma_spatial=${_v(fx, 'chroma', atFrame, 3)}');
      case 'vignette':
        return chain(
            "vignette=angle='PI/${_v(fx, 'angle', atFrame, 0.8)}':mode=${fx.strVal('mode', 'forward')}");
      case 'hflip':
        return chain('hflip');
      case 'vflip':
        return chain('vflip');
      case 'chromakey':
        {
          var s = chain(
              'chromakey=${fx.strVal('color', '0x00ff00')}:similarity=${_v(fx, 'similarity', atFrame, 0.3)}:blend=${_v(fx, 'blend', atFrame, 0.1)}');
          if (fx.values['despill'] == true) {
            s = _appendTo(s, 'despill=type=green');
          }
          return s;
        }
      case 'grayscale':
        return chain('hue=s=0');
      case 'sepia':
        {
          const m = 'rr=.393:rg=.769:rb=.189:gr=.349:gg=.686:gb=.168:br=.272:bg=.534:bb=.131';
          final mix = _v(fx, 'mix', atFrame, 1);
          if (mix == '1.0000') {
            return chain('colorchannelmixer=$m');
          }
          // blend sepia with original via mix filter
          var s = chain("split[a${fx.id}][b${fx.id}]");
          _ctx.emit(
              '[b${fx.id}]colorchannelmixer=$m[bp${fx.id}]');
          final out = _ctx.lab();
          _ctx.emit(
              '[a${fx.id}][bp${fx.id}]blend=all_mode=normal:all_opacity=$mix[$out]');
          return out;
        }
      case 'invert':
        return chain(
            'negate=negate_alpha=${fx.values['alpha'] == true ? 1 : 0}');
      case 'pixelate':
        {
          final sz = max(1, fx.numVal('size', 16).round());
          var s = chain(
              'scale=w=iw/$sz:h=ih/$sz:flags=neighbor');
          s = _appendTo(s, 'scale=w=$width:h=$height:flags=neighbor');
          return s;
        }
      case 'noise':
        return chain(
            'noise=alls=${_v(fx, 'strength', atFrame, 10)}:allf=${fx.values['temporal'] == false ? 'p' : 't+u'}');
      case 'deshake':
        return chain(
            'deshake=x=${_v(fx, 'x', atFrame, 0)}:y=${_v(fx, 'y', atFrame, 0)}:w=${_v(fx, 'w', atFrame, 16)}:h=${_v(fx, 'h', atFrame, 16)}');
      case 'fadein':
        return chain(
            'fade=t=in:st=0:d=${_c(fx.numVal('d', 24) / fps)}:alpha=1:color=${fx.strVal('color', 'black')}');
      case 'fadeout':
        return chain(
            'fade=t=out:st=${_c(localDur / fps - fx.numVal('d', 24) / fps)}:d=${_c(fx.numVal('d', 24) / fps)}:alpha=1:color=${fx.strVal('color', 'black')}');
      case 'drawtext':
        {
          final text = escText(fx.strVal('text', ''));
          final x = _vx(fx, 'x', 0.5) ?? _v(fx, 'x', atFrame, 0.5);
          final y = _vx(fx, 'y', 0.5) ?? _v(fx, 'y', atFrame, 0.5);
          final box = fx.values['box'] == true
              ? ':box=1:boxcolor=${fx.strVal('boxcolor', 'black@0.5')}:boxborderw=10'
              : '';
          final font = fx.strVal('font', '');
          final fontArg = font.isEmpty ? '' : ":font='${esc(font)}'";
          return chain(
              "drawtext=text='$text':fontsize=${_v(fx, 'size', atFrame, 64)}:fontcolor=${fx.strVal('color', 'white')}:x='(w-text_w)*($x)':y='(h-text_h)*($y)'$box$fontArg");
        }
    }
    return input;
  }

  String _appendTo(String input, String filter) {
    final out = _ctx.lab();
    _ctx.emit('[$input]$filter[$out]');
    return out;
  }

  Track? _findTrack(Sequence seq, String clipId) {
    for (final t in seq.tracks) {
      if (t.clips.any((c) => c.id == clipId)) return t;
    }
    return null;
  }

  Clip? _prevClip(Track? t, Clip clip) {
    if (t == null) return null;
    Clip? prev;
    for (final c in t.clips) {
      if (c.id == clip.id) continue;
      if (c.end <= clip.position &&
          (prev == null || c.end > prev.end)) prev = c;
    }
    return prev;
  }

  /// Audio chain for one clip: decode → speed → effects → gain → delay/pad
  /// to full timeline length [winStart..winEnd).
  String? _emitClipAudio(
      Sequence seq, Clip clip, int winStart, int winEnd, int seqOffset) {
    final a = project.assetById(clip.assetId);
    if (a == null) return null;
    if (a.type == AssetType.sequence) {
      // audio of nested sequence: mix sub-sequence audio
      final sub = project.sequenceById(a.sequenceId ?? '');
      if (sub == null) return null;
      return _emitSequenceAudio(sub, clip, winStart, winEnd, seqOffset);
    }
    if (!a.hasAudio && a.type != AssetType.audio) return null;
    if (a.type != AssetType.audio && a.type != AssetType.video) return null;

    final pos = clip.position + seqOffset;
    final visStart = max(pos, winStart);
    final visEnd = min(pos + clip.duration, winEnd);
    if (visEnd <= visStart) return null;
    final speed = clip.speed;
    final inSec = clip.offsetSec + (visStart - pos) / fps * speed;
    final durSec = (visEnd - visStart) / fps * speed;

    if (_isOffline(a)) return null;
    final inp = _clipInput(a, inSec, durSec + 0.5);
    if (inp.index < 0) return null;
    var s = _ctx.lab();
    _ctx.emit(
        '[${inp.index}:a]aresample=${project.sampleRate},aformat=channel_layouts=stereo[$s]');
    if (speed != 1.0) {
      final o = _ctx.lab();
      _ctx.emit('[$s]${_atempoChain(speed)}[$o]');
      s = o;
    }
    // audio effects
    for (final fx in clip.effects) {
      final def = Effects.byId(fx.effectId);
      if (def == null || !def.audio || !fx.enabled) continue;
      s = _applyAudioEffect(s, fx, clip);
    }
    // track gain+pan
    final track = _findTrack(seq, clip.id);
    if (track != null && (track.gain != 1.0 || track.pan != 0)) {
      final o = _ctx.lab();
      var f = '';
      if (track.gain != 1.0) f += 'volume=${_c(track.gain)},';
      if (track.pan != 0) {
        final p = track.pan;
        f += 'pan=stereo|c0=${_c(min(1.0, 1 - p))}*c0|c1=${_c(min(1.0, 1 + p))}*c1';
      }
      if (f.endsWith(',')) f = f.substring(0, f.length - 1);
      _ctx.emit('[$s]$f[$o]');
      s = o;
    }
    // position on timeline: delay then pad to full window length
    final relMs = ((visStart - winStart) / fps * 1000).round();
    final totalSec = (winEnd - winStart) / fps;
    final o = _ctx.lab();
    _ctx.emit(
        '[$s]adelay=${relMs}ms:all=1,apad,atrim=0:${_c(totalSec)}[$o]');
    return o;
  }

  String? _emitSequenceAudio(
      Sequence sub, Clip clip, int winStart, int winEnd, int seqOffset) {
    final streams = <String>[];
    final pos = clip.position + seqOffset;
    final visStart = max(pos, winStart);
    final visEnd = min(pos + clip.duration, winEnd);
    if (visEnd <= visStart) return null;
    for (final t in sub.audioTracks) {
      if (t.muted) continue;
      for (final c in t.sorted) {
        if (!c.enabled) continue;
        // sub clip position relative to sequence clip's window
        final s = _emitClipAudio(sub, c, visStart - pos, visEnd - pos, 0);
        if (s != null) streams.add(s);
      }
    }
    if (streams.isEmpty) return null;
    String mixed;
    if (streams.length == 1) {
      mixed = streams.first;
    } else {
      final out = _ctx.lab();
      _ctx.emit(
          '${streams.map((e) => '[$e]').join()}amix=inputs=${streams.length}:duration=longest:normalize=0[$out]');
      mixed = out;
    }
    // shift the sub-sequence mix into the parent window: sub window starts
    // at parent-time (visStart); the returned stream must cover the parent
    // render window [winStart, winEnd).
    final relMs = ((visStart - winStart) / fps * 1000).round();
    final totalSec = (winEnd - winStart) / fps;
    final o = _ctx.lab();
    _ctx.emit(
        '[$mixed]adelay=${relMs}ms:all=1,apad,atrim=0:${_c(totalSec)}[$o]');
    return o;
  }

  String _atempoChain(double speed) {
    // atempo accepts 0.5..100; chain for extreme slowdowns
    final parts = <String>[];
    var v = speed;
    while (v < 0.5) {
      parts.add('atempo=0.5');
      v /= 0.5;
    }
    while (v > 100) {
      parts.add('atempo=100');
      v /= 100;
    }
    parts.add('atempo=${_c(v)}');
    return parts.join(',');
  }

  String _applyAudioEffect(String input, ClipEffect fx, Clip clip) {
    String chain(String f) {
      final out = _ctx.lab();
      _ctx.emit('[$input]$f[$out]');
      return out;
    }

    switch (fx.effectId) {
      case 'gain':
        {
          final expr = _vx(fx, 'v', 0);
          if (expr != null) {
            return chain("volume='pow(10,($expr)/20)':eval=frame");
          }
          return chain('volume=${_c(fx.numVal('v', 0))}dB');
        }
      case 'pan':
        {
          final p = fx.numVal('p', 0);
          return chain(
              'pan=stereo|c0=${_c(min(1.0, 1 - p))}*c0|c1=${_c(min(1.0, 1 + p))}*c1');
        }
      case 'afadein':
        return chain(
            'afade=t=in:st=0:d=${_c(fx.numVal('d', 24) / fps)}');
      case 'afadeout':
        return chain(
            'afade=t=out:st=${_c(clip.duration / fps - fx.numVal('d', 24) / fps)}:d=${_c(fx.numVal('d', 24) / fps)}');
      case 'aeq':
        return chain(
            'equalizer=f=${_v(fx, 'lowf', 0, 200)}:t=q:w=1:g=${_v(fx, 'low', 0, 0)},'
            'equalizer=f=${_v(fx, 'midf', 0, 1000)}:t=q:w=1:g=${_v(fx, 'mid', 0, 0)},'
            'equalizer=f=${_v(fx, 'highf', 0, 6000)}:t=q:w=1:g=${_v(fx, 'high', 0, 0)}');
      case 'acompressor':
        return chain(
            'acompressor=threshold=${_v(fx, 'threshold', 0, 0.09)}:ratio=${_v(fx, 'ratio', 0, 3)}:attack=${_v(fx, 'attack', 0, 20)}:release=${_v(fx, 'release', 0, 250)}:makeup=${_v(fx, 'makeup', 0, 2)}');
      case 'alimiter':
        return chain(
            'alimiter=limit=${_v(fx, 'limit', 0, 0.9)}:attack=${_v(fx, 'attack', 0, 5)}:release=${_v(fx, 'release', 0, 50)}');
      case 'loudnorm':
        return chain(
            'loudnorm=I=${_v(fx, 'i', 0, -16)}:TP=${_v(fx, 'tp', 0, -1.5)}:LRA=${_v(fx, 'lra', 0, 11)}');
      case 'agate':
        return chain(
            'agate=threshold=${_v(fx, 'threshold', 0, 0.02)}:ratio=${_v(fx, 'ratio', 0, 2)}:attack=${_v(fx, 'attack', 0, 20)}:release=${_v(fx, 'release', 0, 250)}');
      case 'aecho':
        return chain(
            'aecho=0.8:0.8:${_v(fx, 'delay', 0, 500)}:${_v(fx, 'decay', 0, 0.5)}');
      case 'highpass':
        return chain('highpass=f=${_v(fx, 'f', 0, 200)}');
      case 'lowpass':
        return chain('lowpass=f=${_v(fx, 'f', 0, 3000)}');
    }
    return input;
  }
}
