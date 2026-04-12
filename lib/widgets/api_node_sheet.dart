import 'package:flutter/material.dart';
import '../models/node.dart';
import '../models/settings.dart';
import '../services/api_runner.dart';

const _providers = ['anthropic', 'openai', 'deepseek'];
const _models = {
  'anthropic': ['claude-sonnet-4-5'],
  'openai': ['gpt-4o'],
  'deepseek': ['deepseek-chat'],
};
const _maxTokenPresets = [256, 512, 1024, 2048, 4096];
const _tempPresets = [0.0, 0.3, 0.7, 1.0];

class ApiNodeSettings {
  String provider;
  String model;
  int maxTokens;
  double temperature;

  ApiNodeSettings({
    this.provider = 'deepseek',
    this.model = 'deepseek-chat',
    this.maxTokens = 1024,
    this.temperature = 0.7,
  });
}

// Store per-node settings alongside the node (keyed by node id)
final nodeApiSettings = <String, ApiNodeSettings>{};

ApiNodeSettings _settingsFor(Node node) =>
    nodeApiSettings.putIfAbsent(node.id, () => ApiNodeSettings());

class ApiNodeSheet extends StatefulWidget {
  final Node node;
  final GlobalSettings settings;
  final String Function(Node) buildInput;
  final void Function(Node) onChanged;
  final void Function(Node) onRun;
  final RunStats? lastRunStats;

  const ApiNodeSheet({
    super.key,
    required this.node,
    required this.settings,
    required this.buildInput,
    required this.onChanged,
    required this.onRun,
    this.lastRunStats,
  });

  @override
  State<ApiNodeSheet> createState() => _ApiNodeSheetState();
}

class _ApiNodeSheetState extends State<ApiNodeSheet> {
  late final TextEditingController _nameCtrl;
  late Node _node;
  late ApiNodeSettings _api;

  @override
  void initState() {
    super.initState();
    _node = widget.node;
    _api = _settingsFor(_node);
    _nameCtrl = TextEditingController(text: _node.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    _node = _node.copyWith(name: _nameCtrl.text);
    widget.onChanged(_node);
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.buildInput(_node);
    final inputTokens = (input.length / 3).ceil();
    final resultTokens = (_node.text.length / 3).ceil();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('API Node',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Name
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Name (optional)', border: OutlineInputBorder()),
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: 16),
            // Provider
            const Text('Provider', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: _providers
                  .map((p) => ButtonSegment(value: p, label: Text(p)))
                  .toList(),
              selected: {_api.provider},
              onSelectionChanged: (s) => setState(() {
                _api.provider = s.first;
                _api.model = _models[_api.provider]!.first;
              }),
            ),
            const SizedBox(height: 12),
            // Model
            const Text('Model', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _api.model,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: (_models[_api.provider] ?? [])
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _api.model = v!),
            ),
            const SizedBox(height: 12),
            // Max tokens
            const Text('Max output tokens',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _maxTokenPresets
                  .map((t) => ChoiceChip(
                        label: Text('$t'),
                        selected: _api.maxTokens == t,
                        onSelected: (_) => setState(() => _api.maxTokens = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            // Temperature
            const Text('Temperature',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _tempPresets
                  .map((t) => ChoiceChip(
                        label: Text(t.toString()),
                        selected: _api.temperature == t,
                        onSelected: (_) =>
                            setState(() => _api.temperature = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            // Input preview
            Text(
              'Input: ~$inputTokens tok',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            // Run button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(_node.status == NodeStatus.running
                    ? 'Running…'
                    : 'Run'),
                onPressed: _node.status == NodeStatus.running
                    ? null
                    : () {
                        widget.onRun(_node);
                        Navigator.pop(context);
                      },
              ),
            ),
            // Last run stats
            if (_node.status == NodeStatus.done && _node.text.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const Text('Last result',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (widget.lastRunStats != null)
                Text(
                  'in: ${widget.lastRunStats!.inputTokens} tok  '
                  'out: ${widget.lastRunStats!.outputTokens} tok  '
                  '${widget.lastRunStats!.elapsed.inMilliseconds} ms',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: 'monospace'),
                )
              else
                Text(
                  'Output: ~$resultTokens tok',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: 'monospace'),
                ),
              const SizedBox(height: 6),
              Text(
                _node.text,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
