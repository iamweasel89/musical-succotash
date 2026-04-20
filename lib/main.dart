import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/debug_server.dart';
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
  DebugServer? _debug;
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
    if (await Settings.getDebugEnabled()) {
      await _startDebug();
    }
  }

  Future<void> _startDebug() async {
    _debug ??= DebugServer(_vault);
    try {
      await _debug!.start();
    } catch (_) {
      // Error stays in _debug.lastError, surfaced in Settings UI.
    }
    if (mounted) setState(() {});
  }

  Future<void> _stopDebug() async {
    await _debug?.stop();
    if (mounted) setState(() {});
  }

  Future<void> _restartDebug() async {
    await _stopDebug();
    await _startDebug();
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
            tooltip: 'Перечитать волт',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(
                  onDebugToggled: (enabled) async {
                    if (enabled) {
                      await _startDebug();
                    } else {
                      await _stopDebug();
                    }
                  },
                  onRestart: _restartDebug,
                  debugServer: _debug,
                ),
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
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: _atoms.isEmpty
                        ? ListView(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 200),
                              Center(child: Text('Волт пуст')),
                            ],
                          )
                        : ListView.separated(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
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
  final Future<void> Function(bool enabled)? onDebugToggled;
  final Future<void> Function()? onRestart;
  final DebugServer? debugServer;
  const SettingsScreen({
    super.key,
    this.onDebugToggled,
    this.onRestart,
    this.debugServer,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiCtl = TextEditingController();
  final _modelCtl = TextEditingController();
  final _maxCtl = TextEditingController();
  final _portCtl = TextEditingController();
  bool _obscure = true;
  bool _debugEnabled = false;
  String _debugToken = '';
  List<String> _ips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _apiCtl.text = await Settings.getApiKey();
    _modelCtl.text = await Settings.getModel();
    _maxCtl.text = (await Settings.getMaxTokens()).toString();
    _portCtl.text = (await Settings.getDebugPort()).toString();
    _debugEnabled = await Settings.getDebugEnabled();
    _debugToken = await Settings.getDebugToken();
    _ips = await _listIps();
    if (mounted) setState(() {});
  }

  Future<List<String>> _listIps() async {
    final out = <String>[];
    try {
      final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in ifs) {
        for (final a in i.addresses) {
          out.add('${i.name} ${a.address}');
        }
      }
    } catch (_) {}
    return out;
  }

  @override
  void dispose() {
    _apiCtl.dispose();
    _modelCtl.dispose();
    _maxCtl.dispose();
    _portCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await Settings.setApiKey(_apiCtl.text.trim());
    await Settings.setModel(_modelCtl.text.trim());
    final max = int.tryParse(_maxCtl.text.trim()) ?? Settings.defaultMaxTokens;
    await Settings.setMaxTokens(max);
    final port = int.tryParse(_portCtl.text.trim()) ??
        Settings.defaultDebugPort;
    await Settings.setDebugPort(port);
    await Settings.setDebugEnabled(_debugEnabled);
    await widget.onDebugToggled?.call(_debugEnabled);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
          const Divider(),
          const SizedBox(height: 8),
          Text('Debug HTTP-сервер',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Включён'),
            value: _debugEnabled,
            onChanged: (v) => setState(() => _debugEnabled = v),
          ),
          TextField(
            controller: _portCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Порт',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('X-Debug-Token'),
            subtitle: SelectableText(_debugToken),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Новый токен',
              onPressed: () async {
                final r = DateTime.now().microsecondsSinceEpoch;
                final t = 'tok_${r.toRadixString(36)}';
                await Settings.setDebugToken(t);
                setState(() => _debugToken = t);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text('Адреса устройства:',
              style: Theme.of(context).textTheme.bodySmall),
          for (final ip in _ips) SelectableText(ip),
          const SizedBox(height: 12),
          Text(
            widget.debugServer == null
                ? 'Сервер: не инициализирован'
                : widget.debugServer!.isRunning
                    ? 'Сервер: запущен на ${widget.debugServer!.boundUri}'
                    : 'Сервер: остановлен',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.debugServer?.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                'Ошибка старта: ${widget.debugServer!.lastError}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onRestart == null
                ? null
                : () async {
                    await widget.onRestart!();
                    if (mounted) setState(() {});
                  },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Перезапустить сервер'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Сохранить'),
          ),
        ],
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
