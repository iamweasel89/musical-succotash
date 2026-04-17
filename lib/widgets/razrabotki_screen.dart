import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

// ── Мастерская: Разработки ───────────────────────────────────────────────────
// Viewer PASSPORT.md из репозитория (raw GitHub). Единственный источник истины —
// файл в репо; правки делаются через git. LLM-чат в разделе — отдельный шаг.

const _passportRawUrl =
    'https://raw.githubusercontent.com/iamweasel89/musical-succotash/'
    'claude/hex-canvas-mobile-08MeM/PASSPORT.md';

class RazrabotkiScreen extends StatefulWidget {
  const RazrabotkiScreen({super.key});

  @override
  State<RazrabotkiScreen> createState() => _RazrabotkiScreenState();
}

class _RazrabotkiScreenState extends State<RazrabotkiScreen> {
  String? _content;
  String? _error;
  bool _loading = false;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await http
          .get(Uri.parse(_passportRawUrl))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        throw Exception('HTTP ${r.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _content = r.body;
        _loading = false;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Разработки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading && _content == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _content == null
              ? _ErrorView(error: _error!, onRetry: _load)
              : Column(
                  children: [
                    if (_loadedAt != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              'Обновлено: ${_fmtTime(_loadedAt!)}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Markdown(
                        data: _content ?? '',
                        padding: const EdgeInsets.all(16),
                        selectable: true,
                      ),
                    ),
                  ],
                ),
    );
  }

  String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text('Не удалось загрузить PASSPORT.md:\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}
