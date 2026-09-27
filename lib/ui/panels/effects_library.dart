import 'package:flutter/material.dart';

import '../../models/effects.dart';
import '../../models/model.dart';
import '../../state/editor_state.dart';
import '../../theme.dart';

/// Effects library: categorized effect list; double-click applies to the
/// selected clip, or drag onto a timeline clip.
class EffectsLibraryPanel extends StatefulWidget {
  final EditorState state;
  const EffectsLibraryPanel({super.key, required this.state});

  @override
  State<EffectsLibraryPanel> createState() => _EffectsLibraryPanelState();
}

class _EffectsLibraryPanelState extends State<EffectsLibraryPanel> {
  String _filter = '';
  String _cat = '';

  @override
  Widget build(BuildContext context) {
    final cats = Effects.all.map((e) => e.category).toSet().toList();
    final defs = Effects.all.where((d) {
      if (_cat.isNotEmpty && d.category != _cat) return false;
      if (_filter.isNotEmpty &&
          !d.name.toLowerCase().contains(_filter.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    return Column(children: [
      Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          height: 22,
          child: TextField(
            style: const TextStyle(fontSize: 11.5),
            decoration: const InputDecoration(
                hintText: 'Search effects',
                prefixIcon: Icon(Icons.search, size: 13)),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
      ),
      SizedBox(
        height: 26,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          children: [
            _catChip('', 'All'),
            for (final c in cats) _catChip(c, _catName(c)),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: defs.length,
          itemBuilder: (_, i) => _row(defs[i]),
        ),
      ),
    ]);
  }

  String _catName(String c) => switch (c) {
        'transform' => 'Transform',
        'color' => 'Color',
        'blur' => 'Blur & Sharpen',
        'stylize' => 'Stylize',
        'keying' => 'Keying',
        'text' => 'Text',
        'audio' => 'Audio',
        _ => c,
      };

  Widget _catChip(String id, String name) {
    final on = _cat == id;
    return GestureDetector(
      onTap: () => setState(() => _cat = id),
      child: Container(
        margin: const EdgeInsets.only(right: 4, top: 3, bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8),
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

  Widget _row(EffectDef d) {
    final s = widget.state;
    return Draggable<String>(
      data: 'effect:${d.id}',
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: AppTheme.panelAlt,
              border: Border.all(color: AppTheme.accent),
              borderRadius: BorderRadius.circular(3)),
          child: Text(d.name, style: const TextStyle(fontSize: 11)),
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(d.audio ? Icons.graphic_eq : Icons.auto_fix_high,
            size: 13, color: AppTheme.textDim),
        title: Text(d.name, style: const TextStyle(fontSize: 11.5)),
        subtitle: Text(_catName(d.category),
            style: const TextStyle(fontSize: 9.5, color: AppTheme.textDim)),
        onTap: () {
          // double-click semantics: tap applies to selected clip
          final clip = s.selectedClipId != null
              ? s.clipById(s.selectedClipId!)
              : null;
          if (clip != null) {
            s.edit('Add effect', () {
              clip.effects.add(ClipEffect(
                  id: newId(), effectId: d.id, values: d.defaults()));
            });
            s.status('Added ${d.name}');
          }
        },
      ),
    );
  }
}
