import 'package:flutter/material.dart';

import '../models/app_model.dart';
import '../models/reminder.dart';
import '../services/reminder_service.dart';

// ── Мастерская: Напоминания (ВР4.3–4.4) ──────────────────────────────────────

class RemindersScreen extends StatefulWidget {
  final AppModel model;
  const RemindersScreen({super.key, required this.model});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Reminder> get _reminders {
    final list = List<Reminder>.from(widget.model.reminders);
    list.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return list;
  }

  Future<void> _create() async {
    final r = await showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateSheet(),
    );
    if (r == null) return;
    try {
      await ReminderService.schedule(r);
      setState(() => widget.model.reminders.add(r));
      widget.model.notifyRemindersChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка планирования: $e')),
      );
    }
  }

  Future<void> _delete(Reminder r) async {
    await ReminderService.cancel(r);
    setState(() => widget.model.reminders.removeWhere((x) => x.id == r.id));
    widget.model.notifyRemindersChanged();
  }

  @override
  Widget build(BuildContext context) {
    final items = _reminders;
    return Scaffold(
      appBar: AppBar(title: const Text('Напоминания')),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Напоминаний нет.\nКнопка «+» — создать.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              itemBuilder: (ctx, i) => _ReminderTile(
                reminder: items[i],
                onDelete: () => _delete(items[i]),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add_alarm),
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onDelete;

  const _ReminderTile({required this.reminder, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = reminder.scheduledAt.difference(now);
    String when;
    Color? color;
    if (reminder.done) {
      when = 'готово';
      color = Colors.grey;
    } else if (diff.isNegative) {
      when = 'прошло';
      color = Colors.grey;
    } else if (diff.inMinutes < 60) {
      when = 'через ${diff.inMinutes} мин';
      color = Colors.orange[700];
    } else if (diff.inHours < 24) {
      when = 'через ${diff.inHours} ч';
      color = Colors.blue[700];
    } else {
      when = 'через ${diff.inDays} дн';
      color = Colors.grey[700];
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ListTile(
        leading: Icon(Icons.alarm, color: color),
        title: Text(reminder.text),
        subtitle: Text(
          '$when · ${_fmtDate(reminder.scheduledAt)}',
          style: TextStyle(fontSize: 12, color: color),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: onDelete,
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

// ── Create sheet ─────────────────────────────────────────────────────────────

class _CreateSheet extends StatefulWidget {
  const _CreateSheet();

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  Duration _delta = const Duration(minutes: 15);
  DateTime? _customTime;

  static const _quick = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 24),
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  String _fmtDelta(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} мин';
    if (d.inHours < 24) return '${d.inHours} ч';
    return '${d.inDays} дн';
  }

  DateTime get _scheduledAt =>
      _customTime ?? DateTime.now().add(_delta);

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 15))),
    );
    if (time == null) return;
    setState(() {
      _customTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _submit() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    final when = _scheduledAt;
    if (when.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Время в прошлом'), duration: Duration(seconds: 1)),
      );
      return;
    }
    Navigator.pop(context, Reminder(scheduledAt: when, text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Новое напоминание',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'О чём напомнить',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Через:',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final d in _quick)
                  ChoiceChip(
                    label: Text(_fmtDelta(d)),
                    selected: _customTime == null && _delta == d,
                    onSelected: (_) => setState(() {
                      _customTime = null;
                      _delta = d;
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit_calendar, size: 16),
                  label: const Text('Выбрать…'),
                  onPressed: _pickCustom,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Сработает: ${_formatTime(_scheduledAt)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.alarm_add),
                  label: const Text('Создать'),
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
