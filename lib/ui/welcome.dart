import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state/editor_state.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'window_frame.dart';

/// Startup screen — open recent, open, or create a project.
class WelcomeScreen extends StatelessWidget {
  final EditorState state;
  const WelcomeScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(children: [
            if (isDesktop) const WindowTitleBar(),
            _banner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
              child: Row(children: [
                Expanded(
                    child: _action(context,
                        icon: Icons.folder_open_outlined,
                        label: 'Open Project…',
                        onTap: () => _open(context))),
                const SizedBox(width: 16),
                Expanded(
                    child: _action(context,
                        icon: Icons.add_box_outlined,
                        label: 'New Project…',
                        onTap: () => s.newProject())),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 8, 28, 6),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Open Recent',
                      style: TextStyle(fontSize: 12, color: AppTheme.textDim))),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _recentList(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 28, 10),
              child: Row(children: [
                SizedBox(
                  height: 20,
                  width: 20,
                  child: Checkbox(
                    value: s.settings.showWelcome,
                    onChanged: (v) {
                      s.settings.showWelcome = v ?? true;
                      s.settings.save();
                      s.refresh();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Show on Startup',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
                const Spacer(),
                TextButton(
                  onPressed: () => s.dismissWelcome(),
                  child: const Text('Continue without a project',
                      style:
                          TextStyle(fontSize: 11, color: AppTheme.textDim)),
                ),
              ]),
            ),
          ]),
    );
  }

  Widget _banner() {
    return Container(
      height: 160,
      width: double.infinity,
      color: AppTheme.header,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(children: [
        Image.asset('assets/icon-1024.png', width: 72, height: 72),
        const SizedBox(width: 14),
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DartAlive',
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text)),
            SizedBox(height: 2),
            Text('Non-linear video editor',
                style: TextStyle(fontSize: 12, color: AppTheme.textDim)),
          ],
        ),
      ]),
    );
  }

  Widget _action(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Material(
      color: AppTheme.panelAlt,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          child: Row(children: [
            Icon(icon, size: 18, color: AppTheme.accent),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(fontSize: 13, color: AppTheme.text)),
          ]),
        ),
      ),
    );
  }

  Widget _recentList(BuildContext context) {
    final recent = state.settings.recentProjects;
    if (recent.isEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Text('No recent projects',
            style: TextStyle(fontSize: 12, color: AppTheme.textDim)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: recent.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppTheme.border),
        itemBuilder: (_, i) {
          final p = recent[i];
          final f = File(p);
          final name = p.split(Platform.pathSeparator).last;
          final exists = f.existsSync();
          String sub = p;
          if (exists) {
            final m = f.statSync().modified;
            sub =
              '${m.day.toString().padLeft(2, '0')}/${m.month.toString().padLeft(2, '0')}/${m.year % 100} '
              '${m.hour.toString().padLeft(2, '0')}:${m.minute.toString().padLeft(2, '0')}   $p';
          }
          return ListTile(
            dense: true,
            leading: Icon(
                exists ? Icons.movie_outlined : Icons.videocam_off_outlined,
                size: 16,
                color: exists ? AppTheme.accent : AppTheme.textDim),
            title: Text(name,
                style: TextStyle(
                    fontSize: 12.5,
                    color: exists ? AppTheme.text : AppTheme.textDim)),
            subtitle: Text(sub,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10.5, color: AppTheme.textDim)),
            onTap: () {
              if (!exists) return;
              state.openProject(p);
            },
          );
        },
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final r = await FilePicker.pickFiles(
        dialogTitle: 'Open Project',
        allowedExtensions: ['dal', 'kdenlive'],
        type: FileType.custom);
    if (r.isEmpty) return;
    final p = r.single.path;
    if (p == null) return;
    if (p.endsWith('.kdenlive')) {
      if (!context.mounted) return;
      await importKdenlive(context, state, p);
    } else {
      await state.openProject(p);
    }
  }
}
