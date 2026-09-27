import 'dart:math';
import 'dart:ui' as ui show Clip;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/effects.dart';
import '../../models/model.dart';
import '../../models/sequence_ops.dart';
import '../../state/editor_state.dart';
import '../../theme.dart';

/// The multi-track timeline editor: ruler, markers, in/out zone, draggable
/// and trimmable clips with thumbnails and waveforms, transitions, snapping,
/// tools (select/razor/ripple/slip/slide) and bin drop targets.
class TimelinePanel extends StatefulWidget {
  final EditorState state;
  const TimelinePanel({super.key, required this.state});

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  final _hCtrl = ScrollController();
  final _vCtrl = ScrollController();
  final _rulerCtrl = ScrollController();
  bool _syncing = false;
  double _trackH = 52;

  double get ppf => widget.state.timelineZoom > 0
      ? widget.state.timelineZoom
      : _fitPpf();
  EditorState get s => widget.state;

  double _fitPpf() {
    final seq = s.sequence;
    if (seq == null || seq.duration == 0) return 6;
    final w = context.size?.width ?? 800;
    return max(0.5, (w - 160) / seq.duration);
  }

  @override
  void initState() {
    super.initState();
    _hCtrl.addListener(() {
      if (_syncing) return;
      _syncing = true;
      if (_rulerCtrl.hasClients &&
          _rulerCtrl.offset != _hCtrl.offset) {
        _rulerCtrl.jumpTo(_hCtrl.offset);
      }
      _syncing = false;
    });
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    _rulerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seq = s.sequence;
    if (seq == null) {
      return const Center(
          child: Text('No sequence', style: TextStyle(color: AppTheme.textDim)));
    }
    final totalW = max(400.0, (seq.duration + 120) * ppf);
    return Column(children: [
      _seqTabs(seq),
      _toolbar(seq),
      Expanded(
        child: Row(children: [
          SizedBox(width: 132, child: _headers(seq)),
          Expanded(
            child: Column(children: [
              SizedBox(
                height: 26,
                child: SingleChildScrollView(
                  controller: _rulerCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                      width: totalW, child: _ruler(seq, totalW)),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _vCtrl,
                  child: SingleChildScrollView(
                    controller: _hCtrl,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: totalW,
                      child: _lanes(seq, totalW),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }

  // ------------------------------------------------------------------
  Widget _seqTabs(Sequence cur) {
    return Container(
      height: 26,
      color: AppTheme.header,
      child: Row(children: [
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final sq in s.project.sequences)
                _seqTab(sq, sq.id == cur.id),
            ],
          ),
        ),
        IconButton(
            icon: const Icon(Icons.add, size: 14),
            visualDensity: VisualDensity.compact,
            onPressed: () => s.newSequence()),
      ]),
    );
  }

  Widget _seqTab(Sequence sq, bool active) {
    return GestureDetector(
      onTap: () => s.openSequence(sq.id),
      onSecondaryTapUp: (d) => showMenu(
          context: context,
          position:
              RelativeRect.fromLTRB(d.globalPosition.dx, d.globalPosition.dy, 0, 0),
          items: [
            const PopupMenuItem(value: 'ren', height: 28, child: Text('Rename')),
            if (s.project.sequences.length > 1)
              const PopupMenuItem(value: 'del', height: 28, child: Text('Delete')),
          ]).then((v) {
        if (v == 'ren') {
          _renameSeq(sq);
        } else if (v == 'del') {
          s.edit('Delete sequence', () {
            s.project.sequences.removeWhere((x) => x.id == sq.id);
            s.project.assets.removeWhere((x) => x.sequenceId == sq.id);
            if (s.activeSequenceId == sq.id) {
              s.openSequence(s.project.sequences.first.id);
            }
          });
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppTheme.panel : Colors.transparent,
          border: Border(
              top: BorderSide(
                  color: active ? AppTheme.accent : Colors.transparent,
                  width: 2)),
        ),
        child: Center(
          child: Row(children: [
            if (sq.id != s.project.mainSequenceId)
              const Icon(Icons.subscriptions,
                  size: 10, color: AppTheme.textDim),
            if (sq.id != s.project.mainSequenceId) const SizedBox(width: 4),
            Text(sq.name,
                style: TextStyle(
                    fontSize: 11,
                    color: active ? AppTheme.text : AppTheme.textDim)),
          ]),
        ),
      ),
    );
  }

  void _renameSeq(Sequence sq) async {
    // deferred import of dialog to keep this file self-contained
    final c = TextEditingController(text: sq.name);
    final n = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Rename sequence'),
              content: TextField(controller: c, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, c.text),
                    child: const Text('OK')),
              ],
            ));
    if (n != null && n.isNotEmpty) {
      s.edit('Rename sequence', () {
        sq.name = n;
        for (final a in s.project.assets) {
          if (a.sequenceId == sq.id) a.name = n;
        }
      });
    }
  }

  // ------------------------------------------------------------------
  Widget _toolbar(Sequence seq) {
    return Container(
      height: 28,
      color: AppTheme.panelAlt,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        _toolBtn('select', Icons.near_me_outlined, 'Selection (V)'),
        _toolBtn('razor', Icons.content_cut, 'Razor (C)'),
        _toolBtn('ripple', Icons.cut, 'Ripple trim (R)'),
        _toolBtn('slip', Icons.swap_horiz, 'Slip (Y)'),
        _toolBtn('slide', Icons.open_with, 'Slide (U)'),
        const VerticalDivider(width: 10, color: AppTheme.border),
        IconButton(
            icon: Icon(Icons.add_link, size: 15),
            tooltip: 'Add track',
            visualDensity: VisualDensity.compact,
            onPressed: () => _addTrack(seq)),
        IconButton(
            icon: const Icon(Icons.zoom_out, size: 15),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              s.timelineZoom = (s.timelineZoom / 1.3).clamp(0.5, 400);
              s.refresh();
            }),
        Expanded(
          child: Slider(
            value: s.timelineZoom <= 0 ? 10 : s.timelineZoom.clamp(0.5, 400),
            min: 0.5,
            max: 400,
            onChanged: (v) {
              s.timelineZoom = v;
              s.refresh();
            },
          ),
        ),
        IconButton(
            icon: const Icon(Icons.zoom_in, size: 15),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              s.timelineZoom = (s.timelineZoom * 1.3).clamp(0.5, 400);
              s.refresh();
            }),
        TextButton(
            onPressed: () {
              s.timelineZoom = -1;
              s.refresh();
            },
            child: const Text('Fit', style: TextStyle(fontSize: 11))),
        const VerticalDivider(width: 10, color: AppTheme.border),
        PopupMenuButton<double>(
          tooltip: 'Track height',
          onSelected: (v) => setState(() => _trackH = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 36, height: 26, child: Text('Small', style: TextStyle(fontSize: 11))),
            PopupMenuItem(value: 52, height: 26, child: Text('Medium', style: TextStyle(fontSize: 11))),
            PopupMenuItem(value: 72, height: 26, child: Text('Large', style: TextStyle(fontSize: 11))),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.height, size: 15, color: AppTheme.textDim),
          ),
        ),
        IconButton(
            icon: Icon(Icons.grid_on,
                size: 15,
                color:
                    s.settings.snapping ? AppTheme.accent : AppTheme.textDim),
            tooltip: 'Snapping',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              s.settings.snapping = !s.settings.snapping;
              s.refresh();
            }),
      ]),
    );
  }

  Widget _toolBtn(String tool, IconData icon, String tip) {
    final on = s.tool == tool;
    return Tooltip(
      message: tip,
      child: IconButton(
        icon: Icon(icon, size: 15,
            color: on ? AppTheme.accent : AppTheme.textDim),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          s.tool = tool;
          s.refresh();
        },
      ),
    );
  }

  void _addTrack(Sequence seq) {
    showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 60, 0, 0),
      items: const [
        PopupMenuItem(value: 'v', height: 30, child: Text('Video track')),
        PopupMenuItem(value: 'a', height: 30, child: Text('Audio track')),
      ],
    ).then((v) {
      if (v == null) return;
      s.edit('Add track', () {
        if (v == 'v') {
          final n = seq.videoTracks.length + 1;
          seq.tracks.insert(
              seq.videoTracks.length,
              Track(
                  id: newId(),
                  kind: TrackKind.video,
                  name: 'V$n'));
        } else {
          final n = seq.audioTracks.length + 1;
          seq.tracks.add(Track(
              id: newId(), kind: TrackKind.audio, name: 'A$n'));
        }
      });
    });
  }

  // ------------------------------------------------------------------
  Widget _headers(Sequence seq) {
    return ListView(
      controller: _vCtrl,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final t in seq.tracks) _trackHeader(seq, t),
      ],
    );
  }

  Widget _trackHeader(Sequence seq, Track t) {
    final isV = t.kind == TrackKind.video;
    return Container(
      height: _trackH,
      decoration: const BoxDecoration(
          color: AppTheme.panelAlt,
          border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5))),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(isV ? Icons.videocam_outlined : Icons.graphic_eq,
                size: 12, color: AppTheme.textDim),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onDoubleTap: () async {
                  final c = TextEditingController(text: t.name);
                  final n = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                            content: TextField(controller: c, autofocus: true),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, c.text),
                                  child: const Text('OK')),
                            ],
                          ));
                  if (n != null) {
                    s.edit('Rename track', () => t.name = n);
                  }
                },
                child: Text(t.name.isEmpty ? t.id : t.name,
                    style:
                        const TextStyle(fontSize: 11, color: AppTheme.text)),
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  t.muted = !t.muted;
                  s.frameServer.invalidate();
                });
              },
              child: Icon(isV ? Icons.visibility_outlined : Icons.volume_up,
                  size: 12,
                  color: t.muted ? AppTheme.danger : AppTheme.textDim),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                setState(() {
                  if (isV) {
                    t.hidden = !t.hidden;
                  } else {
                    t.muted = !t.muted;
                  }
                  s.frameServer.invalidate();
                });
              },
              child: Icon(isV ? Icons.videocam_off_outlined : Icons.volume_off,
                  size: 12,
                  color:
                      (isV ? t.hidden : t.muted) ? AppTheme.danger : AppTheme.textDim),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => t.locked = !t.locked),
              child: Icon(Icons.lock_outline,
                  size: 12,
                  color: t.locked ? AppTheme.accent : AppTheme.textDim),
            ),
          ]),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  Widget _ruler(Sequence seq, double w) {
    return GestureDetector(
      onTapDown: (d) => s.seek((d.localPosition.dx / ppf).round()),
      onHorizontalDragUpdate: (d) =>
          s.seek((d.localPosition.dx / ppf).round()),
      child: CustomPaint(
        painter: _RulerPainter(
            fps: s.fps,
            ppf: ppf,
            playhead: s.playhead,
            inPoint: s.inPoint,
            outPoint: s.outPoint,
            markers: seq.markers),
        size: Size(w, 26),
      ),
    );
  }

  // ------------------------------------------------------------------
  Widget _lanes(Sequence seq, double w) {
    final tracks = seq.tracks;
    final totalH = tracks.length * _trackH;
    return DragTarget<String>(
      onAcceptWithDetails: (d) => _dropAsset(seq, d),
      builder: (context, cand, rej) {
        return SizedBox(
          width: w,
          height: totalH,
          child: Stack(children: [
            // track backgrounds + grid
            CustomPaint(
              size: Size(w, totalH),
              painter: _LanesPainter(
                  fps: s.fps,
                  ppf: ppf,
                  trackCount: tracks.length,
                  trackH: _trackH,
                  inPoint: s.inPoint,
                  outPoint: s.outPoint),
            ),
            // clips
            for (var ti = 0; ti < tracks.length; ti++)
              for (final c in tracks[ti].clips) _clip(seq, tracks[ti], c, ti),
            // playhead
            Positioned(
              left: s.playhead * ppf,
              top: 0,
              bottom: 0,
              child: Container(width: 1, color: AppTheme.accent),
            ),
          ]),
        );
      },
    );
  }

  void _dropAsset(Sequence seq, DragTargetDetails<String> d) {
    if (!d.data.startsWith('asset:')) return;
    final assetId = d.data.substring(6);
    final a = s.project.assetById(assetId);
    if (a == null) return;
    // figure out which track the drop lands on
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    // compute from drag offset inside the lanes stack: the DragTarget covers
    // lanes only
    final local = box.globalToLocal(d.offset);
    final ti = (local.dy / _trackH).floor().clamp(0, seq.tracks.length - 1);
    final frame = (local.dx / ppf).round().clamp(0, 1 << 30);
    _insertAsset(seq, a, seq.tracks[ti], frame);
  }

  void _insertAsset(Sequence seq, MediaAsset a, Track track, int frame) {
    final durFrames = a.type == AssetType.sequence
        ? (s.project.sequenceById(a.sequenceId ?? '')?.duration ??
            s.project.framesFromSeconds(5))
        : (a.type == AssetType.image ||
                a.type == AssetType.color ||
                a.type == AssetType.title)
            ? s.project.framesFromSeconds(a.durationSec > 0 ? a.durationSec : 5)
            : s.project.framesFromSeconds(a.durationSec);
    if (durFrames <= 0) return;
    s.edit('Insert clip', () {
      final group = newId();
      final wantVideo = track.kind == TrackKind.video;
      if (wantVideo && a.hasVideo) {
        final pos = SeqOps.resolvePosition(track, frame, durFrames);
        track.clips.add(Clip(
            id: newId(),
            assetId: a.id,
            position: pos,
            duration: durFrames,
            name: a.name,
            linkGroup: a.hasAudio ? group : null));
        // linked audio onto first audio track
        if (a.hasAudio && seq.audioTracks.isNotEmpty) {
          final at = seq.audioTracks.first;
          final apos = SeqOps.resolvePosition(at, pos, durFrames);
          at.clips.add(Clip(
              id: newId(),
              assetId: a.id,
              position: apos,
              duration: durFrames,
              name: a.name,
              linkGroup: group));
        }
      } else if (!wantVideo && (a.hasAudio || a.type == AssetType.audio)) {
        final pos = SeqOps.resolvePosition(track, frame, durFrames);
        track.clips.add(Clip(
            id: newId(),
            assetId: a.id,
            position: pos,
            duration: durFrames,
            name: a.name));
      } else if (wantVideo && a.type == AssetType.sequence) {
        final pos = SeqOps.resolvePosition(track, frame, durFrames);
        track.clips.add(Clip(
            id: newId(),
            assetId: a.id,
            position: pos,
            duration: durFrames,
            name: a.name));
      }
    });
  }

  // ------------------------------------------------------------------
  Widget _clip(Sequence seq, Track track, Clip c, int trackIndex) {
    final left = c.position * ppf;
    final w = max(2.0, c.duration * ppf);
    final top = trackIndex * _trackH;
    final sel = s.selectedClips.contains(c.id);
    final isV = track.kind == TrackKind.video;
    final a = s.project.assetById(c.assetId);
    final offline = a != null && s.offlineAssets.contains(a.id);

    return Positioned(
      left: left,
      top: top + 1,
      width: w,
      height: _trackH - 2,
      child: DragTarget<String>(
        onAcceptWithDetails: (d) {
          if (d.data.startsWith('effect:')) {
            final fid = d.data.substring(7);
            final def = Effects.byId(fid);
            if (def == null) return;
            s.edit('Add effect', () {
              c.effects.add(ClipEffect(
                  id: newId(),
                  effectId: fid,
                  values: def.defaults()));
            });
          }
        },
        builder: (_, cand, child) => GestureDetector(
        onDoubleTap: () {
          if (a != null &&
              a.type == AssetType.sequence &&
              a.sequenceId != null) {
            s.openSequence(a.sequenceId!);
          }
        },
        child: _ClipWidget(
        clip: c,
        track: track,
        seq: seq,
        state: s,
        ppf: ppf,
        width: w,
        asset: a,
        selected: sel,
        offline: offline,
        isVideo: isV,
        isEffectHover: cand.isNotEmpty,
      ))),
    );
  }

}

