import 'package:flutter/material.dart';

import '../../models/app_model.dart';

// Bottom-sheet с историей undo-записей. Открывается из тулбара чата.
// Показывает стек описаний последних действий; кнопка «Отменить шаг»
// делает model.undo() и закрывает sheet.
class HistorySheet extends StatelessWidget {
  final AppModel model;
  const HistorySheet({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final stack = model.undoStack.reversed.toList();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text('История изменений',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
          if (stack.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Нет записей', style: TextStyle(color: Colors.grey)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stack.length,
                itemBuilder: (_, i) => ListTile(
                  leading: Icon(Icons.history,
                      size: 18, color: Colors.grey[500]),
                  title: Text(
                      stack[i].description.isEmpty ? '—' : stack[i].description,
                      style: const TextStyle(fontSize: 14)),
                  dense: true,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (model.canUndo)
                  TextButton.icon(
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Отменить шаг'),
                    onPressed: () {
                      Navigator.pop(context);
                      model.undo();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
