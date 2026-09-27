import 'dart:io';
import 'dart:math';

import 'package:xml/xml.dart';

import '../models/model.dart';

/// Imports a .kdenlive project (MLT XML) into our project model.
///
/// Structure: chains/producers are bin+timeline producers, tractors with
/// sequenceproperties are sequences, each timeline track is a tractor with
/// two playlists (front/back for mixes). Clip effects are `filter` children
/// of `entry` elements.
class KdenliveImport {
  static double _fps = 30;
  static int _w = 1920, _h = 1080;
  static String _root = '';

  static Future<Project> run(String path) async {
    final xml = File(path).readAsStringSync();
    final doc = XmlDocument.parse(xml);
    final mlt = doc.findElements('mlt').first;
    _root = mlt.getAttribute('root') ?? File(path).parent.path;
    // prefer the directory containing the kdenlive file
    final fileDir = File(path).parent.path;
    if (!Directory(_root).existsSync()) _root = fileDir;

    final prof = mlt.findElements('profile').firstOrNull;
    if (prof != null) {
      _w = int.parse(prof.getAttribute('width') ?? '1920');
      _h = int.parse(prof.getAttribute('height') ?? '1080');
      _fps = (int.parse(prof.getAttribute('frame_rate_num') ?? '30')) /
          (int.parse(prof.getAttribute('frame_rate_den') ?? '1'));
    }

    final fnum = int.tryParse(prof?.getAttribute('frame_rate_num') ?? '');
    final fden = int.tryParse(prof?.getAttribute('frame_rate_den') ?? '');
    final project = Project(name: _basename(path).replaceAll('.kdenlive', ''),
        width: _w,
        height: _h,
        fps: (fnum != null && fden != null && fden != 0)
            ? Rational(fnum, fden)
            : Rational((_fps * 1000).round(), 1000),
        sampleRate: 48000);

    // ---- collect producers and chains ----
    final producers = <String, XmlElement>{};
    for (final e in mlt.findElements('producer')) {
      producers[e.getAttribute('id')!] = e;
    }
    for (final e in mlt.findElements('chain')) {
      producers[e.getAttribute('id')!] = e;
    }

    final assetByKid = <String, MediaAsset>{};

    MediaAsset assetFor(XmlElement prod) {
      final kid = _prop(prod, 'kdenlive:id') ?? prod.getAttribute('id')!;
      if (assetByKid.containsKey(kid)) return assetByKid[kid]!;
      final service = _prop(prod, 'mlt_service') ?? '';
      final resource = _prop(prod, 'resource') ?? '';
      final name = _prop(prod, 'kdenlive:clipname') ??
          _basename(resource.isEmpty ? 'clip $kid' : resource);
      MediaAsset a;
      if (service == 'kdenlivetitle' || _prop(prod, 'xmldata') != null) {
        a = MediaAsset(
            id: kid,
            type: AssetType.title,
            name: name,
            title: _parseTitle(_prop(prod, 'xmldata') ?? ''),
            durationSec: _len(prod) / _fps,
            hasVideo: true);
      } else if (service == 'color' || resource.startsWith('color:')) {
        a = MediaAsset(
            id: kid,
            type: AssetType.color,
            name: name,
            color: _kdenliveColor(resource),
            durationSec: _len(prod) / _fps,
            hasVideo: true);
      } else if (service == 'qimage' || _isImage(resource)) {
        a = MediaAsset(
            id: kid,
            type: AssetType.image,
            name: name,
            relPath: resource,
            fileName: _basename(resource),
            durationSec: _len(prod) / _fps,
            hasVideo: true);
      } else {
        // avformat producer/chain
        final isTimewarp = service == 'timewarp' ||
            _prop(prod, 'kdenlive:orig_service') == 'timewarp';
        final res = resource.startsWith('timewarp:')
            ? resource.split(':').skip(2).join(':')
            : resource;
        final hasV = _prop(prod, 'meta.media.nb_streams') != null
            ? _prop(prod, 'meta.media.0.stream.type') == 'video'
            : _hasVideoExt(res);
        final hasA = hasV ||
            _prop(prod, 'meta.media.1.stream.type') == 'audio' ||
            _hasAudioExt(res);
        a = MediaAsset(
            id: kid,
            type: hasV ? AssetType.video : AssetType.audio,
            name: name,
            relPath: res,
            fileName: _basename(res),
            hash: _prop(prod, 'kdenlive:file_hash'),
            fileSize: int.tryParse(_prop(prod, 'kdenlive:file_size') ?? '') ?? 0,
            durationSec: _len(prod) / _fps,
            width: int.tryParse(_prop(prod, 'meta.media.width') ?? '') ?? 0,
            height:
                int.tryParse(_prop(prod, 'meta.media.height') ?? '') ?? 0,
            fps: double.tryParse(_prop(prod, 'meta.media.frame_rate_num') ?? '') ??
                0,
            hasVideo: hasV,
            hasAudio: hasA);
        if (isTimewarp) {
          a.meta = {'timewarp': true};
        }
      }
      assetByKid[kid] = a;
      project.assets.add(a);
      return a;
    }

    // ---- tracks ----
    // track tractors: a tractor whose tracks are playlists (2-track pair)
    final tractorById = <String, XmlElement>{};
    for (final e in mlt.findElements('tractor')) {
      tractorById[e.getAttribute('id')!] = e;
    }
    final playlistById = <String, XmlElement>{};
    for (final e in mlt.findElements('playlist')) {
      if (e.getAttribute('id') == 'main_bin') continue;
      playlistById[e.getAttribute('id')!] = e;
    }

    Track importTrack(XmlElement tractor) {
      final tracks = tractor.findElements('track').toList();
      final audio = _prop(tractor, 'kdenlive:audio_track') == '1';
      final t = Track(
          id: tractor.getAttribute('id')!,
          kind: audio ? TrackKind.audio : TrackKind.video,
          name: _prop(tractor, 'kdenlive:track_name') ??
              (audio ? 'A' : 'V'));
      if (tracks.isEmpty) return t;
      // front playlist is first track element (may be hidden side)
      final pl = playlistById[tracks.first.getAttribute('producer')];
      if (pl == null) return t;
      var pos = 0;
      for (final e in pl.children.whereType<XmlElement>()) {
        if (e.name.local == 'blank') {
          pos += _t(e.getAttribute('length') ?? '0');
          continue;
        }
        if (e.name.local != 'entry') continue;
        final prod = producers[e.getAttribute('producer')];
        if (prod == null) {
          continue;
        }
        final inS = _ts(e.getAttribute('in') ?? '0');
        final outS = _ts(e.getAttribute('out') ?? '0');
        final asset = assetFor(prod);
        final dur = max(1, ((outS - inS) * _fps).round() + 1);
        final clip = Clip(
          id: e.getAttribute('id') ?? 'k$pos',
          assetId: asset.id,
          position: pos,
          duration: dur,
          offsetSec: inS,
          name: asset.name,
        );
        // timewarp producers → speed; kdenlive in/out are in warped
        // (output) time, so the source offset scales by speed
        if (asset.meta?['timewarp'] == true) {
          clip.speed = double.tryParse(
                  _prop(prod, 'warp_speed') ?? _prop(prod, 'speed') ?? '') ??
              _timewarpSpeed(_prop(prod, 'resource') ?? '');
          clip.offsetSec = inS * clip.speed;
        }
        // entry filters → effects
        for (final f in e.findElements('filter')) {
          final fx = _importFilter(f);
          if (fx != null) clip.effects.add(fx);
        }
        // entry-level transitions (same-track mix via <transition> in a
        // nested tractor entry are rare; kdenlive uses a second playlist
        // with its own entries for mixes — handled roughly below)
        t.clips.add(clip);
        pos = clip.end;
      }
      return t;
    }

    // find sequence tractors
    final seqTractors = <XmlElement>[];
    XmlElement? mainTractor;
    for (final tr in mlt.findElements('tractor')) {
      if (_prop(tr, 'kdenlive:projectTractor') == '1') {
        mainTractor = tr;
        continue;
      }
      if (_prop(tr, 'kdenlive:uuid') != null ||
          _prop(tr, 'kdenlive:sequenceproperties.documentuuid') != null) {
        seqTractors.add(tr);
      }
    }

    final seqByTractorId = <String, Sequence>{};
    for (final tr in seqTractors) {
      final seq = Sequence(
          id: _prop(tr, 'kdenlive:uuid') ?? tr.getAttribute('id')!,
          name: _prop(tr, 'kdenlive:clipname') ?? 'Sequence');
      for (final te in tr.findElements('track')) {
        final tid = te.getAttribute('producer')!;
        final tt = tractorById[tid];
        if (tt != null) {
          // track tractor → import its front playlist
          seq.tracks.add(importTrack(tt));
        } else if (producers.containsKey(tid)) {
          // direct producer track (e.g. the black background)
          continue;
        } else if (playlistById.containsKey(tid)) {
          // bare playlist track
          final t = _importBarePlaylist(
              playlistById[tid]!, producers, assetFor, seq.tracks.length);
          seq.tracks.add(t);
        }
      }
      seqTractorFixOrder(seq);
      project.sequences.add(seq);
      seqByTractorId[tr.getAttribute('id')!] = seq;
      // bin asset for the sequence
      project.assets.add(MediaAsset(
          id: 'seqasset_${seq.id}',
          type: AssetType.sequence,
          name: seq.name,
          sequenceId: seq.id,
          hasVideo: true,
          hasAudio: true));
    }

    // main timeline tractor → wraps a sequence clip
    if (mainTractor != null) {
      final mainSeq = Sequence(id: 'main', name: 'Timeline');
      for (final te in mainTractor.findElements('track')) {
        final tid = te.getAttribute('producer')!;
        final sub = seqByTractorId[tid];
        if (sub != null) {
          final t = Track(
              id: 'mt_$tid', kind: TrackKind.video, name: 'V1');
          final durF = sub.duration;
          t.clips.add(Clip(
              id: 'mclip_$tid',
              assetId: 'seqasset_${sub.id}',
              position: 0,
              duration: durF,
              name: sub.name));
          mainSeq.tracks.add(t);
          continue;
        }
        final tt = tractorById[tid];
        if (tt != null) mainSeq.tracks.add(importTrack(tt));
      }
      if (mainSeq.tracks.isNotEmpty) {
        project.sequences.add(mainSeq);
        project.mainSequenceId = mainSeq.id;
      }
    }
    if (project.mainSequenceId.isEmpty && project.sequences.isNotEmpty) {
      project.mainSequenceId = project.sequences.last.id;
    }

    // link A/V pairs: same asset, same position, different kind
    for (final seq in project.sequences) {
      final vs = seq.videoTracks.expand((t) => t.clips).toList();
      for (final t in seq.audioTracks) {
        for (final c in t.clips) {
          final mate = vs.where((v) =>
              v.assetId == c.assetId && (v.position - c.position).abs() < 2);
          if (mate.isNotEmpty) {
            final g = 'g_${mate.first.id}';
            c.linkGroup = g;
            mate.first.linkGroup = g;
          }
        }
      }
    }
    return project;
  }

