import 'model.dart';

/// Pure timeline edit operations. All functions mutate the passed sequence
/// and return whether they did anything; callers wrap them in undo steps.

class SeqOps {
  /// Does placing [pos..pos+len) on [track] collide with an existing clip
  /// (optionally ignoring [ignoreId] or a link group)?
  static bool collides(Track track, int pos, int len, {String? ignoreId, String? linkGroup}) {
    for (final c in track.clips) {
      if (ignoreId != null && c.id == ignoreId) continue;
      if (linkGroup != null && c.linkGroup == linkGroup) continue;
      if (pos < c.end && pos + len > c.position) return true;
    }
    return false;
  }

  /// Nearest legal position for a clip of [len] dragged to [wanted].
  /// Slides it out of overlaps left or right, preferring the closer side.
  static int resolvePosition(Track track, int wanted, int len,
      {String? ignoreId, String? linkGroup}) {
    if (wanted < 0) wanted = 0;
    if (!collides(track, wanted, len, ignoreId: ignoreId, linkGroup: linkGroup)) {
      return wanted;
    }
    // try right then left
    for (var dist = 1; dist < 100000; dist++) {
      final r = wanted + dist;
      if (!collides(track, r, len, ignoreId: ignoreId, linkGroup: linkGroup)) {
        return r;
      }
      final l = wanted - dist;
      if (l >= 0 &&
          !collides(track, l, len, ignoreId: ignoreId, linkGroup: linkGroup)) {
        return l;
      }
      if (l < 0 && r > wanted + 4000) break;
    }
    return wanted;
  }

  /// Split every clip crossing [frame] into two clips. Returns new clips.
  static List<Clip> splitAt(Sequence seq, int frame, double fps,
      {String? onlyClipId}) {
    final created = <Clip>[];
    for (final t in seq.tracks) {
      if (t.locked) continue;
      for (final c in List.of(t.clips)) {
        if (onlyClipId != null && c.id != onlyClipId) continue;
        if (frame <= c.position || frame >= c.end) continue;
        final leftLen = frame - c.position;
        final rightLen = c.end - frame;
        final right = c.clone('${c.id}_r$frame');
        right.position = frame;
        right.duration = rightLen;
        right.offsetSec = c.offsetSec + (leftLen / fps) * c.speed;
        right.transition = c.transition;
        c.transition = null;
        c.duration = leftLen;
        t.clips.add(right);
        created.add(right);
      }
    }
    return created;
  }

  /// Remove a clip; when [ripple] also close the gap on all unlocked tracks.
  static bool removeClip(Sequence seq, String clipId, {bool ripple = false}) {
    Clip? found;
    for (final t in seq.tracks) {
      for (final c in t.clips) {
        if (c.id == clipId) found = c;
      }
    }
    if (found == null) return false;
    final gap = found.duration;
    final gapPos = found.position;
    for (final t in seq.tracks) {
      t.clips.removeWhere((c) => c.id == clipId);
      if (ripple && !t.locked) {
        for (final c in t.clips) {
          if (c.position >= gapPos) c.position -= gap;
        }
      }
    }
    return true;
  }

  /// Trim a clip's left edge to [newPos] frames. Returns false if illegal
  /// (would overlap neighbour, run past media start, or shrink below 1 frame).
  static bool trimLeft(Sequence seq, Clip clip, int newPos, double fps,
      {double maxSourceSec = double.infinity, bool ripple = false}) {
    final delta = newPos - clip.position;
    if (delta == 0) return true;
    final newDur = clip.duration - delta;
    if (newDur < 1) return false;
    final newOffset = clip.offsetSec + (delta / fps) * clip.speed;
    if (newOffset < 0) return false;
    // collision check on the exposed region
    final track = _trackOf(seq, clip.id);
    if (track == null) return false;
    if (delta < 0 &&
        collides(track, newPos, -delta,
            ignoreId: clip.id, linkGroup: clip.linkGroup)) {
      return false;
    }
    if (ripple && delta != 0) {
      // ripple trim: pull/push subsequent clips on this track
      for (final c in track.clips) {
        if (c.id != clip.id && c.position >= clip.end) c.position += delta;
      }
    }
    clip.position = newPos;
    clip.duration = newDur;
    clip.offsetSec = newOffset;
    return true;
  }

  /// Trim a clip's right edge to [newEnd].
  static bool trimRight(Sequence seq, Clip clip, int newEnd, double fps,
      {double maxSourceSec = double.infinity, bool ripple = false}) {
    final delta = newEnd - clip.end;
    if (delta == 0) return true;
    final newDur = clip.duration + delta;
    if (newDur < 1) return false;
    if (clip.sourceSpan(fps) + (delta / fps) * clip.speed >
        maxSourceSec - clip.offsetSec + clip.sourceSpan(fps)) {
      // extending past media end: check source availability
      final newSourceOut = clip.offsetSec + (newDur / fps) * clip.speed;
      if (newSourceOut > maxSourceSec + 0.0001) return false;
    }
    final track = _trackOf(seq, clip.id);
    if (track == null) return false;
    if (delta > 0 &&
        collides(track, clip.end, delta,
            ignoreId: clip.id, linkGroup: clip.linkGroup)) {
      return false;
    }
    if (ripple && delta != 0) {
      for (final c in track.clips) {
        if (c.id != clip.id && c.position >= clip.end) c.position += delta;
      }
    }
    clip.duration = newDur;
    return true;
  }

