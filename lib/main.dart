import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'landing.dart';
import 'state/editor_state.dart';
import 'state/settings.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
    try {
      await windowManager.ensureInitialized();
      const opts = WindowOptions(
          minimumSize: Size(960, 540),
          title: 'DartAlive',
          backgroundColor: AppTheme.bg);
      windowManager.waitUntilReadyToShow(opts, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {}
  }
  final settings = Settings.load();
  runApp(kIsWeb
      ? LandingApp()
      : EditorAppRoot(state: EditorState(settings)));
}

class EditorAppRoot extends StatelessWidget {
  final EditorState state;
  const EditorAppRoot({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DartAlive',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: EditorApp(state: state),
    );
  }
}
