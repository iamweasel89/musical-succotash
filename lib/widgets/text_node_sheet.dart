import 'package:flutter/material.dart';
import '../models/node.dart';

class TextNodeSheet extends StatefulWidget {
  final Node node;
  final List<Node> incomingNodes;
  final String Function(Node) buildInput;
  final void Function(Node) onChanged;

  const TextNodeSheet({
    super.key,
    required this.node,
    required this.incomingNodes,
    required this.buildInput,
    required this.onChanged,
  });

  @override
  State<TextNodeSheet> createState() => _TextNodeSheetState();
}

class _TextNodeSheetState extends State<TextNodeSheet> {
  late final TextEditingController _nameCtrl;
  late Node _node;

  @override
  void initState() {
    super.initState();
    _node = widget.node;
    _nameCtrl = TextEditingController(text: _node.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save({String? name, String? text}) {
    _node = _node.copyWith(name: name ?? _node.name, text: text ?? _node.text);
    widget.onChanged(_node);
  }

  int _ownTokens() => (_node.text.length / 3).ceil();
  int _totalTokens() => (widget.buildInput(_node).length / 3).ceil();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Drag handle
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
            const Text('Text Node',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Name
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Name (optional)', border: OutlineInputBorder()),
              onChanged: (v) => _save(name: v),
            ),
            const SizedBox(height: 12),
            // Token counter
            Row(
              children: [
                Text(
                  'own: ~${_ownTokens()} tok  |  total: ~${_totalTokens()} tok',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: 'monospace'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Text field (tap opens full-screen editor)
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
                  setState(() => _save(text: result));
                }
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 80),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _node.text.isEmpty ? 'Tap to edit text…' : _node.text,
                  style: TextStyle(
                      color: _node.text.isEmpty ? Colors.grey : Colors.black),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Incoming slots (received content keyed by source node)
            if (widget.incomingNodes.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Received',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...widget.incomingNodes.map((n) => _IncomingTile(
                    node: n,
                    slotText: widget.node.received[n.id] ?? '',
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _IncomingTile extends StatelessWidget {
  final Node node;
  final String slotText; // what was actually pushed into this text node's slot

  const _IncomingTile({required this.node, required this.slotText});

  @override
  Widget build(BuildContext context) {
    final preview = slotText
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(3)
        .join('\n');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: node.type == NodeType.text
              ? const Color(0xFF2196F3)
              : const Color(0xFF7B1FA2),
        ),
        title: Text(node.name.isEmpty ? '(unnamed)' : node.name,
            style: const TextStyle(fontSize: 13)),
        subtitle: preview.isEmpty
            ? const Text('(no content pushed yet)',
                style: TextStyle(color: Colors.grey))
            : Text(preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

// ── Full-screen text editor ────────────────────────────────────────────────
class _FullScreenEditor extends StatefulWidget {
  final String initialText;
  final String nodeName;
  const _FullScreenEditor(
      {required this.initialText, required this.nodeName});

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
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
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