// ----------------------------------------------------------------------

class _ClipWidget extends StatefulWidget {
  final Clip clip;
  final Track track;
  final Sequence seq;
  final EditorState state;
  final double ppf;
  final double width;
  final MediaAsset? asset;
  final bool selected;
  final bool offline;
  final bool isVideo;
  final bool isEffectHover;

  const _ClipWidget({
    required this.clip,
    required this.track,
    required this.seq,
    required this.state,
    required this.ppf,
    required this.width,
    required this.asset,
    required this.selected,
    required this.offline,
    required this.isVideo,
    this.isEffectHover = false,
  });

  @override
  State<_ClipWidget> createState() => _ClipWidgetState();
}

class _ClipWidgetState extends State<_ClipWidget> {
  _DragMode? _mode;
  double _dragDy = 0;

  EditorState get s => widget.state;
  Clip get c => widget.clip;

  @override
  Widget build(BuildContext context) {
    final color = widget.offline
        ? AppTheme.danger
        : widget.isVideo
            ? AppTheme.videoClip
            : AppTheme.audioClip;
    return GestureDetector(
      onTapDown: (d) => _onTap(d),
      onSecondaryTapUp: (d) => _menu(d.globalPosition),
      onPanStart: _panStart,
      onPanUpdate: _panUpdate,
      onPanEnd: (_) {
        if (_mode != null) s.endGesture();
        _mode = null;
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: c.enabled ? 0.55 : 0.25),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
              color: widget.isEffectHover
                  ? AppTheme.accent
                  : widget.selected
                      ? AppTheme.accent
                      : color,
              width: widget.isEffectHover ? 2 : 1),
        ),
        clipBehavior: ui.Clip.hardEdge,
        child: Stack(children: [
          _content(),
          if (c.transition != null)
            Positioned(
                left: 0, top: 0, bottom: 0,
                width: min<double>(widget.width, c.transition!.duration * widget.ppf).toDouble(),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0.35),
                      Colors.transparent,
                    ]),
                  ),
                  child: const Align(
                      alignment: Alignment.topLeft,
                      child: Icon(Icons.arrow_right,
                          size: 10, color: Colors.white70)),
                )),
          // trim handles
          Positioned(left: 0, top: 0, bottom: 0, width: 7, child: _edge(true)),
          Positioned(right: 0, top: 0, bottom: 0, width: 7, child: _edge(false)),
        ]),
      ),
    );
  }

  Widget _edge(bool left) => MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            _mode = left ? _DragMode.trimL : _DragMode.trimR;
            s.beginGesture('Trim clip');
          },
          onHorizontalDragUpdate: (d) {
            final df = (d.delta.dx / widget.ppf).round();
            if (df == 0) return;
            if (_mode == _DragMode.trimL) {
              SeqOps.trimLeft(widget.seq, c, c.position + df, s.fps,
                  maxSourceSec: widget.asset?.durationSec ?? double.infinity,
                  ripple: s.tool == 'ripple');
            } else {
              SeqOps.trimRight(widget.seq, c, c.end + df, s.fps,
                  maxSourceSec: widget.asset?.durationSec ?? double.infinity,
                  ripple: s.tool == 'ripple');
            }
            s.duringGesture();
          },
          onHorizontalDragEnd: (_) {
            s.endGesture();
            _mode = null;
          },
          child: Container(
            color: Colors.white.withValues(alpha: 0.0),
          ),
        ),
      );

  Widget _content() {
    final a = widget.asset;
    return Stack(children: [
      // filmstrip / waveform
      Positioned.fill(
        child: widget.isVideo
            ? _filmstrip(a)
            : _waveform(a),
      ),
      Positioned(
        left: 4,
        top: 2,
        child: Text(
          c.name ?? a?.name ?? '',
          style: const TextStyle(
              fontSize: 10, color: Colors.white, shadows: [
            Shadow(color: Colors.black, blurRadius: 2)
          ]),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (c.speed != 1.0)
        Positioned(
          right: 4,
          top: 2,
          child: Text('${(c.speed * 100).round()}%',
              style: const TextStyle(
                  fontSize: 9,
                  color: AppTheme.accent,
                  shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
        ),
      if (widget.asset?.type == AssetType.sequence)
        const Positioned(
          right: 4,
          bottom: 2,
          child: Icon(Icons.movie_filter, size: 10, color: Colors.white70),
        ),
    ]);
  }

  Widget _filmstrip(MediaAsset? a) {
    if (a == null || !a.hasVideo) return const SizedBox();
    final count = max(1, (widget.width / 60).floor()).clamp(1, 12);
    final thumbs = <Widget>[];
    for (var i = 0; i < count; i++) {
      var t = s.stripThumb(a.id, i);
      if (t == null) {
        s.requestStripThumb(a, i);
        t = s.thumb(a.id);
      }
      thumbs.add(Expanded(
        child: t != null && t.isNotEmpty
            ? Image.memory(t, fit: BoxFit.cover, gaplessPlayback: true)
            : Container(color: Colors.black26),
      ));
    }
    return Row(children: thumbs);
  }

  Widget _waveform(MediaAsset? a) {
    if (a == null) return const SizedBox();
    final w = s.wave(a.id);
    return CustomPaint(
      painter: _WavePainter(w, widget.width),
      size: Size(widget.width, widget.width > 0 ? 30 : 0),
    );
  }

  void _onTap(TapDownDetails d) {
    final x = d.localPosition.dx;
    if (s.tool == 'razor') {
      final frame = c.position + (x / widget.ppf).round();
      s.edit('Razor cut', () {
        SeqOps.splitAt(widget.seq, frame, s.fps, onlyClipId: c.id);
      });
      return;
    }
    s.selectClip(c.id,
        add: HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isShiftPressed);
    // select linked partners
    if (c.linkGroup != null) {
      for (final t in widget.seq.tracks) {
        for (final o in t.clips) {
          if (o.linkGroup == c.linkGroup) s.selectedClips.add(o.id);
        }
      }
    }
  }

  void _panStart(DragStartDetails d) {
    if (widget.track.locked) return;
    _mode = switch (s.tool) {
      'slip' => _DragMode.slip,
      'slide' => _DragMode.slide,
      _ => _DragMode.move,
    };
    _dragDy = 0;
    if (_mode == _DragMode.move) s.beginGesture('Move clip');
    if (_mode == _DragMode.slip) s.beginGesture('Slip clip');
    if (_mode == _DragMode.slide) s.beginGesture('Slide clip');
  }

  void _panUpdate(DragUpdateDetails d) {
    _dragDy += d.delta.dy;
    final df = (d.delta.dx / widget.ppf).round();
    if (_mode == _DragMode.move) _moveTracks();
    if (df == 0 || _mode == null) return;
    switch (_mode!) {
      case _DragMode.move:
        var want = c.position + df;
        if (s.settings.snapping) {
          final pts = SeqOps.snapPoints(widget.seq,
              playhead: s.playhead, excludeClipId: c.id);
          final snapped = SeqOps.snap(
              want, pts, (s.settings.snapThresholdPx / widget.ppf).round());
          final snappedEnd = SeqOps.snap(want + c.duration, pts,
              (s.settings.snapThresholdPx / widget.ppf).round());
          if (snapped != want) {
            want = snapped;
          } else if (snappedEnd != want + c.duration) {
            want = snappedEnd - c.duration;
          }
        }
        final newPos = SeqOps.resolvePosition(widget.track, want, c.duration,
            ignoreId: c.id, linkGroup: c.linkGroup);
        final delta = newPos - c.position;
        if (delta != 0) {
          c.position = newPos;
          _moveLinked(delta);
          s.duringGesture();
        }
        break;
      case _DragMode.slip:
        if (SeqOps.slip(c, df, s.fps,
            maxSourceSec:
                widget.asset?.durationSec ?? double.infinity)) {
          s.duringGesture();
        }
        break;
      case _DragMode.slide:
        SeqOps.slide(widget.seq, c, df, s.fps,
            maxSourceSec:
                widget.asset?.durationSec ?? double.infinity);
        s.duringGesture();
        break;
      case _DragMode.trimL:
      case _DragMode.trimR:
        break;
    }
  }

  /// Drag vertically across tracks: move the clip (and linked partners)
  /// to the track under the pointer if the kind matches.
  void _moveTracks() {
    const th = 52.0; // matches _trackH in parent
    final tracks = widget.seq.tracks;
    final curIdx = tracks.indexOf(widget.track);
    final deltaTracks = (_dragDy / th).round();
    if (deltaTracks == 0) return;
    final targetIdx = (curIdx + deltaTracks).clamp(0, tracks.length - 1);
    final target = tracks[targetIdx];
    if (target.id == widget.track.id || target.locked) return;
    if (target.kind != widget.track.kind) return;
    if (SeqOps.collides(target, c.position, c.duration, ignoreId: c.id)) {
      return;
    }
    widget.track.clips.remove(c);
    target.clips.add(c);
    _dragDy -= deltaTracks * th;
    s.duringGesture();
  }

  void _moveLinked(int delta) {
    if (c.linkGroup == null) return;
    for (final t in widget.seq.tracks) {
      for (final o in t.clips) {
        if (o.id != c.id && o.linkGroup == c.linkGroup) {
          o.position += delta;
        }
      }
    }
  }

  void _menu(Offset pos) {
    final s0 = s;
    final a = widget.asset;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'cut', height: 28, child: Text('Cut at playhead')),
        const PopupMenuItem(value: 'trans', height: 28, child: Text('Toggle transition')),
        const PopupMenuItem(value: 'speed', height: 28, child: Text('Speed…')),
        const PopupMenuItem(value: 'unlink', height: 28, child: Text('Unlink')),
        const PopupMenuItem(value: 'dup', height: 28, child: Text('Duplicate')),
        const PopupMenuItem(value: 'rename', height: 28, child: Text('Rename…')),
        const PopupMenuItem(value: 'enable', height: 28, child: Text('Enable/disable')),
        const PopupMenuItem(value: 'del', height: 28, child: Text('Delete')),
        const PopupMenuItem(value: 'rdel', height: 28, child: Text('Ripple delete')),
        if (a?.type == AssetType.sequence)
          const PopupMenuItem(value: 'openseq', height: 28, child: Text('Open sequence')),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'cut':
          s0.edit('Cut', () =>
              SeqOps.splitAt(widget.seq, s0.playhead, s0.fps, onlyClipId: c.id));
          break;
        case 'trans':
          s0.edit('Toggle transition', () {
            c.transition = c.transition == null
                ? ClipTransition(
                    duration: s0.settings.defaultTransitionFrames)
                : null;
          });
          break;
        case 'speed':
          _speedDialog();
          break;
        case 'rename':
          _renameClip();
          break;
        case 'unlink':
          s0.edit('Unlink', () => c.linkGroup = null);
          break;
        case 'dup':
          s0.edit('Duplicate', () {
            final n = c.clone(newId());
            n.position = c.end;
            widget.track.clips.add(n);
          });
          break;
        case 'enable':
          s0.edit('Toggle clip', () => c.enabled = !c.enabled);
          break;
        case 'del':
          s0.edit('Delete clip',
              () => SeqOps.removeClip(widget.seq, c.id));
          break;
        case 'rdel':
          s0.edit('Ripple delete',
              () => SeqOps.removeClip(widget.seq, c.id, ripple: true));
          break;
        case 'openseq':
          if (a?.sequenceId != null) s0.openSequence(a!.sequenceId!);
          break;
      }
    });
  }

  void _renameClip() async {
    final c0 = TextEditingController(text: c.name ?? widget.asset?.name ?? '');
    final n = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Rename clip'),
              content: TextField(controller: c0, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, c0.text),
                    child: const Text('OK')),
              ],
            ));
    if (n != null) s.edit('Rename clip', () => c.name = n);
  }

  void _speedDialog() {
    final ctl = TextEditingController(text: '${(c.speed * 100).round()}');
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Clip speed'),
              content: TextField(
                  controller: ctl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Speed %', suffixText: '%')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      final v = double.tryParse(ctl.text);
                      if (v != null && v > 0) {
                        s.edit('Change speed', () {
                          c.speed = v / 100;
                        });
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('OK')),
              ],
            ));
  }
}

