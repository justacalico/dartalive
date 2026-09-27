import 'package:flutter/material.dart';

import '../../state/editor_state.dart';
import '../../theme.dart';

/// Program monitor: shows the composited frame stream from the frame
/// server, with transport controls, in/out marks and preview quality.
class ProgramMonitor extends StatefulWidget {
  final EditorState state;
  const ProgramMonitor({super.key, required this.state});

  @override
  State<ProgramMonitor> createState() => _ProgramMonitorState();
}

class _ProgramMonitorState extends State<ProgramMonitor> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Column(children: [
      Expanded(
        child: Container(
          color: Colors.black,
          child: ValueListenableBuilder(
            valueListenable: s.frameImage,
            builder: (_, img, child) {
              return Stack(fit: StackFit.expand, children: [
                if (img != null)
                  RawImage(
                      image: img,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium),
                if (img == null)
                  const Center(
                      child: Icon(Icons.movie_outlined,
                          color: Color(0xff333340), size: 56)),
                Positioned(
                  left: 8, top: 6,
                  child: _hud(s.displayTime),
                ),
                if (s.sequence != null)
                  Positioned(
                    right: 8, top: 6,
                    child: _hud(s.sequence!.name),
                  ),
                if (s.offlineAssets.isNotEmpty)
                  const Positioned(
                    left: 8, bottom: 6,
                    child: Text('MEDIA OFFLINE',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
              ]);
            },
          ),
        ),
      ),
      _transport(),
    ]);
  }

  Widget _hud(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: Colors.black54,
        child: Text(t,
            style: const TextStyle(
                fontSize: 11,
                color: AppTheme.text,
                fontFamily: 'monospace')),
      );

  Widget _transport() {
    final s = widget.state;
    return Container(
      height: 34,
      color: AppTheme.panelAlt,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        _t(Icons.fast_rewind, () => s.play(rate: s.playRate > 0 ? -1 : s.playRate - 1), 'Play back (J)'),
        _t(s.playing ? Icons.pause : Icons.play_arrow, () => s.togglePlay(), 'Play/Pause (Space)'),
        _t(Icons.fast_forward, () => s.play(rate: s.playRate < 0 ? 1 : s.playRate + 1), 'Play forward (L)'),
        _t(Icons.stop, () => s.stopPlayback(), 'Stop (K)'),
        const SizedBox(width: 6),
        _t(Icons.chevron_left, () => s.seek(s.playhead - 1), 'Prev frame'),
        _t(Icons.chevron_right, () => s.seek(s.playhead + 1), 'Next frame'),
        _t(Icons.first_page, () => s.seek(0), 'Start'),
        _t(Icons.last_page, () => s.seek(s.seqDuration), 'End'),
        const VerticalDivider(width: 14, color: AppTheme.border),
        _t(Icons.first_page_outlined, () {
          s.inPoint = s.playhead;
          s.refresh();
        }, 'Set in (I)'),
        _t(Icons.last_page_outlined, () {
          s.outPoint = s.playhead;
          s.refresh();
        }, 'Set out (O)'),
        const Spacer(),
        _previewScaleMenu(s),
      ]),
    );
  }

  Widget _t(IconData i, VoidCallback f, String tip) => Tooltip(
        message: tip,
        child: IconButton(
            icon: Icon(i, size: 16),
            onPressed: f,
            visualDensity: VisualDensity.compact),
      );

  Widget _previewScaleMenu(EditorState s) {
    const opts = [0.25, 0.5, 0.75, 1.0];
    final cur = s.frameServer.scale;
    return PopupMenuButton<double>(
      tooltip: 'Preview resolution',
      onSelected: (v) {
        s.settings.previewScale = v;
        s.frameServer.scale = v;
        s.frameServer.invalidate(hard: true);
        s.settings.save();
      },
      itemBuilder: (_) => [
        for (final o in opts)
          PopupMenuItem(
              value: o,
              height: 26,
              child: Text('${(o * 100).round()}%',
                  style: const TextStyle(fontSize: 11))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('${(cur * 100).round()}%',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textDim)),
      ),
    );
  }
}
