import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../engine/exporter.dart';
import '../../engine/ffmpeg.dart';
import '../../models/model.dart';
import '../../state/editor_state.dart';
import '../../theme.dart';
import '../dialogs.dart';

/// Project bin: folders, assets, sequences. Double-click opens the source
/// monitor; drag onto the timeline to edit.
class BinPanel extends StatefulWidget {
  final EditorState state;
  final void Function(String assetId) onOpenSource;
  const BinPanel({super.key, required this.state, required this.onOpenSource});

  @override
  State<BinPanel> createState() => _BinPanelState();
}

class _BinPanelState extends State<BinPanel> {
  String _filter = '';
  String _folder = ''; // '' = all

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final assets = s.project.assets.where((a) {
      if (_filter.isNotEmpty &&
          !a.name.toLowerCase().contains(_filter.toLowerCase())) {
        return false;
      }
      if (_folder.isNotEmpty && a.folderId != _folder) return false;
      return true;
    }).toList();
    return Column(children: [
      _toolbar(),
      if (s.project.folders.isNotEmpty) _folderBar(),
      Expanded(
        child: assets.isEmpty
            ? const Center(
                child: Text('Drop or import media',
                    style: TextStyle(color: AppTheme.textDim)))
            : ListView.builder(
                itemCount: assets.length,
                itemBuilder: (_, i) => _row(assets[i]),
              ),
      ),
    ]);
  }

  Widget _toolbar() {
    final s = widget.state;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 15),
            tooltip: 'New bin',
            onPressed: () async {
              final n =
                  await promptText(context, 'New bin', 'Name', initial: 'Bin');
              if (n == null) return;
              setState(() => s.project.folders
                  .add(BinFolder(id: newId(), name: n)));
            }),
        IconButton(
            icon: const Icon(Icons.movie_creation_outlined, size: 15),
            tooltip: 'New sequence',
            onPressed: () => s.newSequence()),
        IconButton(
            icon: const Icon(Icons.title, size: 15),
            tooltip: 'New title',
            onPressed: () async {
              final title = await showTitleEditor(context);
              if (title != null) {
                s.addTitleClip(title['name'] as String, title);
              }
            }),
        IconButton(
            icon: const Icon(Icons.color_lens_outlined, size: 15),
            tooltip: 'Color clip',
            onPressed: () async {
              final c = await showColorPickerDialog(context);
              if (c != null) s.addColorClip('Color', c);
            }),
        IconButton(
            icon: const Icon(Icons.file_upload_outlined, size: 15),
            tooltip: 'Import',
            onPressed: () async {
              final r = await FilePicker.pickFiles();
              if (r.isEmpty) return;
              for (final f in r) {
                if (f.path != null) await s.importFile(f.path!);
              }
            }),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: 22,
            child: TextField(
              style: const TextStyle(fontSize: 11.5),
              decoration: const InputDecoration(
                  hintText: 'Search', prefixIcon: Icon(Icons.search, size: 13)),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _folderBar() {
    final s = widget.state;
    return Container(
      height: 24,
      color: AppTheme.panelAlt,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        _folderChip('', 'All'),
        for (final f in s.project.folders) _folderChip(f.id, f.name),
      ]),
    );
  }

  Widget _folderChip(String id, String name) {
    final on = _folder == id;
    return GestureDetector(
      onTap: () => setState(() => _folder = id),
      child: Container(
        margin: const EdgeInsets.only(right: 4, top: 3, bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: on ? AppTheme.accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
              color: on ? AppTheme.accent : AppTheme.border, width: 0.5),
        ),
        child: Center(
            child: Text(name,
                style: TextStyle(
                    fontSize: 10,
                    color: on ? AppTheme.accent : AppTheme.textDim))),
      ),
    );
  }

  Widget _row(MediaAsset a) {
    final s = widget.state;
    final offline = s.offlineAssets.contains(a.id);
    final sel = s.selectedAssetId == a.id;
    final thumb = s.thumb(a.id);
    return Draggable<String>(
      data: 'asset:${a.id}',
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: AppTheme.panelAlt,
              border: Border.all(color: AppTheme.accent),
              borderRadius: BorderRadius.circular(4)),
          child: Text(a.name,
              style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
        ),
      ),
      child: GestureDetector(
        onTap: () {
          s.selectedAssetId = a.id;
          s.refresh();
        },
        onDoubleTap: () {
          if (a.type == AssetType.sequence) {
            s.openSequence(a.sequenceId!);
          } else {
            widget.onOpenSource(a.id);
          }
        },
        onSecondaryTapUp: (d) => _menu(a, d.globalPosition),
        child: Container(
          height: 40,
          color: sel ? AppTheme.accent.withValues(alpha: 0.12) : null,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            _thumbBox(a, thumb, offline),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(a.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: offline ? AppTheme.danger : AppTheme.text)),
                  Text(
                    _subtitle(a),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textDim),
                  ),
                ],
              ),
            ),
            if (a.proxyPath != null)
              const Tooltip(
                  message: 'Proxy ready',
                  child: Icon(Icons.bolt, size: 12, color: AppTheme.accent)),
          ]),
        ),
      ),
    );
  }

  Widget _thumbBox(MediaAsset a, dynamic thumb, bool offline) {
    return Container(
      width: 52,
      height: 30,
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (thumb != null) Image.memory(thumb, fit: BoxFit.cover),
        if (thumb == null)
          Center(child: Icon(_iconFor(a), size: 16, color: AppTheme.textDim)),
        if (offline)
          Container(
              color: Colors.red.withValues(alpha: 0.35),
              child: const Center(
                  child: Text('OFFLINE',
                      style: TextStyle(fontSize: 7, color: Colors.white)))),
      ]),
    );
  }

  IconData _iconFor(MediaAsset a) => switch (a.type) {
        AssetType.video => Icons.movie_outlined,
        AssetType.audio => Icons.graphic_eq,
        AssetType.image => Icons.image_outlined,
        AssetType.color => Icons.square,
        AssetType.title => Icons.title,
        AssetType.sequence => Icons.movie_filter,
      };

  String _subtitle(MediaAsset a) {
    final d = Duration(milliseconds: (a.durationSec * 1000).round());
    final t = '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return switch (a.type) {
      AssetType.sequence => 'sequence',
      AssetType.title => 'title',
      AssetType.color => 'color',
      _ =>
        '${a.width}x${a.height} ${a.fps.toStringAsFixed(2)}fps  $t',
    };
  }

  void _menu(MediaAsset a, Offset pos) {
    final s = widget.state;
    showMenu<String>(context: context, position: RelativeRect.fromLTRB(
        pos.dx, pos.dy, pos.dx, pos.dy), items: [
      if (a.isAv) ...[
        const PopupMenuItem(value: 'proxy', height: 30, child: Text('Generate proxy')),
        const PopupMenuItem(value: 'transcode', height: 30, child: Text('Transcode…')),
      ],
      const PopupMenuItem(value: 'rename', height: 30, child: Text('Rename')),
      const PopupMenuItem(value: 'relink', height: 30, child: Text('Relocate file…')),
      const PopupMenuItem(value: 'remove', height: 30, child: Text('Remove')),
    ]).then((v) async {
      if (v == null) return;
      switch (v) {
        case 'proxy':
          final src = s.project.resolvedPaths[a.id];
          if (src == null) break;
          final dir = '${s.projectDir}/.cache/proxies';
          Directory(dir).createSync(recursive: true);
          final dst = '$dir/${a.id}.mp4';
          s.status('Generating proxy for ${a.name}…');
          final ok = await FFmpeg.proxy(src, dst,
              width: s.settings.proxyWidth);
          if (ok) {
            a.proxyPath = '.cache/proxies/${a.id}.mp4';
            s.status('Proxy ready: ${a.name}');
          } else {
            s.status('Proxy failed: ${a.name}');
          }
          s.refresh();
          break;
        case 'transcode':
          final src = s.project.resolvedPaths[a.id];
          if (src == null) break;
          final dstUri = await FilePicker.saveFile(
              dialogTitle: 'Transcode to',
              fileName: '${a.name}.mp4',
              bytes: Uint8List(0));
          if (dstUri != null) {
            await Transcoder.run(src, dstUri.toFilePath(), ExportPreset.list[1]);
            s.status('Transcoded ${a.name}');
          }
          break;
        case 'rename':
          if (!mounted) break;
          final n = await promptText(context, 'Rename', 'Name',
              initial: a.name);
          if (n != null) {
            a.name = n;
            s.refresh();
          }
          break;
        case 'relink':
          final r = await FilePicker.pickFiles();
          final p = r.isEmpty ? null : r.single.path;
          if (p != null) {
            a.relPath = s.resolver!.toRelative(p);
            a.fileName = p.split('/').last;
            s.project.resolvedPaths[a.id] = p;
            s.offlineAssets.remove(a.id);
            s.refresh();
          }
          break;
        case 'remove':
          s.edit('Remove asset', () {
            s.project.assets.removeWhere((x) => x.id == a.id);
          });
          break;
      }
    });
  }
}
