import 'package:flutter/material.dart';

import '../theme.dart';

/// Simple title designer: a stack of text and rect items over a preview.
/// Items carry normalized coords (0..1). Output is a JSON map stored on the
/// asset and rendered by drawtext/drawbox in the graph.
class TitleEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const TitleEditorDialog({super.key, this.existing});

  @override
  State<TitleEditorDialog> createState() => _TitleEditorDialogState();
}

class _TitleEditorDialogState extends State<TitleEditorDialog> {
  late List<Map<String, dynamic>> items;
  int _sel = 0;
  final _name = TextEditingController(text: 'Title');

  @override
  void initState() {
    super.initState();
    items = ((widget.existing?['items'] as List?) ??
            [
              {'type': 'text', 'text': 'Title', 'x': 0.5, 'y': 0.85, 'size': 0.07, 'color': 'white'},
            ])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _name.text = widget.existing?['name'] as String? ?? 'Title';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 720,
        height: 460,
        child: Row(children: [
          // preview
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(10),
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CustomPaint(painter: _TitlePainter(items)),
              ),
            ),
          ),
          SizedBox(
            width: 250,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name')),
              ),
              Expanded(
                child: ListView(children: [
                  for (var i = 0; i < items.length; i++) _itemTile(i),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.add, size: 14),
                    title: const Text('Add text', style: TextStyle(fontSize: 12)),
                    onTap: () => setState(() => items.add({
                          'type': 'text',
                          'text': 'Text',
                          'x': 0.5,
                          'y': 0.5,
                          'size': 0.06,
                          'color': 'white',
                        })),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.crop_square, size: 14),
                    title:
                        const Text('Add bar', style: TextStyle(fontSize: 12)),
                    onTap: () => setState(() => items.add({
                          'type': 'rect',
                          'x': 0.1,
                          'y': 0.8,
                          'w': 0.8,
                          'h': 0.05,
                          'color': 'white',
                        })),
                  ),
                ]),
              ),
              if (_sel < items.length) _itemEditor(items[_sel]),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context,
                        {'name': _name.text, 'items': items}),
                    child: const Text('Save'),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _itemTile(int i) {
    final it = items[i];
    final sel = i == _sel;
    return ListTile(
      dense: true,
      selected: sel,
      title: Text(
          it['type'] == 'rect' ? 'Bar' : '${it['text'] ?? ''}',
          style: const TextStyle(fontSize: 11.5),
          overflow: TextOverflow.ellipsis),
      trailing: GestureDetector(
        onTap: () => setState(() {
          items.removeAt(i);
          _sel = _sel.clamp(0, items.length - 1);
        }),
        child: const Icon(Icons.close, size: 13),
      ),
      onTap: () => setState(() => _sel = i),
    );
  }

  Widget _itemEditor(Map<String, dynamic> it) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        if (it['type'] == 'text')
          TextFormField(
            initialValue: '${it['text'] ?? ''}',
            decoration: const InputDecoration(labelText: 'Text'),
            onChanged: (v) => setState(() => it['text'] = v),
          ),
        _sl('X', it, 'x'),
        _sl('Y', it, 'y'),
        if (it['type'] == 'text') _sl('Size', it, 'size', max: 0.4),
        if (it['type'] == 'rect') _sl('W', it, 'w'),
        if (it['type'] == 'rect') _sl('H', it, 'h', max: 0.5),
      ]),
    );
  }

  Widget _sl(String label, Map<String, dynamic> it, String k,
      {double max = 1}) {
    final v = (it[k] as num?)?.toDouble() ?? 0.5;
    return Row(children: [
      SizedBox(
          width: 34,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 10.5, color: AppTheme.textDim))),
      Expanded(
        child: Slider(
          value: v.clamp(0, max),
          max: max,
          onChanged: (x) => setState(() => it[k] = x),
        ),
      ),
    ]);
  }
}

class _TitlePainter extends CustomPainter {
  final List<Map<String, dynamic>> items;
  _TitlePainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xff202020));
    for (final it in items) {
      if (it['type'] == 'rect') {
        canvas.drawRect(
            Rect.fromLTWH(
                (it['x'] as num) * size.width,
                (it['y'] as num) * size.height,
                (it['w'] as num) * size.width,
                (it['h'] as num) * size.height),
            Paint()..color = _c('${it['color']}'));
      } else {
        final tp = TextPainter(
          text: TextSpan(
            text: '${it['text'] ?? ''}',
            style: TextStyle(
                fontSize: (it['size'] as num) * size.height,
                color: _c('${it['color']}'),
                fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width);
        tp.paint(
            canvas,
            Offset(
                (it['x'] as num) * size.width - tp.width / 2,
                (it['y'] as num) * size.height - tp.height / 2));
      }
    }
  }

  Color _c(String s) {
    if (s.startsWith('0x')) {
      return Color(int.parse(s.substring(2), radix: 16) | 0xff000000);
    }
    const map = {
      'white': Colors.white,
      'black': Colors.black,
      'red': Colors.red,
      'yellow': Colors.yellow,
      'green': Colors.green,
      'blue': Colors.blue,
    };
    return map[s] ?? Colors.white;
  }

  @override
  bool shouldRepaint(_TitlePainter o) => true;
}
