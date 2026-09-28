import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models/model.dart';
import 'models/sequence_ops.dart';
import 'state/editor_state.dart';
import 'state/shortcuts.dart';
import 'theme.dart';
import 'ui/dialogs.dart';
import 'ui/dock.dart';
import 'ui/welcome.dart';
import 'ui/window_frame.dart';
import 'ui/panels/bin.dart';
import 'ui/panels/effect_stack.dart';
import 'ui/panels/effects_library.dart';
import 'ui/panels/export_panel.dart';
import 'ui/panels/history.dart';
import 'ui/panels/mixer.dart';
import 'ui/panels/program_monitor.dart';
import 'ui/panels/scopes.dart';
import 'ui/panels/source_monitor.dart';
import 'ui/panels/timeline_panel.dart';

class EditorApp extends StatefulWidget {
  final EditorState state;
  const EditorApp({super.key, required this.state});

  @override
  State<EditorApp> createState() => _EditorAppState();
}

class _EditorAppState extends State<EditorApp> {
  late DockLayout layout;
  late ShortcutMap shortcuts;
  final FocusNode _keyFocus = FocusNode();
  String? _sourceAssetId;

  @override
  void initState() {
    super.initState();
    layout = DockLayout.decode(widget.state.settings.layout) ??
        DockLayout.defaults();
    shortcuts = ShortcutMap(widget.state.settings.shortcuts);
    widget.state.addListener(_onState);
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _keyFocus.dispose();
    super.dispose();
  }

  Map<String, PanelDef> get _registry => {
        'bin': PanelDef('bin', 'Project', Icons.folder_outlined,
            () => BinPanel(state: widget.state, onOpenSource: _openSource)),
        'source': PanelDef('source', 'Source', Icons.smart_display,
            () => SourceMonitor(state: widget.state, assetId: _sourceAssetId)),
        'program': PanelDef('program', 'Program', Icons.tv,
            () => ProgramMonitor(state: widget.state)),
        'timeline': PanelDef('timeline', 'Timeline', Icons.view_timeline,
            () => TimelinePanel(state: widget.state)),
        'effectstack': PanelDef(
            'effectstack',
            'Effect Stack',
            Icons.auto_fix_high,
            () => EffectStackPanel(state: widget.state)),
        'effects': PanelDef('effects', 'Effects', Icons.blur_on,
            () => EffectsLibraryPanel(state: widget.state)),
        'mixer': PanelDef('mixer', 'Audio Mixer', Icons.tune,
            () => MixerPanel(state: widget.state)),
        'history': PanelDef('history', 'History', Icons.history,
            () => HistoryPanel(state: widget.state)),
        'export': PanelDef('export', 'Export', Icons.ios_share,
            () => ExportPanel(state: widget.state)),
        'scopes': PanelDef('scopes', 'Scopes', Icons.bar_chart,
            () => ScopesPanel(state: widget.state)),
      };

  void _openSource(String assetId) {
    setState(() => _sourceAssetId = assetId);
    // make sure the source tab is visible in center group
    for (final g in layout.areas['center']!) {
      final i = g.panels.indexOf('source');
      if (i >= 0) {
        g.active = i;
        return;
      }
    }
    layout.dock('source', 'center', 0);
  }

