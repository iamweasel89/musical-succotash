import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'services/debug_server.dart';
import 'services/llm_client.dart';
import 'services/settings.dart';
import 'services/updater.dart';
import 'services/vault.dart';
import 'widgets/atom_view.dart';
import 'widgets/context_picker_sheet.dart';
import 'widgets/quick_add_sheet.dart';

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

enum MoveSort { byTime, byDepth, byManualDepth }

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _vault = Vault();
  final _promptCtl = TextEditingController();
  final _searchCtl = TextEditingController();
  final Set<String> _ctx = {};
  DebugServer? _debug;
  late final TabController _tab;
  List<File> _atoms = [];
  List<File> _moves = [];
  final Map<String, String> _atomText = {};
  final Map<String, String> _moveText = {};
  final Map<String, int> _depth = {};
  final Map<String, int> _manualDepth = {};
  final Map<String, List<String>> _children = {};
  MoveSort _moveSort = MoveSort.byTime;
  String _search = '';
  bool _loading = true;
  bool _sending = false;
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    AppUpdater.addListener(_onUpdater);
    _bootstrap();
  }

  @override
  void dispose() {
    AppUpdater.removeListener(_onUpdater);
    _tab.dispose();
    _promptCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  List<File> _filter(List<File> list, Map<String, String> texts) {
    if (_search.isEmpty) return list;
    final q = _search.toLowerCase();
    return list.where((f) {
      if (f.path.toLowerCase().contains(q)) return true;
      final text = texts[f.path];
      return text != null && text.toLowerCase().contains(q);
    }).toList();
  }

  String _idOf(File f) => f.path.split('/').last.replaceAll('.md', '');

  List<File> get _visibleAtoms => _filter(_atoms, _atomText);

  List<File> get _visibleMoves {
    final filtered = _filter(_moves, _moveText);
    if (_moveSort == MoveSort.byTime) return filtered;
    final sorted = [...filtered];
    final map = _moveSort == MoveSort.byDepth ? _depth : _manualDepth;
    sorted.sort((a, b) {
      final da = map[_idOf(a)] ?? 0;
      final db = map[_idOf(b)] ?? 0;
      return db.compareTo(da);
    });
    return sorted;
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
    final atomFiles = await _vault.listAtoms();
    final moveFiles = await _vault.listMoves();
    final atomTexts = <String, String>{};
    for (final f in atomFiles) {
      try {
        atomTexts[f.path] = await f.readAsString();
      } catch (_) {}
    }
    final moveTexts = <String, String>{};
    for (final f in moveFiles) {
      try {
        moveTexts[f.path] = await f.readAsString();
      } catch (_) {}
    }
    final staged = await Settings.getStagedPrompt();
    if (mounted) {
      setState(() {
        _atoms = atomFiles;
        _moves = moveFiles;
        _atomText
          ..clear()
          ..addAll(atomTexts);
        _moveText
          ..clear()
          ..addAll(moveTexts);
        _computeMoveMetrics();
        _loading = false;
      });
      if (staged.isNotEmpty && _promptCtl.text.trim().isEmpty) {
        _promptCtl.text = staged;
        await Settings.clearStagedPrompt();
        if (mounted) setState(() {});
      }
    }
  }

  void _computeMoveMetrics() {
    _depth.clear();
    _manualDepth.clear();
    _children.clear();

    final parents = <String, List<String>>{};
    final gates = <String, String>{};
    for (final f in _moves) {
      final text = _moveText[f.path];
      if (text == null) continue;
      final id = f.path.split('/').last.replaceAll('.md', '');
      final parsed = parseFrontmatter(text);
      parents[id] = parseIdList(parsed.meta['parent_move_ids']);
      gates[id] = parsed.meta['gate'] ?? 'auto';
    }

    int depthOf(String id) {
      if (_depth.containsKey(id)) return _depth[id]!;
      final p = parents[id] ?? const <String>[];
      var d = 0;
      for (final parent in p) {
        if (parents.containsKey(parent)) {
          d = math.max(d, 1 + depthOf(parent));
        }
      }
      _depth[id] = d;
      return d;
    }

    int manualDepthOf(String id) {
      if (_manualDepth.containsKey(id)) return _manualDepth[id]!;
      if (gates[id] != 'manual') {
        _manualDepth[id] = 0;
        return 0;
      }
      final p = parents[id] ?? const <String>[];
      var d = 1;
      for (final parent in p) {
        if (parents.containsKey(parent) && gates[parent] == 'manual') {
          d = math.max(d, 1 + manualDepthOf(parent));
        }
      }
      _manualDepth[id] = d;
      return d;
    }

    for (final id in parents.keys) {
      depthOf(id);
      manualDepthOf(id);
    }

    parents.forEach((child, ps) {
      for (final p in ps) {
        (_children[p] ??= []).add(child);
      }
    });
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
      // Build context block from selected atoms.
      final ctxIds = <String>[];
      final ctxBlocks = <String>[];
      for (final p in _ctx) {
        try {
          final f = File(p);
          final text = await f.readAsString();
          final name = p.split('/').last.replaceAll(RegExp(r'\.md$'), '');
          ctxIds.add(name);
          ctxBlocks.add('=== АТОМ $name ===\n$text');
        } catch (_) {}
      }
      final enriched = ctxBlocks.isEmpty
          ? prompt
          : 'КОНТЕКСТ:\n\n${ctxBlocks.join('\n\n')}\n\n---\n\nЗАПРОС:\n$prompt';
      final llm = await LlmClient.call(
        apiKey: apiKey,
        model: model,
        maxTokens: maxTokens,
        prompt: enriched,
      );
      if (!mounted) return;
      final save = await _showPreview(prompt, llm);
      if (save == true) {
        final moveId = await _vault.reserveMoveId();
        final promptId = await _vault.writeAtom(
            type: 'prompt', body: prompt, sourceMoveId: moveId);
        final responseId = await _vault.writeAtom(
            type: 'response', body: llm.content, sourceMoveId: moveId);
        final parents = await _vault.parentMovesFor(ctxIds);
        await _vault.writeMoveRecord(
          moveId: moveId,
          model: llm.model,
          contextRefs: [promptId, ...ctxIds],
          resultRefs: [responseId],
          tokensIn: llm.tokensIn,
          tokensOut: llm.tokensOut,
          parentMoveIds: parents.toList(),
          gate: 'manual',
          prompt: prompt,
        );
        _promptCtl.clear();
        setState(() {
          _ctx.clear();
          _lastStatus =
              'Сохранён ход $moveId · in ${llm.tokensIn} / out ${llm.tokensOut}';
        });
        await _refresh();
      } else {
        setState(() {
          _lastStatus =
              'Отброшено (токены потрачены: in ${llm.tokensIn} / out ${llm.tokensOut})';
        });
      }
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

  Future<void> _pickContext() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ContextPickerSheet(
        atoms: _atoms,
        initialSelection: _ctx,
      ),
    );
    if (result == null) return;
    setState(() {
      _ctx
        ..clear()
        ..addAll(result);
    });
  }

  Future<void> _quickAdd() async {
    final result = await showModalBottomSheet<QuickAddResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const QuickAddSheet(),
    );
    if (result == null) return;
    final id = await _vault.writeAtom(type: result.type, body: result.body);
    setState(() {
      _lastStatus = 'Записано: $id';
    });
    await _refresh();
  }

  Future<bool?> _showPreview(String prompt, LlmResponse llm) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, sc) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ответ модели',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '${llm.model} · in ${llm.tokensIn} / out ${llm.tokensOut} токенов',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: sc,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(llm.content),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Отбросить'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Сохранить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: 'Атомы (${_atoms.length})'),
            Tab(text: 'Ходы (${_moves.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _searchCtl,
                    onChanged: (v) => setState(() => _search = v.trim()),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: 'Поиск по содержимому…',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchCtl.clear();
                                setState(() => _search = '');
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildList(
                        all: _atoms,
                        visible: _visibleAtoms,
                        emptyLabel: 'Атомов нет',
                        onTapFile: _openAtom,
                        withDepth: false,
                      ),
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Row(
                              children: [
                                Text('Сортировка:',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                                const SizedBox(width: 8),
                                DropdownButton<MoveSort>(
                                  value: _moveSort,
                                  isDense: true,
                                  items: const [
                                    DropdownMenuItem(
                                        value: MoveSort.byTime,
                                        child: Text('по времени')),
                                    DropdownMenuItem(
                                        value: MoveSort.byDepth,
                                        child: Text('по глубине ⛓')),
                                    DropdownMenuItem(
                                        value: MoveSort.byManualDepth,
                                        child:
                                            Text('по чистой глубине ✓')),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _moveSort = v);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _buildList(
                              all: _moves,
                              visible: _visibleMoves,
                              emptyLabel: 'Ходов нет',
                              onTapFile: _openMove,
                              withDepth: true,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_ctx.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 4, left: 8),
                              child: Text(
                                'Контекст: ${_ctx.length} атом(ов)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Быстрая запись (без LLM)',
                              icon: const Icon(Icons.note_add_outlined),
                              onPressed: _sending ? null : _quickAdd,
                            ),
                            IconButton(
                              tooltip: 'Контекст для следующего промта',
                              icon: Badge(
                                label: _ctx.isEmpty
                                    ? null
                                    : Text('${_ctx.length}'),
                                isLabelVisible: _ctx.isNotEmpty,
                                child: const Icon(Icons.attach_file),
                              ),
                              onPressed: _sending ? null : _pickContext,
                            ),
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildList({
    required List<File> all,
    required List<File> visible,
    required String emptyLabel,
    required Future<void> Function(File) onTapFile,
    bool withDepth = false,
  }) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Builder(builder: (_) {
        if (all.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 200),
              Center(child: Text(emptyLabel)),
            ],
          );
        }
        if (visible.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 120),
              Center(
                child: Text(
                  'Ничего не найдено по «$_search»',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final f = visible[i];
            final name = f.path.split('/').last;
            Widget? trailing;
            if (withDepth) {
              final id = _idOf(f);
              final d = _depth[id] ?? 0;
              final md = _manualDepth[id] ?? 0;
              trailing = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _depthChip('⛓ $d',
                      color: Theme.of(context).colorScheme.surfaceContainerHigh),
                  const SizedBox(width: 4),
                  _depthChip('✓ $md',
                      color: md == d
                          ? Colors.green.withOpacity(0.25)
                          : Colors.orange.withOpacity(0.20)),
                ],
              );
            }
            return ListTile(
              title: Text(name),
              trailing: trailing,
              onTap: () => onTapFile(f),
            );
          },
        );
      }),
    );
  }

  Widget _depthChip(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }

  Future<void> _openAtom(File f) async {
    final text = await f.readAsString();
    if (!mounted) return;
    final filename = f.path.split('/').last;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          child: AtomView(
            filename: filename,
            rawText: text,
            onOpenAtom: _openAtomById,
            onOpenMove: _openMoveById,
          ),
        ),
      ),
    );
  }

  Future<void> _openMove(File f) async {
    final text = await f.readAsString();
    if (!mounted) return;
    final filename = f.path.split('/').last;
    final id = _idOf(f);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          child: AtomView(
            filename: filename,
            rawText: text,
            depth: _depth[id],
            manualDepth: _manualDepth[id],
            childMoveIds: _children[id] ?? const [],
            onOpenAtom: _openAtomById,
            onOpenMove: _openMoveById,
          ),
        ),
      ),
    );
  }

  Future<void> _openAtomById(String id) async {
    final f = File('${_vault.root.path}/$id.md');
    if (await f.exists()) await _openAtom(f);
  }

  Future<void> _openMoveById(String id) async {
    final f = File('${_vault.moves.path}/$id.md');
    if (await f.exists()) await _openMove(f);
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
  String _packageBuild = '?';

  @override
  void initState() {
    super.initState();
    AppUpdater.addListener(_onTick);
    _loadPackage();
  }

  Future<void> _loadPackage() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _packageBuild = info.buildNumber);
    } catch (_) {}
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
    final latest = AppUpdater.updateInfo?.latestBuild;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Обновление', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInfoBox(
                  label: 'Текущий',
                  value: 'build-$_packageBuild',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInfoBox(
                  label: 'Доступен',
                  value: latest != null
                      ? 'build-$latest'
                      : (state == UpdState.upToDate
                          ? 'нет нового'
                          : '—'),
                  highlighted: latest != null &&
                      latest > (int.tryParse(_packageBuild) ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Статус: ${state.name}',
              style: Theme.of(context).textTheme.bodySmall),
          if (msg.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(msg, style: Theme.of(context).textTheme.bodySmall),
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

  Widget _buildInfoBox({
    required String label,
    required String value,
    bool highlighted = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