enum _DragMode { move, trimL, trimR, slip, slide }

// ----------------------------------------------------------------------

class _RulerPainter extends CustomPainter {
  final double fps, ppf;
  final int playhead;
  final int? inPoint, outPoint;
  final List<Marker> markers;
  _RulerPainter(
      {required this.fps,
      required this.ppf,
      required this.playhead,
      this.inPoint,
      this.outPoint,
      required this.markers});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = AppTheme.header);
    // in/out zone
    if (inPoint != null && outPoint != null && outPoint! > inPoint!) {
      canvas.drawRect(
          Rect.fromLTRB(inPoint! * ppf, 0, outPoint! * ppf, size.height),
          Paint()..color = AppTheme.accent.withValues(alpha: 0.15));
    }
    final tickPaint = Paint()..color = AppTheme.border;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    // choose tick spacing so labels are ~80px apart
    var stepSec = 1.0;
    while (stepSec * fps * ppf < 80) {
      stepSec *= stepSec < 5 ? 2 : 5;
    }
    final stepFrames = (stepSec * fps).round();
    for (var f = 0; f * ppf < size.width; f += stepFrames) {
      final x = f * ppf;
      canvas.drawLine(
          Offset(x, size.height - 8), Offset(x, size.height), tickPaint);
      final d = Duration(milliseconds: (f / fps * 1000).round());
      String two(int v) => v.toString().padLeft(2, '0');
      textPainter.text = TextSpan(
          text:
              '${two(d.inMinutes)}:${two(d.inSeconds % 60)}',
          style:
              const TextStyle(fontSize: 9, color: AppTheme.textDim));
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 3, 4));
    }
    // markers
    for (final m in markers) {
      final x = m.frame * ppf;
      final p = Paint()..color = Color(m.color);
      canvas.drawPath(
          Path()
            ..moveTo(x, 0)
            ..lineTo(x + 5, 8)
            ..lineTo(x - 5, 8)
            ..close(),
          p);
    }
    // playhead
    canvas.drawRect(
        Rect.fromLTWH(playhead * ppf - 0.5, 0, 1.5, size.height),
        Paint()..color = AppTheme.accent);
    canvas.drawPath(
        Path()
          ..moveTo(playhead * ppf - 5, 0)
          ..lineTo(playhead * ppf + 5, 0)
          ..lineTo(playhead * ppf, 7)
          ..close(),
        Paint()..color = AppTheme.accent);
  }

  @override
  bool shouldRepaint(_RulerPainter o) => true;
}