  void _exec(String command) async {
    final s = widget.state;
    final seq = s.sequence;
    switch (command) {
      case Commands.playPause:
        s.togglePlay();
        break;
      case Commands.playForward:
        s.play(rate: s.playRate == 1 ? 2 : (s.playRate > 0 ? s.playRate + 1 : 1));
        break;
      case Commands.playBackward:
        s.play(rate: s.playRate > -1 ? -1 : s.playRate - 1);
        break;
      case Commands.stop:
        s.stopPlayback();
        break;
      case Commands.frameBack:
        s.stopPlayback(notify: false);
        s.seek(s.playhead - 1);
        break;
      case Commands.frameFwd:
        s.stopPlayback(notify: false);
        s.seek(s.playhead + 1);
        break;
      case Commands.goStart:
        s.seek(0);
        break;
      case Commands.goEnd:
        s.seek(max(0, s.seqDuration - 1));
        break;
      case Commands.prevEdit:
        if (seq == null) break;
        s.seek(_nearestEdge(seq, s.playhead, -1));
        break;
      case Commands.nextEdit:
        if (seq == null) break;
        s.seek(_nearestEdge(seq, s.playhead, 1));
        break;
      case Commands.setIn:
        s.inPoint = s.playhead;
        s.refresh();
        break;
      case Commands.setOut:
        s.outPoint = s.playhead;
        s.refresh();
        break;
      case Commands.clearInOut:
        s.inPoint = null;
        s.outPoint = null;
        s.refresh();
        break;
      case Commands.markClip:
        if (seq == null) break;
        // topmost video track wins, then audio
        for (final t in seq.tracks) {
          final c = t.clipAt(s.playhead);
          if (c != null) {
            s.inPoint = c.position;
            s.outPoint = c.end;
            break;
          }
        }
        s.refresh();
        break;
      case Commands.addMarker:
        if (seq == null) break;
        s.edit('Add marker', () {
          seq.markers.add(Marker(s.playhead, ''));
        });
        break;
      case Commands.cut:
        if (seq == null) break;
        s.edit('Cut', () {
          SeqOps.splitAt(seq, s.playhead, s.fps);
        });
        break;
      case Commands.delete:
        if (seq == null) break;
        s.edit('Delete', () {
          for (final id in s.selectedClips.toList()) {
            SeqOps.removeClip(seq, id);
          }
          s.selectedClips.clear();
        });
        break;
      case Commands.rippleDelete:
        if (seq == null) break;
        s.edit('Ripple delete', () {
          for (final id in s.selectedClips.toList()) {
            SeqOps.removeClip(seq, id, ripple: true);
          }
          s.selectedClips.clear();
        });
        break;
      case Commands.undo:
        s.undo();
        break;
      case Commands.redo:
        s.redo();
        break;
      case Commands.save:
        _save();
        break;
      case Commands.saveAs:
        _saveAs();
        break;
      case Commands.openProject:
        _open();
        break;
      case Commands.newProject:
        s.newProject();
        break;
      case Commands.newSequence:
        _newSequence();
        break;
      case Commands.importMedia:
        _import();
        break;
      case Commands.export:
        _saveLayout();
        showDialog(
            context: context,
            builder: (_) => ExportDialog(state: s));
        break;
      case Commands.zoomIn:
        s.timelineZoom = (s.timelineZoom * 1.25).clamp(1, 400);
        s.refresh();
        break;
      case Commands.zoomOut:
        s.timelineZoom = (s.timelineZoom / 1.25).clamp(1, 400);
        s.refresh();
        break;
      case Commands.zoomFit:
        s.timelineZoom = -1; // sentinel = fit
        s.refresh();
        break;
      case Commands.toolSelect:
        s.tool = 'select';
        s.refresh();
        break;
      case Commands.toolRazor:
        s.tool = 'razor';
        s.refresh();
        break;
      case Commands.toolRipple:
        s.tool = 'ripple';
        s.refresh();
        break;
      case Commands.toolSlip:
        s.tool = 'slip';
        s.refresh();
        break;
      case Commands.toolSlide:
        s.tool = 'slide';
        s.refresh();
        break;
      case Commands.selectAll:
        if (seq == null) break;
        s.selectedClips
          ..clear()
          ..addAll(seq.tracks.expand((t) => t.clips.map((c) => c.id)));
        s.refresh();
        break;
      case Commands.deselect:
        s.clearSelection();
        break;
      case Commands.duplicate:
        _duplicate();
        break;
      case Commands.copyClip:
        _copy();
        break;
      case Commands.pasteClip:
        _paste();
        break;
      case Commands.addTransition:
        _defaultTransition();
        break;
      case Commands.lift:
        _lift(extract: false);
        break;
      case Commands.extract:
        _lift(extract: true);
        break;
      case Commands.toggleFullscreen:
        s.fullscreenPreview = !s.fullscreenPreview;
        s.refresh();
        break;
      case Commands.renderZone:
        _renderZone();
        break;
      case Commands.findMedia:
        _relocate();
        break;
    }
  }

