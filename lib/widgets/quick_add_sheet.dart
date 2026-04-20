import 'package:flutter/material.dart';

class QuickAddResult {
  final String type;
  final String body;
  const QuickAddResult({required this.type, required this.body});
}

class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key});

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  static const _types = <String>[
    'note',
    'thesis',
    'excerpt',
    'observation',
    'idea',
    'question',
  ];
  String _type = 'note';
  final _bodyCtl = TextEditingController();

  @override
  void dispose() {
    _bodyCtl.dispose();
    super.dispose();
  }

  void _save() {
    final body = _bodyCtl.text.trim();
    if (body.isEmpty) return;
    Navigator.of(context).pop(QuickAddResult(type: _type, body: body));
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Быстрая запись',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final t in _types)
                    ChoiceChip(
                      label: Text(t),
                      selected: _type == t,
                      onSelected: (v) {
                        if (v) setState(() => _type = t);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtl,
                autofocus: true,
                maxLines: 8,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Запиши мысль…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
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
                      onPressed: _save,
                      child: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
