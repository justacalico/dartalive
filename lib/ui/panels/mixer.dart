import 'package:flutter/material.dart';

import '../../models/model.dart';
import '../../state/editor_state.dart';
import '../../theme.dart';

/// Per-track gain faders + pan. Applied in the render graph.
class MixerPanel extends StatefulWidget {
  final EditorState state;
  const MixerPanel({super.key, required this.state});

  @override
  State<MixerPanel> createState() => _MixerPanelState();
}

class _MixerPanelState extends State<MixerPanel> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final seq = s.sequence;
    if (seq == null) return const SizedBox();
    final tracks = seq.audioTracks;
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(6),
      children: [
        for (final t in tracks) _strip(s, t),
        _masterStrip(s),
      ],
    );
  }

  Widget _strip(EditorState s, Track t) {
    return Container(
      width: 58,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
          color: AppTheme.panelAlt,
          border: Border.all(color: AppTheme.border, width: 0.5)),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        Text(t.name.isEmpty ? 'A' : t.name,
            style: const TextStyle(fontSize: 10, color: AppTheme.textDim)),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: t.gain.clamp(0, 2),
              min: 0,
              max: 2,
              onChangeStart: t.locked ? null : (_) => s.pushUndo('Track gain'),
              onChanged: t.locked
                  ? null
                  : (v) {
                      setState(() => t.gain = v);
                      s.dirty = true;
                      s.frameServer.invalidate();
                    },
            ),
          ),
        ),
        Text('${(t.gain * 100).round()}%',
            style: const TextStyle(fontSize: 9.5, color: AppTheme.text)),
        const SizedBox(height: 4),
        SizedBox(
          height: 18,
          width: 44,
          child: Slider(
            value: t.pan.clamp(-1, 1),
            min: -1,
            max: 1,
            onChangeStart: t.locked ? null : (_) => s.pushUndo('Track pan'),
            onChanged: t.locked ? null : (v) => setState(() => t.pan = v),
          ),
        ),
        Text('pan ${t.pan.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 9, color: AppTheme.textDim)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => t.muted = !t.muted),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: t.muted ? AppTheme.danger : AppTheme.panel,
                borderRadius: BorderRadius.circular(2)),
            child: Text('M',
                style: TextStyle(
                    fontSize: 9,
                    color: t.muted ? Colors.white : AppTheme.textDim)),
          ),
        ),
      ]),
    );
  }

  Widget _masterStrip(EditorState s) {
    return Container(
      width: 58,
      decoration: BoxDecoration(
          color: AppTheme.panel,
          border: Border.all(color: AppTheme.border, width: 0.5)),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: const Column(children: [
        Text('Master',
            style: TextStyle(fontSize: 10, color: AppTheme.textDim)),
        Expanded(
            child: Center(
                child: Icon(Icons.graphic_eq,
                    color: AppTheme.textDim, size: 20))),
        Text('sum',
            style: TextStyle(fontSize: 9, color: AppTheme.textDim)),
      ]),
    );
  }
}
