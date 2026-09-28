import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Gives an undecorated window resize handles, a hairline border and rounded
/// corners while floating. Pass-through on web/mobile.
class WindowFrame extends StatelessWidget {
  final Widget child;
  const WindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return VirtualWindowFrame(child: child);
  }
}

/// Slim chrome strip shown on screens that have no menu bar (e.g. welcome).
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: Colors.transparent,
      child: const DragToMoveArea(
        child: Row(children: [
          Spacer(),
          WindowButtons(),
        ]),
      ),
    );
  }
}

/// Windows-style minimize/maximize/close cluster for the custom chrome.
class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    const b = Brightness.dark;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      WindowCaptionButton.minimize(
          brightness: b, onPressed: () => windowManager.minimize()),
      _isMaximized
          ? WindowCaptionButton.unmaximize(
              brightness: b, onPressed: () => windowManager.unmaximize())
          : WindowCaptionButton.maximize(
              brightness: b, onPressed: () => windowManager.maximize()),
      WindowCaptionButton.close(
          brightness: b, onPressed: () => windowManager.close()),
    ]);
  }
}
