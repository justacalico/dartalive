import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../state/editor_state.dart';
import '../../theme.dart';

/// Histogram + RGB parade computed from the current preview frame.
class ScopesPanel extends StatefulWidget {
  final EditorState state;
  const ScopesPanel({super.key, required this.state});

  @override
  State<ScopesPanel> createState() => _ScopesPanelState();
}

class _ScopesPanelState extends State<ScopesPanel> {
  List<int>? _histR, _histG, _histB, _histL;
  ui.Image? _analyzed;

  @override
  Widget build(BuildContext context) {
    final img = widget.state.frameImage.value;
    if (img != null && img != _analyzed) {
      _analyzed = img;
      _analyze(img);
    }
    return Container(
      color: Colors.black,
      child: CustomPaint(
        painter: _ScopePainter(_histR, _histG, _histB, _histL),
        size: Size.infinite,
      ),
    );
  }

  Future<void> _analyze(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return;
    const bins = 64;
    final r = List<int>.filled(bins, 0);
    final g = List<int>.filled(bins, 0);
    final b = List<int>.filled(bins, 0);
    final l = List<int>.filled(bins, 0);
    final px = data.buffer.asUint32List();
    final step = (px.length / 40000).ceil().clamp(1, 1000);
    for (var i = 0; i < px.length; i += step) {
      final p = px[i];
      final pr = p & 0xff;
      final pg = (p >> 8) & 0xff;
      final pb = (p >> 16) & 0xff;
      r[pr * bins >> 8]++;
      g[pg * bins >> 8]++;
      b[pb * bins >> 8]++;
      l[((pr * 299 + pg * 587 + pb * 114) ~/ 1000) * bins >> 8]++;
    }
    if (mounted) {
      setState(() {
        _histR = r;
        _histG = g;
        _histB = b;
        _histL = l;
      });
    }
  }
}

class _ScopePainter extends CustomPainter {
  final List<int>? r, g, b, l;
  _ScopePainter(this.r, this.g, this.b, this.l);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    if (l == null) {
      _label(canvas, 'no frame', size);
      return;
    }
    final half = Size(size.width / 2 - 8, size.height - 16);
    _hist(canvas, l!, const Offset(4, 8), half, Colors.white, 'LUMA');
    _rgb(canvas, Offset(8 + half.width, 8), half);
  }

  void _label(Canvas c, String t, Size s) {
    final tp = TextPainter(
        text: TextSpan(text: t, style: const TextStyle(color: AppTheme.textDim, fontSize: 10)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, Offset(4, s.height / 2));
  }

  void _hist(Canvas c, List<int> h, Offset o, Size s, Color col, String name) {
    final maxV = h.fold(0, (m, v) => v > m ? v : m);
    if (maxV == 0) return;
    final paint = Paint()..color = col.withValues(alpha: 0.7);
    final bw = s.width / h.length;
    for (var i = 0; i < h.length; i++) {
      final v = h[i] / maxV;
      c.drawRect(
          Rect.fromLTWH(o.dx + i * bw, o.dy + s.height * (1 - v), bw, s.height * v),
          paint);
    }
    final tp = TextPainter(
        text: TextSpan(text: name, style: const TextStyle(fontSize: 8, color: AppTheme.textDim)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, o);
  }

  void _rgb(Canvas c, Offset o, Size s) {
    if (r == null || g == null || b == null) return;
    final thirds = Size(s.width, s.height / 3);
    _hist(c, r!, o, thirds, Colors.redAccent, 'R');
    _hist(c, g!, o.translate(0, thirds.height), thirds, Colors.greenAccent, 'G');
    _hist(c, b!, o.translate(0, thirds.height * 2), thirds, Colors.blueAccent, 'B');
  }

  @override
  bool shouldRepaint(_ScopePainter o) => true;
}
