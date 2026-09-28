import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'landing.dart';
import 'state/editor_state.dart';
import 'state/settings.dart';
import 'theme.dart';
import 'ui/window_frame.dart';
import 'io/kdenlive_import.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
    try {
      await windowManager.ensureInitialized();
      const opts = WindowOptions(
          size: Size(1600, 920),
          minimumSize: Size(960, 540),
          title: 'DartAlive',
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
          backgroundColor: AppTheme.bg);
      windowManager.waitUntilReadyToShow(opts, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {}
  }
  final settings = Settings.load();
  final state = EditorState(settings);
  state.welcomeVisible = settings.showWelcome;
  runApp(kIsWeb ? LandingApp() : EditorAppRoot(state: state));
  // --open=/path/project.dal
  if (!kIsWeb) {
    for (final a in const String.fromEnvironment('OPEN', defaultValue: '')
        .split(',')
        .where((e) => e.isNotEmpty)) {
      state.welcomeVisible = false;
      if (a.endsWith('.kdenlive')) {
        KdenliveImport.run(a).then((p) => state.loadImportedProject(p, a));
      } else {
        state.openProject(a);
      }
    }
  }
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
      home: WindowFrame(child: EditorApp(state: state)),
    );
  }
}
