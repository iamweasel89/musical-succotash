import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/attachment.dart';
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
  late List<Attachment> _attachments;

  @override
  void initState() {
    super.initState();
    _node = widget.node;
    _nameCtrl = TextEditingController(text: _node.name);
    _attachments = List<Attachment>.from(_node.attachments);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save({String? name, String? text, List<Attachment>? attachments}) {
    _node = _node.copyWith(
      name: name ?? _node.name,
      text: text ?? _node.text,
      attachments: attachments ?? _attachments,
    );
    widget.onChanged(_node);
  }

  int _ownTokens() => (_node.text.length / 3).ceil();
  int _totalTokens() => (widget.buildInput(_node).length / 3).ceil();

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final added = <Attachment>[];
    for (final file in result.files) {
      if (file.bytes == null) continue;
      added.add(Attachment(
        filename: file.name,
        mimeType: _mimeFromExt(file.extension ?? ''),
        base64Data: base64Encode(file.bytes!),
      ));
    }
    if (added.isEmpty) return;

    setState(() {
      _attachments = [..._attachments, ...added];
      _save(attachments: _attachments);
    });
  }

  String _mimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  void _removeAttachment(Attachment a) {
    setState(() {
      _attachments = _attachments.where((x) => !identical(x, a)).toList();
      _save(attachments: _attachments);
    });
  }

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
            const SizedBox(height: 10),
            // Attachment bar
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: const Text('Фото'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: _pickImages,
                ),
              ],
            ),
            // Attachment chips
            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _attachments
                    .map((a) => Chip(
                          avatar: Icon(
                            a.isImage
                                ? Icons.image_outlined
                                : Icons.attach_file,
                            size: 14,
                          ),
                          label: Text(
                            a.filename,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => _removeAttachment(a),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
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
