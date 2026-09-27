import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Dockable panel framework.
///
/// Layout model: four dock areas (left, right, bottom, center). Left and
/// right areas hold a vertical stack of tab groups; the bottom area holds a
/// single tab group spanning the width; center is a single tab group.
/// Panel headers are drag handles; drop targets on each area let a panel
/// become a new group (split top/bottom) or join an existing group as a tab.
/// Splitters between areas and groups are drag-resizable. The whole layout
/// serializes to JSON for saved layouts.

class PanelDef {
  final String id;
  final String title;
  final IconData icon;
  final Widget Function() builder;
  const PanelDef(this.id, this.title, this.icon, this.builder);
}

class PanelGroup {
  List<String> panels;
  int active;
  double flex; // relative size inside its area
  PanelGroup(this.panels, {this.active = 0, this.flex = 1});
  factory PanelGroup.fromJson(Map<String, dynamic> j) => PanelGroup(
        (j['p'] as List).map((e) => '$e').toList(),
        active: j['a'] as int? ?? 0,
        flex: (j['f'] as num?)?.toDouble() ?? 1,
      );
  Map<String, dynamic> toJson() =>
      {'p': panels, 'a': active, 'f': flex};
}

class DockLayout {
  DockLayout();
  // areaId -> stack of groups
  Map<String, List<PanelGroup>> areas = {
    'left': [],
    'right': [],
    'bottom': [],
    'center': [],
  };
  // area sizes (fractions of window)
  double leftW = 0.18, rightW = 0.20, bottomH = 0.42;

  static DockLayout defaults() {
    final d = DockLayout();
    d.areas['left'] = [PanelGroup(['bin', 'effects'])];
    d.areas['center'] = [
      PanelGroup(['source', 'program', 'scopes'])
    ];
    d.areas['right'] = [
      PanelGroup(['effectstack']),
      PanelGroup(['mixer', 'history'])
    ];
    d.areas['bottom'] = [PanelGroup(['timeline'])];
    d.areas['center']!.first.flex = 1;
    return d;
  }

