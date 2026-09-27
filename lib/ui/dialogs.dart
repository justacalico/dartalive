import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/exporter.dart';
import '../io/kdenlive_import.dart';
import '../state/editor_state.dart';
import '../state/shortcuts.dart';
import '../theme.dart';
import 'title_editor.dart';

Future<String?> promptText(BuildContext context, String title, String label,
    {String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('OK')),
      ],
    ),
  );
}

const _swatches = [
  '0x000000', '0xffffff', '0x808080', '0xff0000', '0x00ff00', '0x0000ff',
  '0xffff00', '0xff8800', '0xff00ff', '0x00ffff', '0x8b4513', '0x4a7fb5',
];

/// Simple swatch + hex color picker; returns '0xRRGGBB'.
Future<String?> showColorPickerDialog(BuildContext context,
    {String initial = '0x3f8f63'}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = TextEditingController(text: initial.replaceAll('0x', ''));
      return AlertDialog(
        title: const Text('Pick color'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in _swatches)
              GestureDetector(
                onTap: () => Navigator.pop(ctx, s),
                child: Container(
                  width: 28,
                  height: 28,
                  color: Color(int.parse(s.substring(2), radix: 16) | 0xff000000),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
              controller: c,
              decoration: const InputDecoration(labelText: 'Hex RRGGBB'),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))
              ]),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                var v = c.text.replaceAll('#', '');
                if (v.length == 8) v = v.substring(2);
                if (v.length != 6) return;
                Navigator.pop(ctx, '0x$v');
              },
              child: const Text('OK')),
        ],
      );
    },
  );
}

/// Small inline variant used by the effect stack.
Future<String?> colorField(BuildContext context, String current) =>
    showColorPickerDialog(context, initial: current);

Future<Map<String, dynamic>?> showTitleEditor(BuildContext context,
    {Map<String, dynamic>? existing}) {
  return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => TitleEditorDialog(existing: existing));
}

Future<void> importKdenlive(
    BuildContext context, EditorState s, String path) async {
  try {
    s.status('Importing Kdenlive project…');
    final p = await KdenliveImport.run(path);
    s.loadImportedProject(p, path);
    s.status('Imported ${p.sequences.length} sequence(s), '
        '${p.assets.length} assets');
  } catch (e) {
    s.status('Kdenlive import failed: $e');
    if (context.mounted) {
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Import failed'),
                content: Text('$e',
                    style: const TextStyle(fontSize: 11)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'))
                ],
              ));
    }
  }
}

class SettingsDialog extends StatefulWidget {
  final EditorState state;
  const SettingsDialog({super.key, required this.state});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TextEditingController _ffmpeg, _ffprobe, _cache, _autosave,
      _proxyW, _defTrans, _exportDir;

