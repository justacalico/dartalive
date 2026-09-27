import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/model.dart';
import '../../models/sequence_ops.dart';
import '../../state/editor_state.dart';
import '../../theme.dart';

/// Source monitor: preview a bin asset via libmpv, mark in/out, and do
/// insert/overwrite edits to the timeline.
class SourceMonitor extends StatefulWidget {
  final EditorState state;
  final String? assetId;
  const SourceMonitor({super.key, required this.state, this.assetId});

  @override
  State<SourceMonitor> createState() => _SourceMonitorState();
}

class _SourceMonitorState extends State<SourceMonitor> {
  Player? _player;
  VideoController? _controller;
  String? _loaded;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  double? _in, _out; // seconds

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    _player = Player();
    _controller = VideoController(_player!);
    _player!.stream.position.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player!.stream.duration.listen((d) {
      if (mounted) setState(() => _dur = d);
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _maybeLoad() {
    final s = widget.state;
    final id = widget.assetId ?? s.selectedAssetId;
    if (id == null || id == _loaded) return;
    final a = s.project.assetById(id);
    if (a == null || a.relPath == null || !(a.hasVideo || a.hasAudio)) {
      _loaded = id;
      _player?.stop();
      return;
    }
    final path = s.project.resolvedPaths[a.id];
    if (path == null) {
      _loaded = id;
      _player?.stop();
      return;
    }
    _loaded = id;
    _in = null;
    _out = null;
    _player?.open(Media('file://$path'), play: false);
  }

  @override
  Widget build(BuildContext context) {
    _maybeLoad();
    final s = widget.state;
    final a = widget.assetId != null
        ? s.project.assetById(widget.assetId!)
        : (s.selectedAssetId != null
            ? s.project.assetById(s.selectedAssetId!)
            : null);
    return Column(children: [
      Expanded(
        child: Container(
          color: Colors.black,
          child: a == null || a.type == AssetType.audio
              ? Center(
                  child: a == null
                      ? const Text('No clip selected',
                          style: TextStyle(color: AppTheme.textDim))
                      : const Icon(Icons.graphic_eq,
                          size: 48, color: AppTheme.textDim))
              : _controller == null
                  ? const SizedBox()
                  : Video(controller: _controller!),
        ),
      ),
      _transport(s, a),
    ]);
  }

  Widget _transport(EditorState s, MediaAsset? a) {
    final dur = _dur.inMilliseconds / 1000;
    return Container(
      height: 56,
      color: AppTheme.panelAlt,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(children: [
        SizedBox(
          height: 18,
          child: Slider(
            value: _pos.inMilliseconds
                .clamp(0, max(1, _dur.inMilliseconds))
                .toDouble(),
            max: max(1, _dur.inMilliseconds).toDouble(),
            onChanged: (v) =>
                _player?.seek(Duration(milliseconds: v.round())),
          ),
        ),
        Row(children: [
          _btn(Icons.skip_previous,
              () => _player?.seek(Duration.zero)),
          _btn(Icons.play_arrow, () => _player?.play()),
          _btn(Icons.pause, () => _player?.pause()),
          _btn(Icons.skip_next,
              () => _player?.seek(_dur)),
          const SizedBox(width: 8),
          Text(
              '${_tc(_pos.inMilliseconds / 1000)} / ${_tc(dur)}',
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textDim, fontFeatures: [])),
          const Spacer(),
          _tagBtn('[', () => setState(() => _in = _pos.inMilliseconds / 1000),
              'Set in'),
          _tagBtn(']', () => setState(() => _out = _pos.inMilliseconds / 1000),
              'Set out'),
          const SizedBox(width: 8),
          _actionBtn('Insert', () => _editToTimeline(s, a, insert: true)),
          const SizedBox(width: 4),
          _actionBtn('Overwrite', () => _editToTimeline(s, a, insert: false)),
        ]),
      ]),
    );
  }

  String _tc(double sec) {
    final d = Duration(milliseconds: (sec * 1000).round());
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}.${two(d.inMilliseconds % 1000 ~/ 10)}';
  }

  Widget _btn(IconData i, VoidCallback f) => IconButton(
      icon: Icon(i, size: 17),
      onPressed: f,
      visualDensity: VisualDensity.compact);

  Widget _tagBtn(String label, VoidCallback f, String tip) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: f,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _actionBtn(String label, VoidCallback f) => InkWell(
        onTap: f,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(3)),
          child: Text(label,
              style: const TextStyle(fontSize: 11, color: AppTheme.text)),
        ),
      );

  void _editToTimeline(EditorState s, MediaAsset? a, {required bool insert}) {
    if (a == null) return;
    final seq = s.sequence;
    if (seq == null) return;
    final inS = _in ?? 0;
    final outS = _out ?? a.durationSec;
    final durFrames = s.project.framesFromSeconds(outS - inS);
    if (durFrames <= 0) return;
    s.edit(insert ? 'Insert edit' : 'Overwrite edit', () {
      final vtrack = seq.videoTracks.isEmpty ? null : seq.videoTracks.last;
      final atrack = seq.audioTracks.isEmpty ? null : seq.audioTracks.first;
      final group = newId();
      if (a.hasVideo && vtrack != null) {
        final c = Clip(
            id: newId(),
            assetId: a.id,
            position: s.playhead,
            duration: durFrames,
            offsetSec: inS,
            linkGroup: group,
            name: a.name);
        if (insert) {
          SeqOps.rippleInsert(vtrack, c, s.fps);
        } else {
          SeqOps.overwrite(vtrack, c, '');
        }
      }
      if (a.hasAudio && atrack != null) {
        final c = Clip(
            id: newId(),
            assetId: a.id,
            position: s.playhead,
            duration: durFrames,
            offsetSec: inS,
            linkGroup: group,
            name: a.name);
        if (insert) {
          SeqOps.rippleInsert(atrack, c, s.fps);
        } else {
          SeqOps.overwrite(atrack, c, '');
        }
      }
    });
  }
}

int max(int a, int b) => a > b ? a : b;