  factory DockLayout.fromJson(Map<String, dynamic> j) {
    final d = DockLayout();
    d.leftW = (j['lw'] as num?)?.toDouble() ?? 0.18;
    d.rightW = (j['rw'] as num?)?.toDouble() ?? 0.20;
    d.bottomH = (j['bh'] as num?)?.toDouble() ?? 0.42;
    (j['areas'] as Map?)?.forEach((k, v) {
      d.areas[k] = (v as List)
          .map((e) => PanelGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    });
    return d;
  }

  Map<String, dynamic> toJson() => {
        'lw': leftW,
        'rw': rightW,
        'bh': bottomH,
        'areas': areas.map(
            (k, v) => MapEntry(k, v.map((g) => g.toJson()).toList())),
      };

  String encode() => jsonEncode(toJson());
  static DockLayout? decode(String s) {
    try {
      return DockLayout.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// All panels currently placed.
  Set<String> placed() =>
      areas.values.expand((g) => g.expand((x) => x.panels)).toSet();

  void removePanel(String id) {
    for (final a in areas.values) {
      for (final g in a) {
        g.panels.remove(id);
      }
      for (final g in a) {
        if (g.panels.isNotEmpty) {
          g.active = g.active.clamp(0, g.panels.length - 1);
        }
      }
      a.removeWhere((g) => g.panels.isEmpty);
    }
  }

  /// Dock [id] into [area]; [index] = group index to tab into, or -1/-2 to
  /// split a new group above/below [index].
  void dock(String id, String area, int index, {bool below = false}) {
    removePanel(id);
    final list = areas[area]!;
    if (index >= 0 && index < list.length) {
      list[index].panels.add(id);
      list[index].active = list[index].panels.length - 1;
    } else {
      final g = PanelGroup([id]);
      if (index == -2 && below) {
        list.add(g);
      } else {
        list.insert(0, g);
      }
    }
  }
}

class DockAreaView extends StatefulWidget {
  final DockLayout layout;
  final Map<String, PanelDef> registry;
  final VoidCallback onChanged;
  const DockAreaView(
      {super.key,
      required this.layout,
      required this.registry,
      required this.onChanged});

  @override
  State<DockAreaView> createState() => _DockAreaViewState();
}

class _DockAreaViewState extends State<DockAreaView> {
  String? _dragPanel;
  _DropTarget? _hover;

  void _change() {
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.layout;
    return LayoutBuilder(builder: (context, cons) {
      final totalW = cons.maxWidth;
      final totalH = cons.maxHeight;
      return Row(children: [
        if (l.areas['left']!.isNotEmpty) ...[
          SizedBox(width: totalW * l.leftW, child: _areaColumn('left')),
          _splitter((d) => setState(
              () => l.leftW = (l.leftW + d / totalW).clamp(0.08, 0.4))),
        ],
        Expanded(
          child: Column(children: [
            Expanded(
              child: Row(children: [
                Expanded(child: _centerArea()),
                if (l.areas['right']!.isNotEmpty) ...[
                  _splitter((d) => setState(() => l.rightW =
                      (l.rightW - d / totalW).clamp(0.08, 0.4))),
                  SizedBox(
                      width: totalW * l.rightW, child: _areaColumn('right')),
                ],
              ]),
            ),
            if (l.areas['bottom']!.isNotEmpty) ...[
              _splitterV((d) => setState(() => l.bottomH =
                  (l.bottomH - d / totalH).clamp(0.15, 0.8))),
              SizedBox(height: totalH * l.bottomH, child: _bottomArea()),
            ],
          ]),
        ),
      ]);
    });
  }

  Widget _centerArea() {
    final groups = widget.layout.areas['center']!;
    if (groups.isEmpty) {
      return _dropZone('center', -1,
          child: Container(color: AppTheme.panel));
    }
    return Column(children: [
      for (var i = 0; i < groups.length; i++)
        Expanded(
            flex: (groups[i].flex * 100).round(),
            child: _groupWithDrops('center', groups[i], i)),
    ]);
  }

  Widget _bottomArea() {
    final groups = widget.layout.areas['bottom']!;
    if (groups.isEmpty) {
      return _dropZone('bottom', -1, child: Container(color: AppTheme.panel));
    }
    return Row(children: [
      for (var i = 0; i < groups.length; i++)
        Expanded(
            flex: (groups[i].flex * 100).round(),
            child: _groupWithDrops('bottom', groups[i], i)),
    ]);
  }

  Widget _areaColumn(String area) {
    final groups = widget.layout.areas[area]!;
    return Column(children: [
      for (var i = 0; i < groups.length; i++) ...[
        if (i > 0)
          _splitterV((d) {
            setState(() {
              final total = groups.fold(0.0, (s, g) => s + g.flex);
              final delta = d / context.size!.height * total;
              groups[i - 1].flex =
                  (groups[i - 1].flex + delta).clamp(0.15, 8.0);
              groups[i].flex = (groups[i].flex - delta).clamp(0.15, 8.0);
            });
          }),
        Expanded(flex: (groups[i].flex * 100).round(), child: _groupWithDrops(area, groups[i], i)),
      ],
      _dropZone(area, -1,
          child: const SizedBox(height: 28, width: double.infinity)),
    ]);
  }

  Widget _groupWithDrops(String area, PanelGroup g, int i) {
    return Column(children: [
      _dropZone(area, -3 - i, child: const SizedBox(height: 3)), // split above
      Expanded(child: _tabGroup(area, g, i)),
      _dropZone(area, -100 - i, child: const SizedBox(height: 3)), // below
    ]);
  }

  Widget _splitter(void Function(double) onDrag) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(width: 4, color: AppTheme.border),
      ),
    );
  }