  @override
  void initState() {
    super.initState();
    final s = widget.state.settings;
    _ffmpeg = TextEditingController(text: s.ffmpegPath);
    _ffprobe = TextEditingController(text: s.ffprobePath);
    _cache = TextEditingController(text: '${s.cacheMb}');
    _autosave = TextEditingController(text: '${s.autosaveSec}');
    _proxyW = TextEditingController(text: '${s.proxyWidth}');
    _defTrans = TextEditingController(text: '${s.defaultTransitionFrames}');
    _exportDir = TextEditingController(text: s.exportDir);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state.settings;
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _row('ffmpeg', _ffmpeg),
            _row('ffprobe', _ffprobe),
            _row('Frame cache (MB)', _cache, number: true),
            _row('Autosave (sec)', _autosave, number: true),
            _row('Proxy width', _proxyW, number: true),
            _row('Default transition (frames)', _defTrans, number: true),
            _row('Export directory', _exportDir),
            const SizedBox(height: 8),
            _check('Use proxy media for preview', st.useProxies,
                (v) => st.useProxies = v),
            _check('Snapping', st.snapping, (v) => st.snapping = v),
            _check('Audio scrub', st.audioScrub, (v) => st.audioScrub = v),
            const SizedBox(height: 8),
            const Text('Preview resolution',
                style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 0.25, label: Text('25%')),
                ButtonSegment(value: 0.5, label: Text('50%')),
                ButtonSegment(value: 1.0, label: Text('Full')),
              ],
              selected: {st.previewScale},
              onSelectionChanged: (v) => setState(() {
                st.previewScale = v.first;
                widget.state.frameServer.scale = v.first;
                widget.state.frameServer.invalidate();
              }),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
            onPressed: () {
              st.ffmpegPath = _ffmpeg.text;
              st.ffprobePath = _ffprobe.text;
              st.cacheMb = int.tryParse(_cache.text) ?? st.cacheMb;
              st.autosaveSec = int.tryParse(_autosave.text) ?? st.autosaveSec;
              st.proxyWidth = int.tryParse(_proxyW.text) ?? st.proxyWidth;
              st.defaultTransitionFrames =
                  int.tryParse(_defTrans.text) ?? st.defaultTransitionFrames;
              st.exportDir = _exportDir.text;
              st.save();
              widget.state.frameServer.maxCacheMb = st.cacheMb;
              widget.state.frameServer.useProxies = st.useProxies;
              Navigator.pop(context);
            },
            child: const Text('Save')),
      ],
    );
  }

  Widget _row(String label, TextEditingController c, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 160,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 11, color: AppTheme.textDim))),
        Expanded(
          child: TextField(
              controller: c,
              style: const TextStyle(fontSize: 11.5),
              keyboardType:
                  number ? TextInputType.number : TextInputType.text),
        ),
      ]),
    );
  }

  Widget _check(String label, bool v, void Function(bool) set) {
    return StatefulBuilder(
      builder: (ctx, ss) => Row(children: [
        Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 11, color: AppTheme.textDim))),
        Checkbox(
            value: v,
            onChanged: (x) => ss(() => set(x == true)),
            visualDensity: VisualDensity.compact),
      ]),
    );
  }
}

class ShortcutsDialog extends StatefulWidget {
  final ShortcutMap shortcuts;
  final void Function(Map<String, String>) onChanged;
  const ShortcutsDialog(
      {super.key, required this.shortcuts, required this.onChanged});

  @override
  State<ShortcutsDialog> createState() => _ShortcutsDialogState();
}

class _ShortcutsDialogState extends State<ShortcutsDialog> {
  String? _recording;

  @override
  Widget build(BuildContext context) {
    final cmds = Commands.names.entries.toList();
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (_recording == null) return KeyEventResult.ignored;
            final c = KeyCombo.fromEvent(e);
            if (c == null) return KeyEventResult.handled;
            setState(() {
              widget.shortcuts.map[_recording!] = c.encode();
              _recording = null;
            });
            widget.onChanged(widget.shortcuts.map);
            return KeyEventResult.handled;
          },
          child: ListView(children: [
            if (_recording != null)
              const Padding(
                padding: EdgeInsets.all(6),
                child: Text('Press a key combo…  (Esc to cancel)',
                    style: TextStyle(color: AppTheme.accent, fontSize: 11)),
              ),
            for (final c in cmds) _row(c.key, c.value),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              setState(() {
                widget.shortcuts.map
                  ..clear()
                  ..addAll(Commands.defaults);
              });
              widget.onChanged(widget.shortcuts.map);
            },
            child: const Text('Reset defaults')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done')),
      ],
    );
  }

  Widget _row(String id, String name) {
    final rec = _recording == id;
    return InkWell(
      onTap: () => setState(() => _recording = id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(children: [
          Expanded(
              child: Text(name,
                  style: const TextStyle(fontSize: 11.5,
                      color: AppTheme.text))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: rec ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.panel,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: rec ? AppTheme.accent : AppTheme.border)),
            child: Text(rec ? '…' : widget.shortcuts.combo(id),
                style: const TextStyle(fontSize: 10.5, color: AppTheme.text)),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              setState(() => widget.shortcuts.map[id] = '');
              widget.onChanged(widget.shortcuts.map);
            },
            child: const Icon(Icons.clear, size: 12, color: AppTheme.textDim),
          ),
        ]),
      ),
    );
  }
}