class _LanesPainter extends CustomPainter {
  final double fps, ppf, trackH;
  final int trackCount;
  final int? inPoint, outPoint;
  _LanesPainter(
      {required this.fps,
      required this.ppf,
      required this.trackCount,
      required this.trackH,
      this.inPoint,
      this.outPoint});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppTheme.bg);
    final line = Paint()..color = AppTheme.border.withValues(alpha: 0.5);
    for (var i = 0; i <= trackCount; i++) {
      canvas.drawLine(Offset(0, i * trackH), Offset(size.width, i * trackH), line);
    }
    // light vertical grid every second
    var stepSec = 1.0;
    while (stepSec * fps * ppf < 60) {
      stepSec *= stepSec < 5 ? 2 : 5;
    }
    final stepFrames = (stepSec * fps).round();
    final gp = Paint()..color = AppTheme.border.withValues(alpha: 0.3);
    for (var f = 0; f * ppf < size.width; f += stepFrames) {
      canvas.drawLine(
          Offset(f * ppf, 0), Offset(f * ppf, size.height), gp);
    }
    if (inPoint != null && outPoint != null && outPoint! > inPoint!) {
      canvas.drawRect(
          Rect.fromLTRB(inPoint! * ppf, 0, outPoint! * ppf, size.height),
          Paint()..color = AppTheme.accent.withValues(alpha: 0.06));
    }
  }

  @override
  bool shouldRepaint(_LanesPainter o) => true;
}

class _WavePainter extends CustomPainter {
  final List<double>? peaks;
  final double w;
  _WavePainter(this.peaks, this.w);

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks == null || peaks!.length < 4) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final n = peaks!.length ~/ 2;
    final mid = size.height / 2;
    for (var x = 0.0; x < size.width; x++) {
      final i = (x / size.width * n).floor().clamp(0, n - 1);
      final mn = peaks![i * 2];
      final mx = peaks![i * 2 + 1];
      canvas.drawLine(
          Offset(x, mid - mx * mid), Offset(x, mid - mn * mid), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.peaks != peaks;
}
