import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/web_search_room.dart';

// Детальная страница одного поиска: три блока (запрос / протокол подготовки / ответ),
// у каждого — кнопка «копировать всё». Открывается по тапу на пузырь в ленте.
class WebSearchDetailScreen extends StatelessWidget {
  final WebSearchMessage? query;
  final WebSearchMessage? answer;

  /// Живые логи на момент открытия (когда сеанс ещё идёт и answer == null).
  final List<String>? liveLogs;
  final bool running;
  final int? elapsedSeconds;

  const WebSearchDetailScreen({
    super.key,
    required this.query,
    required this.answer,
    this.liveLogs,
    this.running = false,
    this.elapsedSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final finalLogs = answer != null && answer!.logs.isNotEmpty;
    final runningLogs =
        running && liveLogs != null && liveLogs!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск'),
        actions: [
          if (running && elapsedSeconds != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${elapsedSeconds}s',
                  style: TextStyle(
                    color: elapsedSeconds! > 60
                        ? Colors.orange[700]
                        : Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (query != null)
              _Section(
                title: 'Запрос',
                text: query!.text,
                icon: Icons.help_outline,
                timestamp: query!.createdAt,
              ),
            if (runningLogs)
              _Section(
                title: 'Протокол подготовки (идёт)',
                text: liveLogs!.join('\n'),
                icon: Icons.list_alt,
                mono: true,
              ),
            if (finalLogs)
              _Section(
                title: 'Протокол подготовки',
                text: answer!.logs.join('\n'),
                icon: Icons.list_alt,
                mono: true,
              ),
            if (answer != null)
              _Section(
                title: 'Ответ',
                text: answer!.text,
                icon: Icons.reply,
                timestamp: answer!.createdAt,
                status: answer!.status,
              ),
            if (running && answer == null && !runningLogs)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Агент работает, пока без сообщений в лог.\n'
                    'Это ненормально если больше минуты — возможно, зависший HTTP.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String text;
  final IconData icon;
  final bool mono;
  final DateTime? timestamp;
  final String? status;

  const _Section({
    required this.title,
    required this.text,
    required this.icon,
    this.mono = false,
    this.timestamp,
    this.status,
  });

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title — скопировано'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (status == 'limit') ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Агент упёрся в лимит итераций',
                    child: Icon(
                      Icons.warning_amber_outlined,
                      size: 14,
                      color: Colors.orange[700],
                    ),
                  ),
                ] else if (status == 'error') ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Ошибка',
                    child: Icon(
                      Icons.error_outline,
                      size: 14,
                      color: Colors.red[400],
                    ),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Копировать всё'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ],
            ),
            if (timestamp != null) ...[
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(
                  _fmt(timestamp!),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SelectableText(
              text.isEmpty ? '(пусто)' : text,
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
                color: text.isEmpty ? Colors.grey : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