  Widget _splitterV(void Function(double) onDrag) {
    return GestureDetector(
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(height: 4, color: AppTheme.border),
      ),
    );
  }

  Widget _tabGroup(String area, PanelGroup g, int gi) {
    return Container(
      color: AppTheme.panel,
      child: Column(children: [
        _tabBar(area, g, gi),
        Expanded(
          child: g.panels.isEmpty
              ? const SizedBox()
              : _panelBody(g.panels[g.active.clamp(0, g.panels.length - 1)]),
        ),
      ]),
    );
  }

  Widget _tabBar(String area, PanelGroup g, int gi) {
    return Container(
      height: 26,
      color: AppTheme.header,
      child: Row(children: [
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < g.panels.length; i++)
                _tab(area, g, gi, i),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _tab(String area, PanelGroup g, int gi, int i) {
    final id = g.panels[i];
    final def = widget.registry[id];
    final active = i == g.active;
    return Draggable<String>(
      data: id,
      onDragStarted: () => setState(() => _dragPanel = id),
      onDragEnd: (_) => setState(() {
        _dragPanel = null;
        _hover = null;
      }),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.panelAlt,
            border: Border.all(color: AppTheme.accent),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(def?.title ?? id,
              style: const TextStyle(fontSize: 11, color: AppTheme.text)),
        ),
      ),
      childWhenDragging: const SizedBox(width: 4),
      child: GestureDetector(
        onTap: () => setState(() => g.active = i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? AppTheme.panel : Colors.transparent,
            border: Border(
              top: BorderSide(
                  color: active ? AppTheme.accent : Colors.transparent,
                  width: 2),
            ),
          ),
          child: Row(children: [
            if (def != null) ...[
              Icon(def.icon, size: 12, color: active ? AppTheme.accent : AppTheme.textDim),
              const SizedBox(width: 5),
            ],
            Text(def?.title ?? id,
                style: TextStyle(
                    fontSize: 11,
                    color: active ? AppTheme.text : AppTheme.textDim)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                widget.layout.removePanel(id);
                _change();
              },
              child: const Icon(Icons.close, size: 11, color: AppTheme.textDim),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _panelBody(String id) {
    final def = widget.registry[id];
    if (def == null) {
      return Center(
          child: Text('missing panel: $id',
              style: const TextStyle(color: AppTheme.textDim)));
    }
    return _dropZone('__inside__$id', -1, child: def.builder(), passive: true);
  }

  Widget _dropZone(String area, int index,
      {required Widget child, bool passive = false}) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        if (!widget.registry.containsKey(d.data)) return false;
        setState(() => _hover = _DropTarget(area, index));
        return true;
      },
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) {
        final panel = d.data;
        setState(() {
          _hover = null;
          _dragPanel = null;
        });
        if (area.startsWith('__inside__')) {
          // tab into the group containing this panel
          _dockIntoGroup(panel, area.substring(10));
        } else if (index >= 0) {
          widget.layout.dock(panel, area, index);
        } else if (index <= -100) {
          // split below group gi
          final gi = -100 - index;
          widget.layout.removePanel(panel);
          final list = widget.layout.areas[area]!;
          list.insert((gi + 1).clamp(0, list.length).toInt(), PanelGroup([panel]));
        } else if (index <= -3) {
          // split above group gi
          final gi = -3 - index;
          widget.layout.removePanel(panel);
          final list = widget.layout.areas[area]!;
          list.insert(gi.clamp(0, list.length).toInt(), PanelGroup([panel]));
        } else {
          widget.layout.dock(panel, area, -1);
        }
        _change();
      },
      builder: (context, cand, rej) {
        final hl = _hover != null &&
            _hover!.area == area &&
            _hover!.index == index &&
            _dragPanel != null;
        return Stack(fit: StackFit.passthrough, children: [
          child,
          if (hl)
            Positioned.fill(
                child: IgnorePointer(
                    child: Container(
                        color: AppTheme.accent.withValues(alpha: 0.18)))),
        ]);
      },
    );
  }

  void _dockIntoGroup(String panel, String hostPanelId) {
    for (final e in widget.layout.areas.entries) {
      for (var gi = 0; gi < e.value.length; gi++) {
        if (e.value[gi].panels.contains(hostPanelId)) {
          widget.layout.dock(panel, e.key, gi);
          return;
        }
      }
    }
    widget.layout.dock(panel, 'center', 0);
  }
}

class _DropTarget {
  final String area;
  final int index;
  _DropTarget(this.area, this.index);
}
