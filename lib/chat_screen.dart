import 'package:flutter/material.dart';

import 'models/app_model.dart';
import 'models/edge.dart';
import 'models/hex_pos.dart';
import 'models/node.dart';
import 'services/api_runner.dart';
import 'widgets/api_node_sheet.dart';

class ChatScreen extends StatefulWidget {
  final AppModel model;
  const ChatScreen({super.key, required this.model});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<String> _chainPath = [];
  bool _sending = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Hex helpers ───────────────────────────────────────────────────────────

  List<HexPos> _neighbors(HexPos p) => [
        HexPos(p.q + 1, p.r),
        HexPos(p.q - 1, p.r),
        HexPos(p.q, p.r + 1),
        HexPos(p.q, p.r - 1),
        HexPos(p.q + 1, p.r - 1),
        HexPos(p.q - 1, p.r + 1),
      ];

  HexPos _freeHex(HexPos near, Set<HexPos> occupied) {
    if (!occupied.contains(near)) return near;
    final visited = <HexPos>{near};
    final queue = <HexPos>[];
    for (final p in _neighbors(near)) {
      if (visited.add(p)) queue.add(p);
    }
    while (queue.isNotEmpty) {
      final pos = queue.removeAt(0);
      if (!occupied.contains(pos)) return pos;
      for (final p in _neighbors(pos)) {
        if (visited.add(p)) queue.add(p);
      }
    }
    return near;
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _inputCtrl.clear();
    setState(() => _sending = true);

    final occupied = widget.model.nodes.map((n) => n.position).toSet();

    final HexPos anchor;
    if (_chainPath.isEmpty) {
      anchor = HexPos(0, 0);
    } else {
      anchor = widget.model.nodeById(_chainPath.last)?.position ?? HexPos(0, 0);
    }

    final textPos = _freeHex(anchor, occupied);
    occupied.add(textPos);
    final apiPos = _freeHex(textPos, occupied);

    final textNode = Node(type: NodeType.text, position: textPos, text: text);
    final apiNode = Node(type: NodeType.api, position: apiPos);
    nodeApiSettings[apiNode.id] = ApiNodeSettings();

    widget.model.addNode(textNode);
    widget.model.addNode(apiNode);

    if (_chainPath.isNotEmpty) {
      widget.model.addEdge(Edge(fromId: _chainPath.last, toId: textNode.id));
    }
    widget.model.addEdge(Edge(fromId: textNode.id, toId: apiNode.id));

    setState(() {
      _chainPath
        ..add(textNode.id)
        ..add(apiNode.id);
      _sending = false;
    });

    _scrollToBottom();
    await _runNode(apiNode);
  }

  Future<void> _runNode(Node apiNode) async {
    final messages = <Map<String, String>>[];
    for (final id in _chainPath) {
      final n = widget.model.nodeById(id);
      if (n == null || n.text.isEmpty) continue;
      messages.add({
        'role': n.type == NodeType.text ? 'user' : 'assistant',
        'content': n.text,
      });
    }
    if (messages.isEmpty) return;

    final apiSettings = nodeApiSettings[apiNode.id] ?? ApiNodeSettings();
    widget.model.updateNode(apiNode.copyWith(status: NodeStatus.running, text: ''));

    await runApiNode(
      node: apiNode,
      messages: messages,
      settings: widget.model.settings,
      apiSettings: apiSettings,
      onChunk: (chunk) {
        if (!mounted) return;
        final current = widget.model.nodeById(apiNode.id);
        if (current == null) return;
        widget.model.updateNode(
          current.copyWith(status: NodeStatus.running, text: current.text + chunk),
        );
        _scrollToBottom();
      },
      onComplete: (result, _) {
        if (!mounted) return;
        widget.model.updateNode(apiNode.copyWith(status: NodeStatus.done, text: result));
        _scrollToBottom();
      },
      onError: (error) {
        if (!mounted) return;
        widget.model.updateNode(apiNode.copyWith(status: NodeStatus.error, text: error));
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.model,
              builder: (context, _) => _buildList(),
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_chainPath.isEmpty) {
      return const Center(
        child: Text('Начните диалог',
            style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _chainPath.length,
      itemBuilder: (context, i) {
        final node = widget.model.nodeById(_chainPath[i]);
        if (node == null) return const SizedBox.shrink();
        return _ChatBubble(node: node);
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12, 8, 12,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'Сообщение…',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
    );
  }
}

// ── Bubble ────────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final Node node;
  const _ChatBubble({required this.node});

  @override
  Widget build(BuildContext context) {
    final isUser = node.type == NodeType.text;

    Widget content;
    if (!isUser) {
      switch (node.status) {
        case NodeStatus.idle:
        case NodeStatus.running when node.text.isEmpty:
          content = const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        case NodeStatus.error:
          content =
              Text(node.text, style: const TextStyle(color: Colors.red));
        default:
          content = Text(node.text);
      }
    } else {
      content = Text(node.text);
    }

    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.grey.shade200
              : Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: content,
      ),
    );
  }
}