  static void seqTractorFixOrder(Sequence seq) {
    // kdenlive XML lists tracks bottom-up (last = topmost in compositing);
    // our convention: videoTracks[0] = topmost. Reverse both groups.
    final v = seq.videoTracks.reversed.toList();
    final a = seq.audioTracks.reversed.toList();
    seq.tracks
      ..clear()
      ..addAll(v)
      ..addAll(a);
    // kdenlive GUI numbers topmost video V1 — rename to match
    var vn = 1;
    for (final t in seq.videoTracks.reversed) {
      if (!t.name.startsWith('V')) t.name = 'V$vn';
      vn++;
    }
    var an = 1;
    for (final t in seq.audioTracks.reversed) {
      if (!t.name.startsWith('A')) t.name = 'A$an';
      an++;
    }
  }

  static Track _importBarePlaylist(
      XmlElement pl,
      Map<String, XmlElement> producers,
      MediaAsset Function(XmlElement) assetFor,
      int idx) {
    final t = Track(
        id: pl.getAttribute('id')!,
        kind: TrackKind.video,
        name: 'V${idx + 1}');
    var pos = 0;
    for (final e in pl.children.whereType<XmlElement>()) {
      if (e.name.local == 'blank') {
        pos += _t(e.getAttribute('length') ?? '0');
        continue;
      }
      if (e.name.local != 'entry') continue;
      final prod = producers[e.getAttribute('producer')];
      if (prod == null) continue;
      final inS = _ts(e.getAttribute('in') ?? '0');
      final outS = _ts(e.getAttribute('out') ?? '0');
      final asset = assetFor(prod);
      final clip = Clip(
        id: e.getAttribute('id') ?? 'k$pos',
        assetId: asset.id,
        position: pos,
        duration: max(1, ((outS - inS) * _fps).round() + 1),
        offsetSec: inS,
        name: asset.name,
      );
      for (final f in e.findElements('filter')) {
        final fx = _importFilter(f);
        if (fx != null) clip.effects.add(fx);
      }
      t.clips.add(clip);
      pos = clip.end;
    }
    return t;
  }

