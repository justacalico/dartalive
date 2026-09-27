import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../engine/exporter.dart';
import '../../state/editor_state.dart';
import '../../theme.dart';

/// Render queue panel + add-export form.
class ExportPanel extends StatefulWidget {
  final EditorState state;
  const ExportPanel({super.key, required this.state});

  @override
  State<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<ExportPanel> {
  ExportPreset _preset = ExportPreset.list[0];
  bool _range = false;

  @override
  void initState() {
    super.initState();
    widget.state.exporter.updates.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Column(children: [
      _form(s),
      const Divider(height: 1, color: AppTheme.border),
      Expanded(
        child: s.exporter.queue.isEmpty
            ? const Center(
                child: Text('Queue empty',
                    style: TextStyle(color: AppTheme.textDim)))
            : ListView.builder(
                itemCount: s.exporter.queue.length,
                itemBuilder: (_, i) => _jobTile(s.exporter.queue[i]),
              ),
      ),
    ]);
  }

  Widget _form(EditorState s) {
    final seq = s.sequence;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Row(children: [
          const Text('Preset', style: TextStyle(fontSize: 11, color: AppTheme.textDim)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<ExportPreset>(
              value: _preset,
              isDense: true,
              isExpanded: true,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.text),
              dropdownColor: AppTheme.panelAlt,
              underline: const SizedBox(),
              items: [
                for (final p in ExportPreset.list)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _preset = v!),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(_preset.description,
                style: const TextStyle(fontSize: 10, color: AppTheme.textDim)),
          ),
          const Text('In/out only',
              style: TextStyle(fontSize: 10, color: AppTheme.textDim)),
          Checkbox(
            value: _range,
            onChanged: (v) => setState(() => _range = v == true),
            visualDensity: VisualDensity.compact,
          ),
        ]),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 8)),
            onPressed: seq == null ? null : () => _enqueue(s, seq),
            child: const Text('Add to queue', style: TextStyle(fontSize: 12)),
          ),
        ),
      ]),
    );
  }

  Future<void> _enqueue(EditorState s, dynamic seq) async {
    final dir = s.settings.exportDir.isNotEmpty
        ? s.settings.exportDir
        : s.projectDir;
    final suggested = '$dir/${seq.name.replaceAll(' ', '_')}.${_preset.ext}';
    final out = await FilePicker.saveFile(
        dialogTitle: 'Export to',
        fileName: suggested,
        bytes: Uint8List(0));
    if (out == null) return;
    final inF = _range && s.inPoint != null ? s.inPoint! : 0;
    final outF =
        _range && s.outPoint != null ? s.outPoint! : seq.duration;
    s.exporter.enqueue(ExportJob(
      id: newId(),
      sequenceId: seq.id,
      outputPath: out.toFilePath(),
      preset: _preset,
      inFrame: inF,
      outFrame: outF,
      width: s.project.width,
      height: s.project.height,
      fps: s.fps,
    ));
    setState(() {});
  }

  Widget _jobTile(ExportJob j) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: AppTheme.panelAlt,
          border: Border.all(color: AppTheme.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(j.outputPath.split('/').last,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.text),
                overflow: TextOverflow.ellipsis),
          ),
          Text(j.status,
              style: TextStyle(
                  fontSize: 10,
                  color: switch (j.status) {
                    'done' => AppTheme.audioClip,
                    'failed' || 'cancelled' => AppTheme.danger,
                    'running' => AppTheme.accent,
                    _ => AppTheme.textDim,
                  })),
          const SizedBox(width: 6),
          if (j.status == 'running' || j.status == 'queued')
            GestureDetector(
                onTap: () => widget.state.exporter.cancel(j.id),
                child: const Icon(Icons.close, size: 13)),
          if (j.status == 'done' || j.status == 'failed' || j.status == 'cancelled')
            GestureDetector(
                onTap: () => widget.state.exporter.remove(j.id),
                child: const Icon(Icons.delete_outline, size: 13)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: j.progress,
          minHeight: 3,
          backgroundColor: AppTheme.border,
          color: j.status == 'failed' ? AppTheme.danger : AppTheme.accent,
        ),
        if (j.status == 'done')
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: InkWell(
              onTap: () => Process.start(
                  'xdg-open', [File(j.outputPath).parent.path]),
              child: const Text('open folder',
                  style: TextStyle(fontSize: 10, color: AppTheme.accent)),
            ),
          ),
        if (j.error != null)
          Text(j.error!,
              style: const TextStyle(fontSize: 9.5, color: AppTheme.danger)),
      ]),
    );
  }
}
