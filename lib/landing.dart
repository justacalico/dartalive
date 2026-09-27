import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Web build = landing page only. The editor itself is desktop.
/// Design language matches the app: near-black panels, hairline rules,
/// warm amber accent, dense small type.
class LandingApp extends StatelessWidget {
  const LandingApp({super.key});

  static const bg = Color(0xff141417);
  static const panel = Color(0xff1c1c20);
  static const border = Color(0xff2c2c33);
  static const text = Color(0xffd8d8de);
  static const dim = Color(0xff8b8b96);
  static const accent = Color(0xffe8b32c);
  static const video = Color(0xff4a7fb5);
  static const audio = Color(0xff3f8f63);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DartAlive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: bg),
      home: const LandingPage(),
    );
  }
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LandingApp.bg,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 64),
                _wordmark(),
                const SizedBox(height: 8),
                const Text(
                  'A free, open-source video editor.\nTimeline, sequences, color grading, effects.\nNothing between you and the cut.',
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: LandingApp.dim),
                ),
                const SizedBox(height: 40),
                const _TimelineStripe(),
                const SizedBox(height: 40),
                _downloads(),
                const SizedBox(height: 40),
                _facts(),
                const SizedBox(height: 48),
                _footer(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wordmark() {
    return Row(children: [
      Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: LandingApp.accent,
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: const Center(
          child: Icon(Icons.play_arrow, color: Colors.black, size: 20),
        ),
      ),
      const SizedBox(width: 10),
      const Text('DartAlive',
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: LandingApp.text,
              letterSpacing: 0.3)),
    ]);
  }

  Widget _downloads() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('DESKTOP ONLY',
          style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.6,
              color: LandingApp.dim)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _dl(Icons.terminal, 'Linux', 'AppImage · deb · rpm'),
        _dl(Icons.window_outlined, 'Windows', 'x64 · arm64'),
        _dl(Icons.laptop_mac, 'macOS', 'Apple Silicon'),
      ]),
      const SizedBox(height: 10),
      const Text(
          'Runs on FFmpeg. Projects are portable .dal files — media stays '
          'relative to the project, so the whole edit fits on one drive.',
          style: TextStyle(fontSize: 12, color: LandingApp.dim, height: 1.5)),
    ]);
  }

  Widget _dl(IconData icon, String os, String note) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LandingApp.panel,
        border: Border.all(color: LandingApp.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: LandingApp.text),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(os,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: LandingApp.text)),
          Text(note,
              style:
                  const TextStyle(fontSize: 10, color: LandingApp.dim)),
        ]),
      ]),
    );
  }

  Widget _facts() {
    const rows = [
      ('Tracks', 'Unlimited video + audio, lock/mute/hide, transitions'),
      ('Sequences', 'Edit in a tab, drop the whole thing in as a clip'),
      ('Color', 'EQ, levels, curves, balance, LUTs, channel mixer'),
      ('Audio', 'Gain, pan, EQ, compressor, limiter, loudness normalize'),
      ('Panels', 'Dockable, resizable, layouts you can save'),
      ('Export', 'H.264, HEVC, VP9, ProRes, DNxHD, GIF, WAV'),
      ('Keys', 'Every action bindable. J-K-L, razor, ripple, slip, slide'),
      ('Format', '.dal = zip. Relative paths. Survives drive letters'),
    ];
    return Column(children: [
      for (final r in rows)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: const BoxDecoration(
              border: Border(
                  bottom:
                      BorderSide(color: LandingApp.border, width: 0.5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 110,
                child: Text(r.$1,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: LandingApp.text))),
            Expanded(
                child: Text(r.$2,
                    style: const TextStyle(
                        fontSize: 12, color: LandingApp.dim))),
          ]),
        ),
    ]);
  }

  Widget _footer() {
    return Row(children: [
      const Text('DartAlive — AGPL-3.0',
          style: TextStyle(fontSize: 11, color: LandingApp.dim)),
      const Spacer(),
      _link('Source', 'https://gitlab.com/HttpAnimations/dartalive'),
      const SizedBox(width: 14),
      _link('Releases',
          'https://gitlab.com/HttpAnimations/dartalive/-/releases'),
      const SizedBox(width: 14),
      const Text('Built with Flutter + FFmpeg',
          style: TextStyle(fontSize: 11, color: LandingApp.dim)),
    ]);
  }

  Widget _link(String label, String url) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              color: LandingApp.accent,
              decoration: TextDecoration.underline)),
    );
  }
}

/// A decorative timeline strip: abstract clip blocks on tracks. Not a
/// screenshot — a mark of what the app is.
class _TimelineStripe extends StatelessWidget {
  const _TimelineStripe();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
          color: LandingApp.panel,
          border: Border.all(color: LandingApp.border),
          borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.all(10),
      child: CustomPaint(
        painter: _StripePainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  static const _blocks = [
    // (track, start, len, color)
    (0, 0.00, 0.32, LandingApp.video),
    (0, 0.36, 0.22, LandingApp.video),
    (0, 0.62, 0.30, LandingApp.video),
    (1, 0.10, 0.25, Color(0xff7a5fb5)),
    (1, 0.55, 0.30, Color(0xff7a5fb5)),
    (2, 0.02, 0.55, LandingApp.audio),
    (2, 0.60, 0.36, LandingApp.audio),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const trackH = 24.0, gap = 6.0;
    for (final b in _blocks) {
      final y = b.$1 * (trackH + gap);
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(b.$2 * size.width, y, b.$3 * size.width, trackH),
          const Radius.circular(2));
      canvas.drawRRect(
          rect, Paint()..color = b.$4.withValues(alpha: 0.55));
      canvas.drawRRect(rect, Paint()..color = b.$4..style = PaintingStyle.stroke);
    }
    // playhead
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.42, -4, 1.5, size.height + 8),
        Paint()..color = LandingApp.accent);
  }

  @override
  bool shouldRepaint(_StripePainter o) => false;
}
