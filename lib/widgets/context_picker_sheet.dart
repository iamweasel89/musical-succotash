import 'dart:io';

import 'package:flutter/material.dart';

class ContextPickerSheet extends StatefulWidget {
  final List<File> atoms;
  final Set<String> initialSelection;
  const ContextPickerSheet({
    super.key,
    required this.atoms,
    required this.initialSelection,
  });

  @override
  State<ContextPickerSheet> createState() => _ContextPickerSheetState();
}

class _ContextPickerSheetState extends State<ContextPickerSheet> {
  late final Set<String> _sel;
  final _searchCtl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _sel = {...widget.initialSelection};
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  List<File> get _visible {
    if (_search.isEmpty) return widget.atoms;
    final q = _search.toLowerCase();
    return widget.atoms
        .where((f) => f.path.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, sc) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Выбрать контекст — ${_sel.length} атом(ов)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_sel.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _sel.clear()),
                    child: const Text('Снять всё'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtl,
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Поиск…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: _visible.length,
                itemBuilder: (_, i) {
                  final f = _visible[i];
                  final name = f.path.split('/').last;
                  final selected = _sel.contains(f.path);
                  return CheckboxListTile(
                    dense: true,
                    value: selected,
                    title: Text(name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _sel.add(f.path);
                        } else {
                          _sel.remove(f.path);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_sel),
                      child: Text('Применить (${_sel.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
