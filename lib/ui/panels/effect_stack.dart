import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/effects.dart';
import '../../models/model.dart';
import '../../state/editor_state.dart';
import '../../theme.dart';
import '../dialogs.dart';

/// Effect stack for the selected clip: reorderable effects with parameter
/// editors and per-param keyframes.
class EffectStackPanel extends StatefulWidget {
  final EditorState state;
  const EffectStackPanel({super.key, required this.state});

  @override
  State<EffectStackPanel> createState() => _EffectStackPanelState();
}

class _EffectStackPanelState extends State<EffectStackPanel> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final clip = s.selectedClipId != null ? s.clipById(s.selectedClipId!) : null;
    if (clip == null) {
      return const Center(
          child: Text('Select a clip', style: TextStyle(color: AppTheme.textDim)));
    }
    return Column(children: [
      _header(clip),
      Expanded(
        child: ListView(children: [
          for (var i = 0; i < clip.effects.length; i++)
            _effectTile(clip, clip.effects[i], i),
          _addButton(clip),
        ]),
      ),
    ]);
  }

  Widget _header(Clip clip) {
    final s = widget.state;
    return Container(
      height: 28,
      color: AppTheme.panelAlt,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Expanded(
          child: Text(clip.name ?? 'clip',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.text),
              overflow: TextOverflow.ellipsis),
        ),
        Text('${clip.position}f +${clip.duration}f',
            style: const TextStyle(fontSize: 10, color: AppTheme.textDim)),
        const SizedBox(width: 6),
        InkWell(
          onTap: () => s.edit('Toggle clip', () => clip.enabled = !clip.enabled),
          child: Icon(clip.enabled ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14, color: AppTheme.accent),
        ),
      ]),
    );
  }

  Widget _addButton(Clip clip) {
    final s = widget.state;
    final isAudioClip = s.trackOfClip(clip.id)?.kind == TrackKind.audio;
    final defs = isAudioClip ? Effects.audio : Effects.video;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: PopupMenuButton<String>(
        tooltip: 'Add effect',
        onSelected: (id) {
          final def = Effects.byId(id);
          if (def == null) return;
          s.edit('Add effect', () {
            clip.effects.add(ClipEffect(
                id: newId(), effectId: id, values: def.defaults()));
            _expanded.add(clip.effects.last.id);
          });
        },
        itemBuilder: (_) => [
          for (final d in defs)
            PopupMenuItem(
                value: d.id,
                height: 28,
                child: Text('${d.category} / ${d.name}',
                    style: const TextStyle(fontSize: 11.5))),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(3)),
          child: const Center(
              child: Text('+ Add effect',
                  style: TextStyle(fontSize: 11, color: AppTheme.textDim))),
        ),
      ),
    );
  }

  Widget _effectTile(Clip clip, ClipEffect fx, int index) {
    final s = widget.state;
    final def = Effects.byId(fx.effectId);
    final open = _expanded.contains(fx.id);
    if (def == null) return const SizedBox();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
          color: AppTheme.panelAlt,
          border: Border.all(color: AppTheme.border, width: 0.5),
          borderRadius: BorderRadius.circular(3)),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() =>
              open ? _expanded.remove(fx.id) : _expanded.add(fx.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(children: [
              Icon(open ? Icons.expand_more : Icons.chevron_right,
                  size: 13, color: AppTheme.textDim),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(def.name,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: fx.enabled
                              ? AppTheme.text
                              : AppTheme.textDim))),
              GestureDetector(
                onTap: () => s.edit('Toggle effect',
                    () => fx.enabled = !fx.enabled),
                child: Icon(Icons.power_settings_new,
                    size: 13,
                    color: fx.enabled ? AppTheme.accent : AppTheme.textDim),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: index > 0
                    ? () => s.edit('Move effect', () {
                          clip.effects.removeAt(index);
                          clip.effects.insert(index - 1, fx);
                        })
                    : null,
                child: const Icon(Icons.arrow_upward,
                    size: 12, color: AppTheme.textDim),
              ),
              GestureDetector(
                onTap: index < clip.effects.length - 1
                    ? () => s.edit('Move effect', () {
                          clip.effects.removeAt(index);
                          clip.effects.insert(index + 1, fx);
                        })
                    : null,
                child: const Icon(Icons.arrow_downward,
                    size: 12, color: AppTheme.textDim),
              ),
              GestureDetector(
                onTap: () => s.edit('Remove effect',
                    () => clip.effects.removeAt(index)),
                child: const Icon(Icons.close,
                    size: 12, color: AppTheme.textDim),
              ),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(children: [
              for (final p in def.params) _param(clip, fx, p),
            ]),
          ),
      ]),
    );
  }

  Widget _param(Clip clip, ClipEffect fx, ParamDef p) {
    final s = widget.state;
    final hasKeys = (fx.keyframes[p.id]?.length ?? 0) > 0;
    switch (p.type) {
      case ParamType.toggle:
        return Row(children: [
          Expanded(
              child: Text(p.name,
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textDim))),
          Checkbox(
            value: fx.values[p.id] == true || fx.values[p.id] == 1,
            onChanged: (v) => s.edit('Set ${p.name}',
                () => fx.values[p.id] = v == true),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ]);
      case ParamType.choice:
        return Row(children: [
          Expanded(
              child: Text(p.name,
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textDim))),
          DropdownButton<String>(
            value: fx.strVal(p.id, p.options.isEmpty ? '' : p.options.first),
            isDense: true,
            style: const TextStyle(fontSize: 11, color: AppTheme.text),
            dropdownColor: AppTheme.panelAlt,
            underline: const SizedBox(),
            items: [
              for (final o in p.options)
                DropdownMenuItem(value: o, child: Text(o))
            ],
            onChanged: (v) =>
                s.edit('Set ${p.name}', () => fx.values[p.id] = v),
          ),
        ]);
      case ParamType.color:
        return Row(children: [
          Expanded(
              child: Text(p.name,
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textDim))),
          GestureDetector(
            onTap: () async {
              final cur = fx.strVal(p.id, '0x00ff00');
              final n = await colorField(context, cur);
              if (n != null) {
                s.edit('Set ${p.name}', () => fx.values[p.id] = n);
              }
            },
            child: Container(
              width: 40,
              height: 16,
              decoration: BoxDecoration(
                color: _parseColor(fx.strVal(p.id, '0x00ff00')),
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ]);
      case ParamType.file:
        return Row(children: [
          Expanded(
              child: Text(p.name,
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textDim))),
          Expanded(
            child: InkWell(
              onTap: () async {
                final r = await FilePicker.pickFiles(
                    type: FileType.custom, allowedExtensions: ['cube', '3dl']);
                final path = r.isEmpty ? null : r.single.path;
                if (path != null) {
                  s.edit('Set LUT', () => fx.values[p.id] = path);
                }
              },
              child: Text(
                  fx.strVal(p.id, '').isEmpty
                      ? 'choose…'
                      : fx.strVal(p.id, '').split('/').last,
                  style: const TextStyle(
                      fontSize: 10.5, color: AppTheme.accent),
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        ]);
      case ParamType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(
                child: Text(p.name,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textDim))),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 24,
                child: TextFormField(
                  initialValue: fx.strVal(p.id, ''),
                  style: const TextStyle(fontSize: 11),
                  decoration:
                      const InputDecoration(hintText: '0/0 0.5/0.6 1/1'),
                  onChanged: (v) {
                    fx.values[p.id] = v;
                    s.dirty = true;
                  },
                  onFieldSubmitted: (v) =>
                      s.edit('Set ${p.name}', () => fx.values[p.id] = v),
                ),
              ),
            ),
          ]),
        );
      case ParamType.number:
        return _numParam(clip, fx, p, hasKeys);
    }
  }

  Widget _numParam(Clip clip, ClipEffect fx, ParamDef p, bool hasKeys) {
    final s = widget.state;
    final localFrame =
        (s.playhead - clip.position).clamp(0, clip.duration);
    final cur = hasKeys
        ? fx.at(p.id, localFrame, s.fps, p.def)
        : fx.numVal(p.id, p.def);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        GestureDetector(
          onTap: () => _toggleKeyframe(clip, fx, p, localFrame),
          child: Icon(Icons.diamond,
              size: 11,
              color: hasKeys ? AppTheme.accent : AppTheme.textDim),
        ),
        const SizedBox(width: 4),
        SizedBox(
            width: 90,
            child: Text(p.name,
                style: const TextStyle(
                    fontSize: 10.5, color: AppTheme.textDim),
                overflow: TextOverflow.ellipsis)),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(trackHeight: 1.5),
            child: Slider(
              value: cur.clamp(p.min, p.max),
              min: p.min,
              max: p.max,
              onChangeStart: (_) => s.beginGesture('Set ${p.name}'),
              onChanged: (v) {
                if (hasKeys) {
                  _setKeyAt(clip, fx, p, localFrame, v);
                } else {
                  fx.values[p.id] = v;
                  s.dirty = true;
                  s.frameServer.invalidate();
                }
                s.notifyListeners();
              },
              onChangeEnd: (_) => s.endGesture(),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
              cur.toStringAsFixed(2) + p.unit,
              style: const TextStyle(fontSize: 10, color: AppTheme.text),
              textAlign: TextAlign.right),
        ),
      ]),
    );
  }

  void _toggleKeyframe(Clip clip, ClipEffect fx, ParamDef p, int frame) {
    final s = widget.state;
    s.edit('Toggle keyframe', () {
      final keys = fx.keyframes.putIfAbsent(p.id, () => []);
      final i = keys.indexWhere((k) => k.frame == frame);
      if (i >= 0) {
        keys.removeAt(i);
      } else {
        keys.add(Keyframe(frame, fx.at(p.id, frame, s.fps, p.def)));
        keys.sort((a, b) => a.frame.compareTo(b.frame));
      }
      if (keys.isEmpty) fx.keyframes.remove(p.id);
    });
  }

  void _setKeyAt(
      Clip clip, ClipEffect fx, ParamDef p, int frame, double value) {
    final s = widget.state;
    final keys = fx.keyframes.putIfAbsent(p.id, () => []);
    final i = keys.indexWhere((k) => k.frame == frame);
    if (i >= 0) {
      keys[i].value = value;
    } else {
      keys.add(Keyframe(frame, value));
      keys.sort((a, b) => a.frame.compareTo(b.frame));
    }
    s.dirty = true;
    s.frameServer.invalidate();
  }

  Color _parseColor(String s) {
    var v = s.replaceAll('#', '').replaceAll('0x', '');
    if (v.length == 6) v = 'ff$v';
    final n = int.tryParse(v, radix: 16) ?? 0xff00ff00;
    return Color(n);
  }
}
