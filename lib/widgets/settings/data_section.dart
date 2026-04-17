import 'package:flutter/material.dart';

// ── Секция «Данные» — экспорт / импорт / очистка всего ──────────────────────

class DataSection extends StatelessWidget {
  final VoidCallback? onExport;
  final VoidCallback? onImport;
  final VoidCallback? onClearAll;

  const DataSection({
    super.key,
    required this.onExport,
    required this.onImport,
    required this.onClearAll,
  });

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить всё?'),
        content: const Text(
            'Все ноды, рёбра и история чата будут удалены. Настройки и ключи сохранятся.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      onClearAll?.call();
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasIO = onExport != null || onImport != null;
    if (!hasIO && onClearAll == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasIO) ...[
          const Text('Данные', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (onExport != null)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: const Text('Экспорт'),
                    onPressed: onExport,
                  ),
                ),
              if (onExport != null && onImport != null)
                const SizedBox(width: 8),
              if (onImport != null)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Импорт'),
                    onPressed: onImport,
                  ),
                ),
            ],
          ),
        ],
        if (onClearAll != null) ...[
          const Divider(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('Очистить все данные',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red)),
              onPressed: () => _confirmClear(context),
            ),
          ),
        ],
      ],
    );
  }
}