  int _nearestEdge(Sequence seq, int frame, int dir) {
    int? best;
    for (final t in seq.tracks) {
      for (final c in t.clips) {
        for (final e in [c.position, c.end]) {
          if (dir < 0 && e < frame && (best == null || e > best)) best = e;
          if (dir > 0 && e > frame && (best == null || e < best)) best = e;
        }
      }
    }
    return best ?? frame;
  }

  void _duplicate() {
    final s = widget.state;
    final seq = s.sequence;
    if (seq == null) return;
    s.edit('Duplicate', () {
      for (final id in s.selectedClips.toList()) {
        final c = s.clipById(id);
        final t = s.trackOfClip(id);
        if (c == null || t == null) continue;
        final n = c.clone(newId());
        n.position = c.end;
        n.linkGroup = null;
        t.clips.add(n);
        s.selectedClips
          ..remove(id)
          ..add(n.id);
      }
    });
  }

  void _copy() {
    final s = widget.state;
    s.clipboard = s.selectedClips
        .map((id) => s.clipById(id))
        .whereType<Clip>()
        .map((c) => jsonEncodeClip(c))
        .toList();
    s.status('${s.clipboard.length} clip(s) copied');
  }

  void _paste() {
    final s = widget.state;
    final seq = s.sequence;
    if (seq == null || s.clipboard.isEmpty) return;
    s.edit('Paste', () {
      s.selectedClips.clear();
      for (final raw in s.clipboard) {
        final c = clipFromJson(raw);
        final target = seq.videoTracks.isNotEmpty &&
                _assetIsVideo(s, c.assetId)
            ? seq.videoTracks.last
            : (seq.audioTracks.isEmpty ? seq.tracks.last : seq.audioTracks.first);
        c.id = newId();
        c.position = s.playhead;
        c.linkGroup = null;
        target.clips.add(c);
        s.selectedClips.add(c.id);
      }
    });
  }

  bool _assetIsVideo(EditorState s, String assetId) {
    final a = s.project.assetById(assetId);
    return a != null && a.hasVideo;
  }

  void _defaultTransition() {
    final s = widget.state;
    s.edit('Add transition', () {
      for (final id in s.selectedClips) {
        final c = s.clipById(id);
        if (c != null) {
          c.transition = ClipTransition(
              duration: s.settings.defaultTransitionFrames);
        }
      }
    });
  }

  void _lift({required bool extract}) {
    final s = widget.state;
    final seq = s.sequence;
    if (seq == null || s.inPoint == null || s.outPoint == null) return;
    s.edit(extract ? 'Extract' : 'Lift', () {
      // split at edges then lift the inside
      SeqOps.splitAt(seq, s.inPoint!, s.fps);
      SeqOps.splitAt(seq, s.outPoint!, s.fps);
      SeqOps.liftRegion(seq, s.inPoint!, s.outPoint!, s.fps, ripple: extract);
    });
  }

  Future<void> _save() async {
    final s = widget.state;
    if (s.projectPath == null) {
      return _saveAs();
    }
    await s.saveProject();
  }

  Future<void> _saveAs() async {
    final s = widget.state;
    final p = await FilePicker.saveFile(
      dialogTitle: 'Save project',
      fileName: '${s.project.name}.dal',
      bytes: Uint8List(0),
      type: FileType.custom,
      allowedExtensions: ['dal'],
    );
    if (p != null) {
      final fp = p.toFilePath();
      await s.saveProject(fp.endsWith('.dal') ? fp : '$fp.dal');
    }
  }

  Future<void> _open() async {
    final r = await FilePicker.pickFiles(
        dialogTitle: 'Open project',
        type: FileType.custom,
        allowedExtensions: ['dal', 'kdenlive']);
    final p = r.isEmpty ? null : r.single.path;
    if (p == null) return;
    if (p.endsWith('.kdenlive')) {
      if (!mounted) return;
      await importKdenlive(context, widget.state, p);
    } else {
      await widget.state.openProject(p);
    }
  }

  Future<void> _import() async {
    final r = await FilePicker.pickFiles(
        dialogTitle: 'Import media');
    if (r.isEmpty) return;
    for (final f in r) {
      if (f.path != null) {
        await widget.state.importFile(f.path!,
            onStatus: (m) => widget.state.status(m));
      }
    }
  }

