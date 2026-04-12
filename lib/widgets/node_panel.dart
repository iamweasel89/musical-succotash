import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/node.dart';
import '../services/api_runner.dart';
import 'api_node_sheet.dart'; // for ApiNodeSettings + nodeApiSettings

const _providers = ['anthropic', 'openai', 'deepseek'];
const _models = {
  'anthropic': ['claude-sonnet-4-5'],
  'openai': ['gpt-4o'],
  'deepseek': ['deepseek-chat'],
};
const _maxTokenPresets = [256, 512, 1024, 2048, 4096];
const _tempPresets = [0.0, 0.3, 0.7, 1.0];

class NodePanel extends StatefulWidget {
  final Node node;
  final String effectiveText;
  final String inputText; // for token counter (api node)
  final List<Node> incomingNodes;
  final RunStats? lastRunStats;
  final void Function(Node) onChanged;
  final void Function(Node) onRun;
  final void Function() onClear;
  final void Function() onDeleteEdges;
  final void Function() onDelete;

  const NodePanel({
    super.key,
    required this.node,
    required this.effectiveText,
    required this.inputText,
    required this.incomingNodes,
    required this.onChanged,
    required this.onRun,
    required this.onClear,
    required this.onDeleteEdges,
    required this.onDelete,
    this.lastRunStats,
  });

  @override
  State<NodePanel> createState() => _NodePanelState();
}

class _NodePanelState extends State<NodePanel> {
  late final TextEditingController _nameCtrl;
  late Node _node;
  late ApiNodeSettings _api;

  @override
  void initState() {
    super.initState();
    _node = widget.node;
    _nameCtrl = TextEditingController(text: _node.name);
    _api = nodeApiSettings.putIfAbsent(_node.id, () => ApiNodeSettings());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _saveName() {
    _node = _node.copyWith(name: _nameCtrl.text);
    widget.onChanged(_node);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.effectiveText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isText = _node.type == NodeType.text;
    final double initSize = isText ? 0.45 : 0.70;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: initSize,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // ── Header row: name + actions ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // Node type dot
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isText
                          ? const Color(0xFF2196F3)
                          : const Color(0xFFF44336),
                      shape: BoxShape.circle,
                    ),
                  ),
                  // Editable name
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                        hintText: 'Name (optional)',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => _saveName(),
                    ),
                  ),
                  // Action icons
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    tooltip: 'Copy text',
                    onPressed: _copy,
                  ),
                  if (isText)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: 'Clear own text',
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onClear();
                      },
                    ),
                  if (!isText)
                    IconButton(
                      icon: Icon(
                        _node.status == NodeStatus.running
                            ? Icons.hourglass_top
                            : Icons.play_arrow,
                        size: 20,
                        color: _node.status == NodeStatus.running
                            ? Colors.grey
                            : Colors.green[700],
                      ),
                      tooltip: 'Run',
                      onPressed: _node.status == NodeStatus.running
                          ? null
                          : () {
                              Navigator.pop(context);
                              widget.onRun(_node);
                            },
                    ),
                  IconButton(
                    icon: const Icon(Icons.link_off, size: 20),
                    tooltip: 'Delete all edges',
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDeleteEdges();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.red),
                    tooltip: 'Delete node',
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── Scrollable body ───────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: isText
                    ? _textNodeBody(context)
                    : _apiNodeBody(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Text node body ────────────────────────────────────────────────────────
  List<Widget> _textNodeBody(BuildContext context) {
    final ownTok = (_node.text.length / 3).ceil();
    final totalTok = (widget.effectiveText.length / 3).ceil();

    return [
      // Token counter
      Text(
        'own: ~$ownTok tok  |  total: ~$totalTok tok',
        style: TextStyle(
            fontSize: 12, color: Colors.grey[600], fontFamily: 'monospace'),
      ),
      const SizedBox(height: 10),
      // Received slots
      if (widget.node.received.isNotEmpty) ...[
        ...widget.incomingNodes
            .where((n) => widget.node.received.containsKey(n.id))
            .map((n) => _ReceivedSlot(
                  sourceName: n.name.isEmpty ? '(unnamed)' : n.name,
                  sourceIsApi: n.type == NodeType.api,
                  text: widget.node.received[n.id]!,
                )),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 4),
        Text('Own text',
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
      ],
      // Own text — tappable to edit
      InkWell(
        onTap: () async {
          final result = await Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (_) => _FullScreenEditor(
                  initialText: _node.text, nodeName: _node.name),
            ),
          );
          if (result != null) {
            setState(() {
              _node = _node.copyWith(text: result);
            });
            widget.onChanged(_node);
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _node.text.isEmpty ? 'Tap to edit…' : _node.text,
            style: TextStyle(
                color: _node.text.isEmpty ? Colors.grey[400] : Colors.black87,
                fontSize: 14),
          ),
        ),
      ),
    ];
  }

  // ── API node body ─────────────────────────────────────────────────────────
  List<Widget> _apiNodeBody(BuildContext context) {
    final inputTok = (widget.inputText.length / 3).ceil();
    final stats = widget.lastRunStats;

    return [
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
      const Text('Temperature', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: _tempPresets
            .map((t) => ChoiceChip(
                  label: Text(t.toString()),
                  selected: _api.temperature == t,
                  onSelected: (_) => setState(() => _api.temperature = t),
                ))
            .toList(),
      ),
      const SizedBox(height: 12),
      // Input token count
      Text('Input: ~$inputTok tok',
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontFamily: 'monospace')),
      const SizedBox(height: 12),
      // Run button
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: Text(_node.status == NodeStatus.running ? 'Running…' : 'Run'),
          onPressed: _node.status == NodeStatus.running
              ? null
              : () {
                  Navigator.pop(context);
                  widget.onRun(_node);
                },
        ),
      ),
      // Last result
      if (_node.status == NodeStatus.done && _node.text.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Divider(),
        const Text('Last result',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (stats != null)
          Text(
            'in: ${stats.inputTokens} tok  out: ${stats.outputTokens} tok  ${stats.elapsed.inMilliseconds} ms',
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontFamily: 'monospace'),
          ),
        const SizedBox(height: 6),
        Text(_node.text,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13)),
      ],
    ];
  }
}

// ── Received slot tile ────────────────────────────────────────────────────────
class _ReceivedSlot extends StatelessWidget {
  final String sourceName;
  final bool sourceIsApi;
  final String text;

  const _ReceivedSlot({
    required this.sourceName,
    required this.sourceIsApi,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final preview = text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(4)
        .join('\n');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: sourceIsApi
                    ? const Color(0xFFF44336)
                    : const Color(0xFF2196F3),
                shape: BoxShape.circle,
              ),
            ),
            Text(sourceName,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(preview.isEmpty ? '(empty)' : preview,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Full-screen text editor ────────────────────────────────────────────────────
class _FullScreenEditor extends StatefulWidget {
  final String initialText;
  final String nodeName;
  const _FullScreenEditor({required this.initialText, required this.nodeName});

  @override
  State<_FullScreenEditor> createState() => _FullScreenEditorState();
}

class _FullScreenEditorState extends State<_FullScreenEditor> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nodeName.isEmpty ? 'Text Node' : widget.nodeName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: TextField(
          controller: _ctrl,
          maxLines: null,
          expands: true,
          autofocus: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.all(16),
            border: InputBorder.none,
            hintText: 'Enter text…',
          ),
          style: const TextStyle(fontSize: 15),
          keyboardType: TextInputType.multiline,
        ),
      ),
    );
  }
}