class ExportDialog extends StatelessWidget {
  final EditorState state;
  const ExportDialog({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
          width: 480, height: 420, child: _ExportDialogBody(state: state)),
    );
  }
}

class _ExportDialogBody extends StatefulWidget {
  final EditorState state;
  const _ExportDialogBody({required this.state});

  @override
  State<_ExportDialogBody> createState() => _ExportDialogBodyState();
}

class _ExportDialogBodyState extends State<_ExportDialogBody> {
  ExportPreset _preset = ExportPreset.list[0];
  bool _range = false;
  int _w = 0, _h = 0;
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.state.project;
    _w = p.width;
    _h = p.height;
    _fps = p.fpsValue;
    _expSub = widget.state.exporter.updates.listen((_) {
      if (mounted) setState(() {});
    });
  }

  StreamSubscription? _expSub;

  @override
  void dispose() {
    _expSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final seq = s.sequence;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Export',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          const Text('Sequence',
              style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: seq?.id,
              isDense: true,
              isExpanded: true,
              dropdownColor: AppTheme.panelAlt,
              underline: const SizedBox(),
              items: [
                for (final sq in s.project.sequences)
                  DropdownMenuItem(
                      value: sq.id,
                      child: Text(sq.name,
                          style: const TextStyle(fontSize: 11.5)))
              ],
              onChanged: (v) => s.openSequence(v!),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        DropdownButton<ExportPreset>(
          value: _preset,
          isDense: true,
          isExpanded: true,
          dropdownColor: AppTheme.panelAlt,
          underline: const SizedBox(),
          items: [
            for (final p in ExportPreset.list)
              DropdownMenuItem(value: p, child: Text(p.name,
                  style: const TextStyle(fontSize: 11.5))),
          ],
          onChanged: (v) => setState(() => _preset = v!),
        ),
        Text(_preset.description,
            style: const TextStyle(fontSize: 10, color: AppTheme.textDim)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _num('Width', _w, (v) => setState(() => _w = v))),
          const SizedBox(width: 8),
          Expanded(
              child: _num('Height', _h, (v) => setState(() => _h = v))),
          const SizedBox(width: 8),
          Expanded(
              child: _num('FPS', _fps.round(),
                  (v) => setState(() => _fps = v.toDouble()))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Checkbox(
              value: _range,
              onChanged: (v) => setState(() => _range = v == true),
              visualDensity: VisualDensity.compact),
          const Text('Export in/out range only',
              style: TextStyle(fontSize: 11)),
        ]),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.black),
            onPressed: () async {
              if (seq == null) return;
              final dir = s.settings.exportDir.isNotEmpty
                  ? s.settings.exportDir
                  : s.projectDir;
              final out = await FilePicker.saveFile(
                  dialogTitle: 'Export to',
                  bytes: Uint8List(0),
                  fileName:
                      '$dir/${seq.name.replaceAll(' ', '_')}.${_preset.ext}');
              if (out == null || !context.mounted) return;
              s.exporter.enqueue(ExportJob(
                id: newId(),
                sequenceId: seq.id,
                outputPath: out.toFilePath(),
                preset: _preset,
                inFrame: _range && s.inPoint != null ? s.inPoint! : 0,
                outFrame:
                    _range && s.outPoint != null ? s.outPoint! : seq.duration,
                width: _w,
                height: _h,
                fps: _fps,
              ));
              if (context.mounted) Navigator.pop(context);
              s.status('Queued export → $out');
            },
            child: const Text('Export'),
          ),
        ),
      ]),
    );
  }

  Widget _num(String label, int v, void Function(int) set) {
    // initialValue keeps the field's own state across rebuilds
    return TextFormField(
      initialValue: '$v',
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 11.5),
      decoration: InputDecoration(labelText: label),
      onChanged: (t) {
        final n = int.tryParse(t);
        if (n != null) set(n);
      },
    );
  }
}
