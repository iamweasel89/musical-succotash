import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/settings.dart';
import '../services/llm_transform.dart';

// ── Compress sheet — переиспользуемая шторка сжатия текста ──────────────────
// Принимает произвольный текст + settings. Позволяет выбрать N строк (чипами),
// вызвать compress(), показать результат с копированием.

class CompressSheet extends StatefulWidget {
  final String text;
  final GlobalSettings settings;

  /// Необязательный колбэк — если задан, в результате появляется кнопка
  /// «Применить» которая вызывает onApply(result).
  final void Function(String result)? onApply;

  const CompressSheet({
    super.key,
    required this.text,
    required this.settings,
    this.onApply,
  });

  @override
  State<CompressSheet> createState() => _CompressSheetState();
}

class _CompressSheetState extends State<CompressSheet> {
  int _n = 3;
  bool _busy = false;
  String? _result;
  String? _error;

  static const _options = [1, 3, 5, 10];

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await compress(
        text: widget.text,
        n: _n,
        settings: widget.settings,
      );
      if (!mounted) return;
      setState(() {
        _result = out;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Сжать текст',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('До скольких строк:',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _options
                  .map((n) => ChoiceChip(
                        label: Text('$n'),
                        selected: _n == n,
                        onSelected:
                            _busy ? null : (_) => setState(() => _n = n),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.compress, size: 18),
                  label: Text(_busy ? 'Сжимаю…' : 'Сжать'),
                  onPressed: _busy ? null : _run,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text('Ошибка: $_error',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              const Text('Результат:',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_result!,
                    style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Скопировать'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _result!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Результат скопирован'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  if (widget.onApply != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Применить'),
                      onPressed: () {
                        widget.onApply!(_result!);
                        Navigator.of(context).maybePop();
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Helper — открыть шторку откуда угодно ────────────────────────────────────
Future<void> openCompressSheet(
  BuildContext context, {
  required String text,
  required GlobalSettings settings,
  void Function(String result)? onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CompressSheet(
      text: text,
      settings: settings,
      onApply: onApply,
    ),
  );
}
