import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_model.dart';
import 'models/edge.dart';
import 'models/hex_layout.dart';
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
  void initState() {
    super.initState();
    _chainPath.addAll(widget.model.chainPath);
  }

  void _saveChain() {
    widget.model.chainPath
      ..clear()
      ..addAll(_chainPath);
    widget.model.save();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Messages builder ──────────────────────────────────────────────────────

  List<Map<String, String>> _buildMessages({int upTo = -1}) {
    final end = upTo < 0 ? _chainPath.length : upTo + 1;
    final messages = <Map<String, String>>[];
    for (int i = 0; i < end; i++) {
      final n = widget.model.nodeById(_chainPath[i]);
      if (n == null || n.text.isEmpty) continue;
      messages.add({
        'role': n.type == NodeType.text ? 'user' : 'assistant',
        'content': n.text,
      });
    }
    return messages;
  }

  String _buildInputPreview(int chainIndex) =>
      _buildMessages(upTo: chainIndex).map((m) => m['content']!).join('\n\n');

  // ── Placement helpers ─────────────────────────────────────────────────────

  Set<HexPos> get _occupied =>
      widget.model.nodes.map((n) => n.position).toSet();

  BranchSlot _continuationSlot(Node lastNode) {
    final pos = chainNextPos(lastNode.position, lastNode.growthDir);
    return BranchSlot(pos, lastNode.growthDir);
  }

  BranchSlot _branchSlot(Node branchPoint) {
    final usedDirs = widget.model.edges
        .where((e) => e.fromId == branchPoint.id)
        .map((e) => widget.model.nodeById(e.toId))
        .whereType<Node>()
        .map((n) => n.growthDir)
        .toSet();
    return nextBranchSlot(
      from: branchPoint.position,
      parentGrowthDir: branchPoint.growthDir,
      usedChildDirs: usedDirs,
      occupied: _occupied,
    );
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _inputCtrl.clear();
    setState(() => _sending = true);

    final BranchSlot textSlot;

    if (_chainPath.isEmpty) {
      final startPos = HexPos(0, 0);
      final occ = _occupied;
      textSlot = BranchSlot(
        occ.contains(startPos) ? chainNextPos(startPos, 0) : startPos,
        0,
      );
    } else {
      final lastNode = widget.model.nodeById(_chainPath.last)!;
      final hasChildren = widget.model.edges.any((e) => e.fromId == lastNode.id);
      textSlot = hasChildren ? _branchSlot(lastNode) : _continuationSlot(lastNode);
    }

    final occ = _occupied..add(textSlot.pos);
    final apiPos = chainNextPos(textSlot.pos, textSlot.dir);
    // If api position is taken, find nearest free in same direction
    final finalApiPos = occ.contains(apiPos)
        ? _fallbackPos(textSlot.pos, textSlot.dir, occ)
        : apiPos;

    final textNode = Node(
      type: NodeType.text,
      position: textSlot.pos,
      text: text,
      growthDir: textSlot.dir,
    );
    final apiNode = Node(
      type: NodeType.api,
      position: finalApiPos,
      growthDir: textSlot.dir,
    );
    nodeApiSettings[apiNode.id] = ApiNodeSettings();

    widget.model.addNode(textNode);
    widget.model.addNode(apiNode);

    if (_chainPath.isNotEmpty) {
      widget.model.addEdge(Edge(fromId: _chainPath.last, toId: textNode.id));
    }
    widget.model.addEdge(Edge(fromId: textNode.id, toId: apiNode.id));

    setState(() {
      _chainPath..add(textNode.id)..add(apiNode.id);
      _sending = false;
    });
    _saveChain();
    _scrollToBottom();
    await _runNode(apiNode);
  }

  HexPos _fallbackPos(HexPos from, int dir, Set<HexPos> occ) {
    for (int s = 2; s <= 10; s++) {
      final p = hexStep(from, dir, s);
      if (!occ.contains(p)) return p;
    }
    return hexStep(from, dir, 2);
  }

  Future<void> _runNode(Node apiNode) async {
    final chainIndex = _chainPath.indexOf(apiNode.id);
    final messages = _buildMessages(upTo: chainIndex);
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

  // ── Bubble actions ────────────────────────────────────────────────────────

  void _copyNode(Node node) {
    Clipboard.setData(ClipboardData(text: node.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _editNode(Node node, int chainIndex) async {
    final ctrl = TextEditingController(text: node.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать'),
        content: TextField(
          controller: ctrl,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result == node.text) return;

    widget.model.updateNode(node.copyWith(text: result));

    for (int j = chainIndex + 1; j < _chainPath.length; j++) {
      final n = widget.model.nodeById(_chainPath[j]);
      if (n != null && n.type == NodeType.api) {
        widget.model.updateNode(n.copyWith(status: NodeStatus.idle, text: ''));
      }
    }
  }

  void _branchFromText(Node textNode, int chainIndex) {
    final slot = _branchSlot(textNode);
    final apiNode = Node(
      type: NodeType.api,
      position: slot.pos,
      growthDir: slot.dir,
    );
    nodeApiSettings[apiNode.id] = ApiNodeSettings();

    widget.model.addNode(apiNode);
    widget.model.addEdge(Edge(fromId: textNode.id, toId: apiNode.id));

    setState(() {
      _chainPath
        ..removeRange(chainIndex + 1, _chainPath.length)
        ..add(apiNode.id);
    });
    _saveChain();
    _runNode(apiNode);
  }

  void _branchFromApi(int chainIndex) {
    setState(() => _chainPath.removeRange(chainIndex + 1, _chainPath.length));
    _saveChain();
  }

  Future<void> _retryNode(Node apiNode) async {
    widget.model.updateNode(apiNode.copyWith(status: NodeStatus.idle, text: ''));
    await _runNode(apiNode);
  }

  void _showNodeSettings(Node node, int chainIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ApiNodeSheet(
        node: node,
        settings: widget.model.settings,
        buildInput: (_) => _buildInputPreview(chainIndex),
        onChanged: widget.model.updateNode,
        onRun: (n) => _retryNode(n),
      ),
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
        return _ChatBubble(
          node: node,
          onCopy: () => _copyNode(node),
          onEdit: node.type == NodeType.text ? () => _editNode(node, i) : null,
          onBranch: node.type == NodeType.text
              ? () => _branchFromText(node, i)
              : () => _branchFromApi(i),
          onRetry: (node.type == NodeType.api && node.status == NodeStatus.error)
              ? () => _retryNode(node)
              : null,
          onSettings: node.type == NodeType.api
              ? () => _showNodeSettings(node, i)
              : null,
        );
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
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback onBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;

  const _ChatBubble({
    required this.node,
    required this.onCopy,
    this.onEdit,
    required this.onBranch,
    this.onRetry,
    this.onSettings,
  });

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
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser
                  ? Colors.grey.shade200
                  : Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: content,
          ),
          _ActionRow(
            onCopy: onCopy,
            onEdit: onEdit,
            onBranch: onBranch,
            onRetry: onRetry,
            onSettings: onSettings,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback onBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;

  const _ActionRow({
    required this.onCopy,
    this.onEdit,
    required this.onBranch,
    this.onRetry,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Btn(icon: Icons.copy_outlined, tooltip: 'Копировать', onTap: onCopy),
        if (onEdit != null)
          _Btn(icon: Icons.edit_outlined, tooltip: 'Редактировать', onTap: onEdit!),
        _Btn(icon: Icons.call_split, tooltip: 'Ветвление', onTap: onBranch),
        if (onRetry != null)
          _Btn(icon: Icons.replay, tooltip: 'Повторить', onTap: onRetry!),
        if (onSettings != null)
          _Btn(icon: Icons.more_horiz, tooltip: 'Настройки', onTap: onSettings!),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _Btn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onTap,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      color: Colors.grey[600],
    );
  }
}