  void _newSequence() async {
    final name = await promptText(context, 'New sequence', 'Name',
        initial: 'Sequence ${widget.state.project.sequences.length + 1}');
    if (name == null) return;
    widget.state.newSequence(name: name);
  }

  void _renderZone() {
    final s = widget.state;
    showDialog(context: context, builder: (_) => ExportDialog(state: s));
  }

  Future<void> _relocate() async {
    final s = widget.state;
    final r = s.resolver;
    if (r == null) return;
    final missing = await r.resolveAll(s.project);
    s.offlineAssets
      ..clear()
      ..addAll(missing);
    s.status(missing.isEmpty
        ? 'All media online'
        : '${missing.length} asset(s) still offline');
    s.refresh();
  }

  void _saveLayout() {
    widget.state.settings.layout = layout.encode();
    widget.state.settings.save();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (s.welcomeVisible) {
      return WelcomeScreen(state: s);
    }
    return Focus(
      autofocus: true,
      onKeyEvent: (node, e) {
        final combo = KeyCombo.fromEvent(e);
        if (combo == null) return KeyEventResult.ignored;
        final cmd = shortcuts.commandFor(combo);
        if (cmd != null) {
          _exec(cmd);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: Column(children: [
          _menuBar(),
          Expanded(
            child: s.fullscreenPreview
                ? ProgramMonitor(state: s)
                : DockAreaView(
                    layout: layout,
                    registry: _registry,
                    onChanged: _saveLayout),
          ),
          _statusBar(),
        ]),
      ),
    );
  }

  Widget _menuBar() {
    final s = widget.state;
    return Container(
      height: 32,
      color: AppTheme.header,
      padding: const EdgeInsets.only(left: 8),
      child: DragToMoveArea(
        child: Row(children: [
          Image.asset('assets/icon-1024.png', width: 18, height: 18),
          const SizedBox(width: 6),
          const Text('dartalive',
              style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.5)),
          const SizedBox(width: 14),
          _menu('File', [
            ('New project', Commands.newProject),
            ('Open…', Commands.openProject),
            ('Import media…', Commands.importMedia),
            ('Import Kdenlive project…', ''),
            ('Save', Commands.save),
            ('Save as…', Commands.saveAs),
            ('Export…', Commands.export),
          ]),
          _menu('Edit', [
            ('Undo', Commands.undo),
            ('Redo', Commands.redo),
            ('Copy', Commands.copyClip),
            ('Paste', Commands.pasteClip),
            ('Delete', Commands.delete),
            ('Ripple delete', Commands.rippleDelete),
            ('Select all', Commands.selectAll),
          ]),
          _menu('Sequence', [
            ('New sequence', Commands.newSequence),
            ('Cut at playhead', Commands.cut),
            ('Add transition', Commands.addTransition),
            ('Add marker', Commands.addMarker),
            ('Lift in/out', Commands.lift),
            ('Extract in/out', Commands.extract),
            ('Render zone', Commands.renderZone),
          ]),
          _menu('View', [
            ('Layout: Editing', ''),
            ('Layout: Color', ''),
            ('Layout: Audio', ''),
            ('Toggle fullscreen preview', Commands.toggleFullscreen),
          ]),
          _menu('Tools', [
            ('Settings…', ''),
            ('Keyboard shortcuts…', ''),
            ('Relocate missing media', Commands.findMedia),
          ]),
          const Spacer(),
          Text(s.project.name,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 11)),
          if (s.dirty)
            const Text(' •',
                style: TextStyle(color: AppTheme.accent, fontSize: 16)),
          const WindowButtons(),
        ]),
      ),
    );
  }

  Widget _menu(String label, List<(String, String)> items) {
    return PopupMenuButton<String>(
      tooltip: '',
      offset: const Offset(0, 28),
      itemBuilder: (_) => [
        for (final it in items)
          PopupMenuItem(
            value: it.$1,
            height: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(it.$1, style: const TextStyle(fontSize: 12)),
                if (it.$2.isNotEmpty)
                  Text(shortcutLabel(it.$2),
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 10)),
              ],
            ),
          ),
      ],
      onSelected: (v) => _menuAction(v),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child:
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.text)),
      ),
    );
  }

  String shortcutLabel(String command) {
    final c = shortcuts.combo(command);
    if (c.isEmpty) return '';
    return c.replaceAll('ctrl', 'Ctrl').replaceAll('shift', 'Shift');
  }

  void _menuAction(String item) async {
    final s = widget.state;
    switch (item) {
      case 'Import Kdenlive project…':
        final r = await FilePicker.pickFiles(
            type: FileType.custom, allowedExtensions: ['kdenlive', 'xml']);
        if (r.isNotEmpty && r.single.path != null) {
          if (!mounted) break;
          await importKdenlive(context, s, r.single.path!);
        }
        break;
      case 'Settings…':
        await showDialog(
            context: context,
            builder: (_) => SettingsDialog(state: s));
        break;
      case 'Keyboard shortcuts…':
        await showDialog(
            context: context,
            builder: (_) => ShortcutsDialog(
                shortcuts: shortcuts,
                onChanged: (m) {
                  s.settings.shortcuts = m;
                  s.settings.save();
                }));
        break;
      case 'Layout: Editing':
        setState(() => layout = DockLayout.defaults());
        _saveLayout();
        break;
      case 'Layout: Color':
        setState(() {
          layout = DockLayout();
          layout.areas['left'] = [PanelGroup(['bin'])];
          layout.areas['center'] = [PanelGroup(['program', 'scopes'])];
          layout.areas['right'] = [PanelGroup(['effectstack']), PanelGroup(['effects'])];
          layout.areas['bottom'] = [PanelGroup(['timeline'])];
        });
        _saveLayout();
        break;
      case 'Layout: Audio':
        setState(() {
          layout = DockLayout();
          layout.areas['left'] = [PanelGroup(['bin', 'effects'])];
          layout.areas['center'] = [PanelGroup(['program', 'source'])];
          layout.areas['right'] = [PanelGroup(['mixer'])];
          layout.areas['bottom'] = [PanelGroup(['timeline'])];
        });
        _saveLayout();
        break;
      default:
        // items carry their command as second tuple element, but PopupMenu
        // only returns value ($1) — re-dispatch via command map
        final cmd = _commandByLabel(item);
        if (cmd != null) _exec(cmd);
    }
  }

  String? _commandByLabel(String label) {
    for (final e in Commands.names.entries) {
      if (e.value == label || label.startsWith(e.value)) return e.key;
    }
    // fallbacks for slightly different menu labels
    const map = {
      'New project': Commands.newProject,
      'Open…': Commands.openProject,
      'Import media…': Commands.importMedia,
      'Save': Commands.save,
      'Save as…': Commands.saveAs,
      'Export…': Commands.export,
      'Undo': Commands.undo,
      'Redo': Commands.redo,
      'Copy': Commands.copyClip,
      'Paste': Commands.pasteClip,
      'Delete': Commands.delete,
      'Ripple delete': Commands.rippleDelete,
      'Select all': Commands.selectAll,
      'New sequence': Commands.newSequence,
      'Cut at playhead': Commands.cut,
      'Add transition': Commands.addTransition,
      'Add marker': Commands.addMarker,
      'Lift in/out': Commands.lift,
      'Extract in/out': Commands.extract,
      'Render zone': Commands.renderZone,
      'Toggle fullscreen preview': Commands.toggleFullscreen,
      'Relocate missing media': Commands.findMedia,
    };
    return map[label];
  }

  Widget _statusBar() {
    final s = widget.state;
    final frames = s.frameServer;
    return Container(
      height: 22,
      color: AppTheme.header,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Text(s.statusMessage ?? '',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textDim)),
        const Spacer(),
        if (s.offlineAssets.isNotEmpty)
          Text('${s.offlineAssets.length} offline',
              style: const TextStyle(color: AppTheme.danger, fontSize: 10.5)),
        const SizedBox(width: 12),
        Text('tool: ${s.tool}',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textDim)),
        const SizedBox(width: 12),
        Text('cache ${(frames.cacheBytes / 1048576).round()}MB',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textDim)),
      ]),
    );
  }
}