  // ------------------------------------------------------------------
  static ClipEffect? _importFilter(XmlElement f) {
    final kid = _prop(f, 'kdenlive_id') ?? _prop(f, 'mlt_service') ?? '';
    if (_prop(f, 'internal_added') != null || _prop(f, 'disable') == '1') {
      return null;
    }
    ClipEffect fx(String id) =>
        ClipEffect(id: 'fx${f.getAttribute('id')}', effectId: id);

    double prop(String n, [double def = 0]) =>
        double.tryParse(_prop(f, n) ?? '') ?? def;

    // "t=v;t=v" animated strings → keyframes (seconds → frames)
    List<Keyframe>? keys(String n, {double scale = 1}) {
      final v = _prop(f, n);
      if (v == null || !v.contains('=')) return null;
      final out = <Keyframe>[];
      for (final part in v.split(';')) {
        final kv = part.split('=');
        if (kv.length != 2) continue;
        final t = kv[0].contains(':') ? _ts(kv[0]) : double.tryParse(kv[0]);
        final val = double.tryParse(kv[1]);
        if (t == null || val == null) continue;
        // frame keys are relative to clip start
        final fr = kv[0].contains(':') ? (t * _fps).round() : t.round();
        out.add(Keyframe(max(0, fr), val * scale));
      }
      return out.isEmpty ? null : out;
    }

    switch (kid) {
      case 'avfilter.eq':
      case 'eq':
        final e = fx('eq');
        for (final k in [
          'brightness', 'contrast', 'saturation', 'gamma',
          'gamma_r', 'gamma_g', 'gamma_b'
        ]) {
          e.values[k] = prop('av.$k', prop(k, 0));
        }
        e.values['contrast'] = prop('av.contrast', 1);
        e.values['saturation'] = prop('av.saturation', 1);
        e.values['gamma'] = prop('av.gamma', 1);
        e.values['gamma_r'] = prop('av.gamma_r', 1);
        e.values['gamma_g'] = prop('av.gamma_g', 1);
        e.values['gamma_b'] = prop('av.gamma_b', 1);
        return e;
      case 'avfilter.colorlevels':
        final e = fx('levels');
        e.values['rimin'] = prop('av.rimin');
        e.values['rimax'] = prop('av.rimax', 1);
        e.values['gammaval'] = prop('av.rigamma', 1);
        e.values['romin'] = prop('av.romin');
        e.values['romax'] = prop('av.romax', 1);
        return e;
      case 'avfilter.colorchannelmixer':
        final e = fx('channelmixer');
        for (final k in ['rr', 'rg', 'rb', 'gr', 'gg', 'gb', 'br', 'bg', 'bb']) {
          e.values[k] = prop('av.$k', k == 'rr' || k == 'gg' || k == 'bb' ? 1 : 0);
        }
        return e;
      case 'avfilter.colorbalance':
        final e = fx('colorbalance');
        for (final k in ['rs', 'gs', 'bs', 'rm', 'gm', 'bm', 'rh', 'gh', 'bh']) {
          e.values[k] = prop('av.$k');
        }
        return e;
      case 'avfilter.hue':
        final e = fx('hue');
        e.values['h'] = prop('av.h');
        e.values['s'] = prop('av.s', 1);
        e.values['b'] = prop('av.b');
        return e;
      case 'avfilter.gblur':
        final e = fx('blur');
        e.values['sigma'] = prop('av.sigma', 5);
        return e;
      case 'avfilter.unsharp':
        final e = fx('sharpen');
        e.values['amount'] = prop('av.lamount', prop('av.la', 1));
        return e;
      case 'avfilter.vignette':
        final e = fx('vignette');
        return e;
      case 'brightness':
        {
          // fade_from_black / fade_to_black animate 'alpha' 0..1
          final alpha = keys('alpha');
          if (alpha != null) {
            final e = fx('opacity');
            e.keyframes['op'] = alpha;
            e.values['op'] = alpha.first.value;
            return e;
          }
          final e = fx('eq');
          e.values['brightness'] = prop('level', 0) - 1;
          return e;
        }
      case 'volume':
        {
          // kdenlive gain is already dB
          final g = keys('gain') ?? keys('level');
          final e = fx('gain');
          if (g != null) {
            e.keyframes['v'] =
                g.map((k) => Keyframe(k.frame, k.value)).toList();
            e.values['v'] = e.keyframes['v']!.first.value;
          } else {
            e.values['v'] = prop('gain', 0);
          }
          return e;
        }
      case 'panner':
        final e = fx('pan');
        e.values['p'] = (prop('start', 0.5) - 0.5) * 2;
        return e;
      case 'dynamictext':
        final e = fx('drawtext');
        e.values['text'] = _prop(f, 'argument') ?? '';
        e.values['size'] = prop('size', 64);
        e.values['color'] = _kdenliveColor(_prop(f, 'fgcolour') ?? '0xffffffff');
        final geom = _prop(f, 'geometry') ?? '';
        final parts = geom.split(RegExp(r'[ ,]')).where((x) => x.isNotEmpty);
        final gp = parts.map((e) => double.tryParse(e) ?? 0).toList();
        if (gp.length >= 4) {
          e.values['x'] = gp[0] / _w + (gp[2] / _w) / 2;
          e.values['y'] = gp[1] / _h + (gp[3] / _h) / 2;
        }
        return e;
      case 'qtblend':
        {
          final e = fx('transform');
          final rect = _prop(f, 'rect') ?? '';
          final parts = rect.split(RegExp(r'[ ,]')).where((x) => x.isNotEmpty);
          final rp = parts.map((e) => double.tryParse(e) ?? 0).toList();
          if (rp.length >= 4) {
            e.values['x'] = (rp[0] + rp[2] / 2 - _w / 2) / _w;
            e.values['y'] = (rp[1] + rp[3] / 2 - _h / 2) / _h;
            e.values['sx'] = rp[2] / _w;
            e.values['sy'] = rp[3] / _h;
          }
          e.values['rot'] = prop('rotation');
          e.values['op'] = _prop(f, 'compositing') == '1' ? 1.0 : prop('opacity', 1);
          return e;
        }
      case 'lift_gamma_gain':
        {
          final e = fx('colorbalance');
          // r/g/b packed "r g b" floats in lift/gamma/gain props
          final lift = _rgbTriple(_prop(f, 'lift'));
          final gamma = _rgbTriple(_prop(f, 'gamma'));
          final gain = _rgbTriple(_prop(f, 'gain'));
          e.values['rs'] = lift[0];
          e.values['gs'] = lift[1];
          e.values['bs'] = lift[2];
          e.values['rm'] = (gamma[0] - 1);
          e.values['gm'] = (gamma[1] - 1);
          e.values['bm'] = (gamma[2] - 1);
          e.values['rh'] = (gain[0] - 1);
          e.values['gh'] = (gain[1] - 1);
          e.values['bh'] = (gain[2] - 1);
          return e;
        }
      case 'movit.lift_gamma_gain':
        {
          final e = fx('colorbalance');
          final lift = _rgbTriple(_prop(f, 'lift'));
          final gamma = _rgbTriple(_prop(f, 'gamma'));
          final gain = _rgbTriple(_prop(f, 'gain'));
          e.values['rs'] = lift[0];
          e.values['gs'] = lift[1];
          e.values['bs'] = lift[2];
          e.values['rm'] = (gamma[0] - 1);
          e.values['gm'] = (gamma[1] - 1);
          e.values['bm'] = (gamma[2] - 1);
          e.values['rh'] = (gain[0] - 1);
          e.values['gh'] = (gain[1] - 1);
          e.values['bh'] = (gain[2] - 1);
          return e;
        }
      case 'audiolevel':
      case 'audiowaveform':
      case 'avfilter.avectorscope':
      case 'avfilter.oscilloscope':
        return null; // meters/scopes
      default:
        return null;
    }
  }

