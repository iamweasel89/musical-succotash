import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/settings.dart';
import 'services/updater.dart';
import 'services/vault.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SubstrateApp());
}

class SubstrateApp extends StatelessWidget {
  const SubstrateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Substrate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A2E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _vault = Vault();
  final _promptCtl = TextEditingController();
  List<File> _atoms = [];
  bool _loading = true;
  bool _sending = false;
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    AppUpdater.addListener(_onUpdater);
    _bootstrap();
  }

  @override
  void dispose() {
    AppUpdater.removeListener(_onUpdater);
    _promptCtl.dispose();
    super.dispose();
  }

  void _onUpdater() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await _vault.init();
    await _seedIfEmpty();
    await _refresh();
  }

  Future<void> _seedIfEmpty() async {
    final existing = await _vault.listAtoms();
    if (existing.isNotEmpty) return;
    final seed = await rootBundle.loadString('assets/seed/substrate.md');
    final f = File('${_vault.root.path}/substrate.md');
    await f.writeAsString(seed);
  }

  Future<void> _refresh() async {
    final files = await _vault.listAtoms();
    if (mounted) {
      setState(() {
        _atoms = files;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final prompt = _promptCtl.text.trim();
    if (prompt.isEmpty || _sending) return;
    final apiKey = await Settings.getApiKey();
    if (apiKey.isEmpty) {
      _showSnack('API-ключ не задан. Настройки → Anthropic API key.');
      return;
    }
    setState(() {
      _sending = true;
      _lastStatus = 'Отправка…';
    });
    try {
      final model = await Settings.getModel();
      final maxTokens = await Settings.getMaxTokens();
      final result = await _vault.runMove(
        apiKey: apiKey,
        model: model,
        maxTokens: maxTokens,
        prompt: prompt,
      );
      _promptCtl.clear();
      setState(() {
        _lastStatus =
            'Ход ${result.moveId} · in ${result.tokensIn} / out ${result.tokensOut}';
      });
      await _refresh();
    } catch (e) {
      setState(() {
        _lastStatus = 'Ошибка: $e';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Substrate'),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Проверить обновление',
            icon: const Icon(Icons.system_update),
            onPressed: () => _showUpdater(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _atoms.isEmpty
                      ? const Center(child: Text('Волт пуст'))
                      : ListView.separated(
                          itemCount: _atoms.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final f = _atoms[i];
                            final name = f.path.split('/').last;
                            return ListTile(
                              title: Text(name),
                              onTap: () => _openAtom(f),
                            );
                          },
                        ),
                ),
                if (_lastStatus != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Text(
                      _lastStatus!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _promptCtl,
                            enabled: !_sending,
                            maxLines: 4,
                            minLines: 1,
                            decoration: const InputDecoration(
                              hintText: 'Промт…',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Отправить',
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                          onPressed: _sending ? null : _send,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _openAtom(File f) async {
    final text = await f.readAsString();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(16),
          child: SelectableText(text),
        ),
      ),
    );
  }

  void _showUpdater(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const UpdaterSheet(),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiCtl = TextEditingController();
  final _modelCtl = TextEditingController();
  final _maxCtl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _apiCtl.text = await Settings.getApiKey();
    _modelCtl.text = await Settings.getModel();
    _maxCtl.text = (await Settings.getMaxTokens()).toString();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _apiCtl.dispose();
    _modelCtl.dispose();
    _maxCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await Settings.setApiKey(_apiCtl.text.trim());
    await Settings.setModel(_modelCtl.text.trim());
    final max = int.tryParse(_maxCtl.text.trim()) ?? Settings.defaultMaxTokens;
    await Settings.setMaxTokens(max);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _apiCtl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Anthropic API key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelCtl,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _maxCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max tokens',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class UpdaterSheet extends StatefulWidget {
  const UpdaterSheet({super.key});

  @override
  State<UpdaterSheet> createState() => _UpdaterSheetState();
}

class _UpdaterSheetState extends State<UpdaterSheet> {
  @override
  void initState() {
    super.initState();
    AppUpdater.addListener(_onTick);
  }

  @override
  void dispose() {
    AppUpdater.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = AppUpdater.state;
    final msg = AppUpdater.message;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Обновление', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Статус: ${state.name}'),
          if (msg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(msg),
          ],
          if (state == UpdState.downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: AppUpdater.progress),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: state == UpdState.checking ||
                        state == UpdState.downloading
                    ? null
                    : AppUpdater.check,
                child: const Text('Проверить'),
              ),
              if (state == UpdState.available)
                FilledButton.tonal(
                  onPressed: AppUpdater.download,
                  child: const Text('Скачать'),
                ),
              if (state == UpdState.ready)
                FilledButton.tonal(
                  onPressed: AppUpdater.install,
                  child: const Text('Установить'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
