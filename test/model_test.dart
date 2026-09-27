import 'dart:convert';
import 'dart:io';

import 'package:dartalive/models/model.dart';
import 'package:dartalive/models/sequence_ops.dart';
import 'package:dartalive/io/dal_file.dart';
import 'package:dartalive/io/media_resolver.dart';
import 'package:dartalive/io/kdenlive_import.dart';
import 'package:dartalive/engine/graph.dart';
import 'package:dartalive/state/shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model', () {
    test('project json round-trip', () {
      final p = Project(name: 'T', width: 1920, height: 1080, fps: const Rational(60, 1));
      final seq = Sequence(id: 's1', name: 'Seq');
      seq.tracks.add(Track(id: 't1', kind: TrackKind.video, name: 'V1'));
      final c = Clip(id: 'c1', assetId: 'a1', position: 30, duration: 60,
          offsetSec: 1.5, speed: 1.5, name: 'clip');
      c.effects.add(ClipEffect(id: 'e1', effectId: 'eq', values: {'gamma': 1.2}));
      c.transition = ClipTransition(kind: TransitionKind.wipeLeft, duration: 24);
      seq.tracks.first.clips.add(c);
      seq.markers.add(Marker(10, 'm1'));
      p.sequences.add(seq);
      p.mainSequenceId = 's1';
      p.assets.add(MediaAsset(id: 'a1', type: AssetType.video, name: 'v.mp4',
          relPath: 'v.mp4', hash: 'abc', fileSize: 10, width: 100, height: 50,
          fps: 30, hasVideo: true, hasAudio: true));

      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      final q = Project.fromJson(j);
      expect(q.name, 'T');
      expect(q.fpsValue, 60);
      expect(q.sequences.length, 1);
      final c2 = q.sequences.first.tracks.first.clips.first;
      expect(c2.position, 30);
      expect(c2.speed, 1.5);
      expect(c2.transition!.kind, TransitionKind.wipeLeft);
      expect(c2.effects.first.values['gamma'], 1.2);
      expect(q.assets.first.hash, 'abc');
    });

    test('keyframe eval + expression', () {
      final keys = [Keyframe(0, 0), Keyframe(30, 1), Keyframe(60, 0)];
      expect(evalKeyframes(keys, 15, 0), closeTo(0.5, 1e-9));
      expect(evalKeyframes(keys, 0, 0), 0);
      expect(evalKeyframes(keys, 90, 0), 0);
      final hold = [Keyframe(0, 0, interp: InterpMode.hold), Keyframe(30, 1)];
      expect(evalKeyframes(hold, 15, 0), 0);
      final expr = keyframesToExpr(keys, 30, 0);
      expect(expr, isNotNull);
      expect(expr, contains('if(lt(t,'));
      expect(keyframesToExpr([Keyframe(0, 1)], 30, 1), isNull);
    });
  });

  group('sequence ops', () {
    Sequence mkSeq() {
      final s = Sequence(id: 's', name: 'x');
      s.tracks.add(Track(id: 'v1', kind: TrackKind.video));
      return s;
    }

    test('split cuts a clip into two', () {
      final s = mkSeq();
      s.tracks.first.clips
          .add(Clip(id: 'a', assetId: 'm', position: 0, duration: 100));
      final created = SeqOps.splitAt(s, 40, 30);
      expect(s.tracks.first.clips.length, 2);
      final left = s.tracks.first.clips.firstWhere((c) => c.id == 'a');
      final right = created.first;
      expect(left.duration, 40);
      expect(right.position, 40);
      expect(right.duration, 60);
      expect(right.offsetSec, closeTo(40 / 30, 1e-6));
    });

    test('removeClip ripple shifts later clips', () {
      final s = mkSeq();
      s.tracks.first.clips
        ..add(Clip(id: 'a', assetId: 'm', position: 0, duration: 30))
        ..add(Clip(id: 'b', assetId: 'm', position: 50, duration: 30));
      SeqOps.removeClip(s, 'a', ripple: true);
      final b = s.tracks.first.clips.first;
      expect(b.position, 20);
    });

    test('trim respects media bounds and collisions', () {
      final s = mkSeq();
      s.tracks.first.clips
        ..add(Clip(id: 'a', assetId: 'm', position: 0, duration: 60, offsetSec: 1))
        ..add(Clip(id: 'b', assetId: 'm', position: 60, duration: 60));
      // extend a right into b: blocked
      expect(SeqOps.trimRight(s, s.tracks.first.clips[0], 80, 30), isFalse);
      // trim a's left edge
      expect(SeqOps.trimLeft(s, s.tracks.first.clips[0], 15, 30), isTrue);
      expect(s.tracks.first.clips[0].position, 15);
      expect(s.tracks.first.clips[0].offsetSec, closeTo(1.5, 1e-6));
    });

    test('resolvePosition slides out of overlaps', () {
      final t = Track(id: 'v1', kind: TrackKind.video);
      t.clips.add(Clip(id: 'a', assetId: 'm', position: 10, duration: 30));
      final p = SeqOps.resolvePosition(t, 20, 10);
      expect(p == 40 || p == 0, isTrue);
    });

    test('snap snaps to nearest edge', () {
      final pts = [0, 30, 60];
      expect(SeqOps.snap(28, pts, 5), 30);
      expect(SeqOps.snap(12, pts, 5), 12);
    });
  });

  group('dal file', () {
    test('round-trip through zip', () async {
      final dir = Directory.systemTemp.createTempSync('daltest');
      final p = Project(name: 'ZipTest');
      p.sequences.add(Sequence(id: 's1', name: 's'));
      p.mainSequenceId = 's1';
      final f = '${dir.path}/x.dal';
      await DalFile.write(f, p);
      expect(DalFile.isDal(f), isTrue);
      final q = await DalFile.read(f);
      expect(q.name, 'ZipTest');
      expect(q.mainSequenceId, 's1');
      dir.deleteSync(recursive: true);
    });
  });

  group('media resolver', () {
    test('relative/absolute round-trip', () {
      final r = MediaResolver('/proj/dir');
      expect(r.toRelative('/proj/dir/media/a.mp4'), 'media/a.mp4');
      expect(r.toAbsolute('media/a.mp4'), '/proj/dir/media/a.mp4');
      expect(r.toAbsolute('/x/y.mp4'), '/x/y.mp4');
      expect(r.toRelative('/proj/dir/sub/../b.mp4'), isNot('..'));
    });
  });

  group('kdenlive import', () {
    final kdPath =
        '/home/calico/dartalive/.devinorium-attachments/1e101804-a191-46c8-a343-864bece5c586/0_dance.kdenlive';
    test('imports sequences, tracks, clips, effects', () async {
      if (!File(kdPath).existsSync()) return;
      final p = await KdenliveImport.run(kdPath);
      expect(p.fpsValue, 60);
      expect(p.assets.length, greaterThan(5));
      expect(p.sequences.isNotEmpty, isTrue);
      final main = p.mainSequence!;
      expect(main.duration, greaterThan(0));
      // the edit lives in nested sequence "Sequence 1"
      final inner = p.sequences.firstWhere((s) => s.name == 'Sequence 1');
      final clips = inner.tracks.expand((t) => t.clips).toList();
      expect(clips.length, greaterThan(15));
      // effects were mapped
      final fxCount = clips.fold(0, (n, c) => n + c.effects.length);
      expect(fxCount, greaterThan(10));
      // color grading mapped
      expect(
          clips.expand((c) => c.effects).any((e) => e.effectId == 'eq'),
          isTrue);
      // audio tracks present
      expect(inner.audioTracks.expand((t) => t.clips).length, greaterThan(3));
    });
  });

  group('graph builder', () {
    test('emits a valid filter graph for a simple edit', () async {
      final p = Project(name: 'g', width: 1280, height: 720, fps: const Rational(30, 1));
      p.assets.add(MediaAsset(
          id: 'a1', type: AssetType.video, name: 'v.mp4',
          relPath: '/nonexistent.mp4', hasVideo: true, hasAudio: true,
          durationSec: 30, fps: 30));
      final seq = Sequence(id: 's', name: 's');
      seq.tracks.add(Track(id: 'v', kind: TrackKind.video));
      seq.tracks.add(Track(id: 'a', kind: TrackKind.audio));
      seq.tracks[0].clips.add(Clip(
          id: 'c', assetId: 'a1', position: 0, duration: 90,
          effects: [ClipEffect(id: 'e', effectId: 'eq', values: {'gamma': 1.5})]));
      seq.tracks[1].clips.add(Clip(
          id: 'c2', assetId: 'a1', position: 0, duration: 90));
      p.sequences.add(seq);
      final g = GraphBuilder(project: p).build(seq, 0, 90);
      expect(g.filterComplex, contains('eq='));
      expect(g.filterComplex, contains('overlay'));
      expect(g.audioLabel, isNotEmpty);
      expect(g.videoLabel, isNotEmpty);
    });
  });

  group('shortcuts', () {
    test('combo parse + match', () {
      final c = KeyCombo.parse('ctrl+shift+z')!;
      expect(c.ctrl, isTrue);
      expect(c.shift, isTrue);
      expect(c.key, 'z');
      expect(c.matches(KeyCombo.parse('ctrl+shift+z')!), isTrue);
      expect(c.matches(KeyCombo.parse('ctrl+z')!), isFalse);
      final m = ShortcutMap(null);
      expect(m.commandFor(KeyCombo.parse('space')!), Commands.playPause);
      expect(m.commandFor(KeyCombo.parse('ctrl+z')!), Commands.undo);
    });
  });
}