  static List<double> _rgbTriple(String? s) {
    if (s == null) return [0, 0, 0];
    final parts = s.split(RegExp(r'[ ,;]'))
        .map((e) => double.tryParse(e) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.take(3).toList();
  }

  static double _timewarpSpeed(String resource) {
    // "timewarp:2.0:path"
    final p = resource.split(':');
    if (p.length > 1) return double.tryParse(p[1]) ?? 1;
    return 1;
  }

  static Map<String, dynamic> _parseTitle(String xmlData) {
    final items = <Map<String, dynamic>>[];
    try {
      final doc = XmlDocument.parse(xmlData);
      for (final item in doc.findAllElements('item')) {
        final type = item.getAttribute('type') ?? '';
        if (type.contains('Text')) {
          final content = item.findElements('content').firstOrNull;
          final pos = item.findElements('position').firstOrNull;
          final fontSize = double.tryParse(
                  content?.getAttribute('font-size') ??
                      content?.getAttribute('fontSize') ??
                      '') ??
              48;
          final x = double.tryParse(pos?.getAttribute('x') ?? '') ?? 0;
          final y = double.tryParse(pos?.getAttribute('y') ?? '') ?? 0;
          items.add({
            'type': 'text',
            'text': content?.innerText ?? '',
            'x': (x / _w).clamp(0.0, 1.0),
            'y': (y / _h).clamp(0.0, 1.0),
            'size': (fontSize / _h).clamp(0.01, 0.5),
            'color': _kdenliveColor(
                content?.getAttribute('color') ??
                    content?.getAttribute('font-color') ??
                    '0xffffffff'),
          });
        } else if (type.contains('Rect')) {
          final pos = item.findElements('position').firstOrNull;
          items.add({
            'type': 'rect',
            'x': (double.tryParse(pos?.getAttribute('x') ?? '') ?? 0) / _w,
            'y': (double.tryParse(pos?.getAttribute('y') ?? '') ?? 0) / _h,
            'w': (double.tryParse(pos?.getAttribute('w') ?? '') ?? 200) / _w,
            'h': (double.tryParse(pos?.getAttribute('h') ?? '') ?? 40) / _h,
            'color': 'white',
          });
        }
      }
    } catch (_) {}
    return {'items': items};
  }

  // ------------------------------------------------------------------
  static String? _prop(XmlElement e, String name) {
    for (final p in e.findElements('property')) {
      if (p.getAttribute('name') == name) return p.innerText;
    }
    return null;
  }

  static int _t(String s) => (_ts(s) * _fps).round();

  /// "HH:MM:SS.mmm" or plain frame count or seconds → seconds.
  static double _ts(String s) {
    if (s.contains(':')) {
      final p = s.split(':');
      final h = double.tryParse(p[0]) ?? 0;
      final m = double.tryParse(p[1]) ?? 0;
      final sec = double.tryParse(p[2]) ?? 0;
      return h * 3600 + m * 60 + sec;
    }
    final v = double.tryParse(s) ?? 0;
    // bare integers in MLT are frames
    return v / _fps;
  }

  static double _len(XmlElement prod) {
    final l = int.tryParse(_prop(prod, 'length') ?? '') ?? 0;
    return l > 0 && l < 1e9 ? l.toDouble() : 150;
  }

  static String _basename(String p) {
    final s = p.replaceAll('\\', '/');
    return s.split('/').last;
  }

  static String _kdenliveColor(String s) {
    var v = s.replaceAll('#', '').replaceAll('0x', '');
    // strip anything that isn't hex (MLT escapes ':' inside values)
    v = v.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    if (v.isEmpty) return '0x000000';
    if (v.length == 8) v = v.substring(2);
    if (v.length > 6) v = v.substring(0, 6);
    return '0x$v';
  }

  static bool _isImage(String p) =>
      RegExp(r'\.(png|jpe?g|webp|bmp|tiff?)$', caseSensitive: false)
          .hasMatch(p);
  static bool _hasVideoExt(String p) =>
      RegExp(r'\.(mp4|mov|mkv|avi|webm|mts|m2ts|mpg|mpeg|ts)$',
              caseSensitive: false)
          .hasMatch(p);
  static bool _hasAudioExt(String p) =>
      RegExp(r'\.(wav|mp3|aac|flac|ogg|m4a)$', caseSensitive: false)
          .hasMatch(p);
}