  /// Slip: shift the source window without moving the clip on the timeline.
  static bool slip(Clip clip, int deltaFrames, double fps,
      {double maxSourceSec = double.infinity}) {
    final d = (deltaFrames / fps) * clip.speed;
    final newOffset = clip.offsetSec - d;
    if (newOffset < 0) return false;
    if (newOffset + clip.sourceSpan(fps) > maxSourceSec + 0.0001) return false;
    clip.offsetSec = newOffset;
    return true;
  }

  /// Slide: move the clip between its neighbours keeping position (their
  /// trims compensate). Classic NLE slide.
  static bool slide(Sequence seq, Clip clip, int deltaFrames, double fps,
      {double maxSourceSec = double.infinity}) {
    final track = _trackOf(seq, clip.id);
    if (track == null) return false;
    final sorted = track.sorted;
    final idx = sorted.indexWhere((c) => c.id == clip.id);
    if (idx < 0) return false;
    final prev = idx > 0 ? sorted[idx - 1] : null;
    final next = idx < sorted.length - 1 ? sorted[idx + 1] : null;
    if (prev == null && next == null) return false;
    // validate before mutating so a partial slide can't corrupt the track
    if (prev != null &&
        !_canTrimRight(prev, prev.end + deltaFrames, fps,
            maxSourceSec: maxSourceSec)) {
      return false;
    }
    if (next != null &&
        !_canTrimLeft(next, next.position + deltaFrames, fps)) {
      return false;
    }
    if (prev != null) {
      trimRight(seq, prev, prev.end + deltaFrames, fps,
          maxSourceSec: maxSourceSec);
    }
    if (next != null) {
      trimLeft(seq, next, next.position + deltaFrames, fps,
          maxSourceSec: maxSourceSec);
    }
    clip.position += deltaFrames;
    return true;
  }

  static bool _canTrimLeft(Clip c, int newPos, double fps) {
    if (newPos >= c.end) return false;
    final delta = newPos - c.position;
    return c.offsetSec + delta / fps * c.speed >= -0.0001;
  }

  static bool _canTrimRight(Clip c, int newEnd, double fps,
      {double maxSourceSec = double.infinity}) {
    if (newEnd <= c.position) return false;
    final newDur = newEnd - c.position;
    return c.offsetSec + newDur / fps * c.speed <= maxSourceSec + 0.0001;
  }

  /// Insert [clip] at position, pushing later clips right (insert edit).
  static void rippleInsert(Track track, Clip clip, double fps,
      {Sequence? seq}) {
    // split a clip that straddles the insert point
    for (final c in List.of(track.clips)) {
      if (c.position < clip.position && c.end > clip.position) {
        if (seq != null) {
          splitAt(seq, clip.position, fps);
        }
        break;
      }
    }
    for (final c in track.clips) {
      if (c.position >= clip.position) c.position += clip.duration;
    }
    track.clips.add(clip);
  }

  /// Overwrite: remove anything intersecting [pos..pos+len), drop clip in.
  static List<Clip> overwrite(Track track, Clip clip, String idSuffix) {
    final removed = <Clip>[];
    for (final c in List.of(track.clips)) {
      if (clip.position < c.end && clip.end > c.position) {
        track.clips.remove(c);
        removed.add(c);
      }
    }
    track.clips.add(clip);
    return removed;
  }

  /// Lift region [a..b) on all unlocked tracks (clips split at edges).
  static List<Clip> liftRegion(Sequence seq, int a, int b, double fps,
      {bool ripple = false}) {
    final taken = <Clip>[];
    for (final t in seq.tracks) {
      if (t.locked) continue;
      for (final c in List.of(t.clips)) {
        if (c.position < b && c.end > a) {
          // partial overlap: split at boundaries first via caller; here we
          // just take clips fully inside and trim edges of straddlers.
          if (c.position >= a && c.end <= b) {
            t.clips.remove(c);
            taken.add(c);
          }
        }
      }
      if (ripple) {
        for (final c in t.clips) {
          if (c.position >= b) c.position -= (b - a);
        }
      }
    }
    return taken;
  }

  static Track? _trackOf(Sequence seq, String clipId) {
    for (final t in seq.tracks) {
      if (t.clips.any((c) => c.id == clipId)) return t;
    }
    return null;
  }

  /// Candidate snap points (timeline frames) for a drag: clip edges, playhead,
  /// markers, zero.
  static List<int> snapPoints(Sequence seq, {int? playhead, String? excludeClipId}) {
    final pts = <int>{0};
    if (playhead != null) pts.add(playhead);
    for (final m in seq.markers) {
      pts.add(m.frame);
    }
    for (final t in seq.tracks) {
      for (final c in t.clips) {
        if (c.id == excludeClipId) continue;
        pts.add(c.position);
        pts.add(c.end);
      }
    }
    return pts.toList()..sort();
  }

  static int snap(int frame, List<int> points, int threshold) {
    var best = frame, bestD = threshold + 1;
    for (final p in points) {
      final d = (p - frame).abs();
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }
}
