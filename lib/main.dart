import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'services/updater.dart';

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
  Directory? _vaultDir;
  List<File> _atoms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppUpdater.addListener(_onUpdater);
    _bootstrap();
  }

  @override
  void dispose() {
    AppUpdater.removeListener(_onUpdater);
    super.dispose();
  }

  void _onUpdater() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final base = await getApplicationDocumentsDirectory();
    final vault = Directory('${base.path}/vault');
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    await _seedIfEmpty(vault);
    await _refresh(vault);
  }

  Future<void> _seedIfEmpty(Directory vault) async {
    final entries =
        await vault.list().where((e) => e.path.endsWith('.md')).toList();
    if (entries.isNotEmpty) return;
    final seed = await rootBundle.loadString('assets/seed/substrate.md');
    final f = File('${vault.path}/substrate.md');
    await f.writeAsString(seed);
  }

  Future<void> _refresh(Directory vault) async {
    final files = await vault
        .list()
        .where((e) => e is File && e.path.endsWith('.md'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    if (mounted) {
      setState(() {
        _vaultDir = vault;
        _atoms = files;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Substrate'),
        actions: [
          IconButton(
            tooltip: 'Проверить обновление',
            icon: const Icon(Icons.system_update),
            onPressed: () => _showUpdater(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _atoms.isEmpty
              ? const Center(child: Text('Волт пуст'))
              : ListView.separated(
                  itemCount: _atoms.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = _atoms[i];
                    final name = f.path.split('/').last;
                    return ListTile(
                      title: Text(name),
                      onTap: () => _openAtom(f),
                    );
                  },
                ),
      floatingActionButton: _vaultDir == null
          ? null
          : FloatingActionButton(
              onPressed: () async {
                if (_vaultDir != null) await _refresh(_vaultDir!);
              },
              tooltip: 'Перечитать волт',
              child: const Icon(Icons.refresh),
            ),
    );
  }

  Future<void> _openAtom(File f) async {
    final text = await f.readAsString();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
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
