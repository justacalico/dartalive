import 'package:flutter/material.dart';

import '../../state/editor_state.dart';
import '../../theme.dart';

/// Undo/redo history list; click a label to jump back to that state.
class HistoryPanel extends StatelessWidget {
  final EditorState state;
  const HistoryPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final labels = state.undoLabels;
    if (labels.isEmpty) {
      return const Center(
          child: Text('No edits yet',
              style: TextStyle(color: AppTheme.textDim)));
    }
    return ListView.builder(
      itemCount: labels.length,
      itemBuilder: (_, i) {
        final last = i == labels.length - 1;
        return InkWell(
          onTap: () {
            // undo back to this step
            final n = labels.length - i - 1;
            for (var k = 0; k < n; k++) {
              state.undo();
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            color: last ? AppTheme.accent.withValues(alpha: 0.08) : null,
            child: Text(labels[i],
                style: TextStyle(
                    fontSize: 11,
                    color: last ? AppTheme.text : AppTheme.textDim)),
          ),
        );
      },
    );
  }
}
