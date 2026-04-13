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

  // Collapse state
  // When _globalCollapse=true, _collapsedOverrides = explicitly expanded nodes.
  // When _globalCollapse=false, _collapsedOverrides = explicitly collapsed nodes.
  bool _globalCollapse = false;
  final _collapsedOverrides = <String>{};

  @override
  void initState() {
    super.initState();
    _chainPath.addAll(widget.model.chainPath);
    _globalCollapse = widget.model.settings.compactChat;
  }

  bool _isNodeCollapsed(String nodeId) {
    if (_globalCollapse) return !_collapsedOverrides.contains(nodeId);
    return _collapsedOverrides.contains(nodeId);
  }

  void _toggleNodeCollapse(String nodeId) {
    setState(() {
      if (_collapsedOverrides.contains(nodeId)) {
        _collapsedOverrides.remove(nodeId);
      } else {
        _collapsedOverrides.add(nodeId);
      }
    });
  }

  void _toggleAll() {
    setState(() {
      _globalCollapse = !_globalCollapse;
      _collapsedOverrides.clear();
    });
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
    final raw = _inputCtrl.text.trim();
    if (raw.isEmpty || _sending) return;
    final text = raw[0].toUpperCase() + raw.substring(1);
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
    nodeApiSettings[apiNode.id] = ApiNodeSettings(
      provider: widget.model.settings.defaultProvider,
      model: widget.model.settings.defaultModel,
      maxTokens: widget.model.settings.defaultMaxTokens,
      temperature: widget.model.settings.defaultTemperature,
    );

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
    nodeApiSettings[apiNode.id] = ApiNodeSettings(
      provider: widget.model.settings.defaultProvider,
      model: widget.model.settings.defaultModel,
      maxTokens: widget.model.settings.defaultMaxTokens,
      temperature: widget.model.settings.defaultTemperature,
    );

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

  // ── Branch switching ──────────────────────────────────────────────────────

  List<String> _siblingsOf(int chainIndex) {
    if (chainIndex == 0) return [_chainPath[chainIndex]];
    final parentId = _chainPath[chainIndex - 1];
    return widget.model.edges
        .where((e) => e.fromId == parentId)
        .map((e) => e.toId)
        .toList();
  }

  List<String> _followChain(String startId) {
    final result = <String>[startId];
    var current = startId;
    for (int i = 0; i < 200; i++) {
      final children = widget.model.edges
          .where((e) => e.fromId == current)
          .map((e) => e.toId)
          .toList();
      if (children.isEmpty) break;
      result.add(children.first);
      current = children.first;
    }
    return result;
  }

  Future<void> _deleteBranch(int chainIndex) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить ветку?'),
        content: const Text('Эта нода и все что от неё будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // BFS: collect all descendant node IDs from this point
    final toDelete = <String>{};
    final queue = <String>[_chainPath[chainIndex]];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      toDelete.add(current);
      for (final e in widget.model.edges) {
        if (e.fromId == current && !toDelete.contains(e.toId)) {
          queue.add(e.toId);
        }
      }
    }

    setState(() => _chainPath.removeRange(chainIndex, _chainPath.length));
    _saveChain();
    widget.model.removeNodes(toDelete);
  }

  void _switchBranch(int chainIndex, int delta) {
    final siblings = _siblingsOf(chainIndex);
    if (siblings.length <= 1) return;
    final currentId = _chainPath[chainIndex];
    final idx = siblings.indexOf(currentId);
    if (idx < 0) return;
    final nextIdx = (idx + delta + siblings.length) % siblings.length;
    final suffix = _followChain(siblings[nextIdx]);
    setState(() {
      _chainPath
        ..removeRange(chainIndex, _chainPath.length)
        ..addAll(suffix);
    });
    _saveChain();
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
          if (_chainPath.isNotEmpty) _buildChatToolbar(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildChatToolbar() {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: Icon(
              _globalCollapse ? Icons.unfold_more : Icons.unfold_less,
              size: 18,
            ),
            tooltip: _globalCollapse ? 'Развернуть все' : 'Свернуть все',
            onPressed: _toggleAll,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            color: Colors.grey[600],
          ),
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
        final siblings = _siblingsOf(i);
        final siblingIndex = siblings.indexOf(_chainPath[i]);
        final isLast = i == _chainPath.length - 1;
        final isApi = node.type == NodeType.api;
        return _ChatBubble(
          node: node,
          siblingCount: siblings.length,
          siblingIndex: siblingIndex < 0 ? 0 : siblingIndex,
          isCollapsed: _isNodeCollapsed(node.id),
          maxLines: widget.model.settings.compactLines,
          onDoubleTap: () => _toggleNodeCollapse(node.id),
          onSwipeLeft: siblings.length > 1 ? () => _switchBranch(i, 1) : null,
          onSwipeRight: siblings.length > 1 ? () => _switchBranch(i, -1) : null,
          onCopy: () => _copyNode(node),
          onEdit: !isApi ? () => _editNode(node, i) : null,
          // ⎇ hidden on last API node (input field already continues from there)
          onBranch: isApi && isLast
              ? null
              : (isApi ? () => _branchFromApi(i) : () => _branchFromText(node, i)),
          // ↺ only on last API node or on error
          onRetry: isApi && (isLast || node.status == NodeStatus.error)
              ? () => _retryNode(node)
              : null,
          onSettings: isApi ? () => _showNodeSettings(node, i) : null,
          onDeleteBranch: () => _deleteBranch(i),
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
  final int siblingCount;
  final int siblingIndex;
  final bool isCollapsed;
  final int maxLines;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final VoidCallback? onDeleteBranch;

  const _ChatBubble({
    required this.node,
    this.siblingCount = 1,
    this.siblingIndex = 0,
    this.isCollapsed = false,
    this.maxLines = 5,
    this.onDoubleTap,
    this.onSwipeLeft,
    this.onSwipeRight,
    required this.onCopy,
    this.onEdit,
    this.onBranch,
    this.onRetry,
    this.onSettings,
    this.onDeleteBranch,
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
          content = Text(
            node.text,
            style: const TextStyle(color: Colors.red),
            maxLines: isCollapsed ? maxLines : null,
            overflow: isCollapsed ? TextOverflow.ellipsis : null,
          );
        default:
          content = Text(
            node.text,
            maxLines: isCollapsed ? maxLines : null,
            overflow: isCollapsed ? TextOverflow.ellipsis : null,
          );
      }
    } else {
      content = Text(
        node.text,
        maxLines: isCollapsed ? maxLines : null,
        overflow: isCollapsed ? TextOverflow.ellipsis : null,
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) onSwipeLeft?.call();
          if (v > 200) onSwipeRight?.call();
        },
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
            if (siblingCount > 1)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(siblingCount, (i) => Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == siblingIndex
                          ? Colors.grey[700]
                          : Colors.grey[300],
                    ),
                  )),
                ),
              ),
            _ActionRow(
              onCopy: onCopy,
              onEdit: onEdit,
              onBranch: onBranch,
              onRetry: onRetry,
              onSettings: onSettings,
              onDeleteBranch: onDeleteBranch,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final VoidCallback? onDeleteBranch;

  const _ActionRow({
    required this.onCopy,
    this.onEdit,
    this.onBranch,
    this.onRetry,
    this.onSettings,
    this.onDeleteBranch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Btn(icon: Icons.copy_outlined, tooltip: 'Копировать', onTap: onCopy),
        if (onEdit != null)
          _Btn(icon: Icons.edit_outlined, tooltip: 'Редактировать', onTap: onEdit!),
        if (onBranch != null)
          _Btn(icon: Icons.call_split, tooltip: 'Ветвление', onTap: onBranch!),
        if (onRetry != null)
          _Btn(icon: Icons.replay, tooltip: 'Повторить', onTap: onRetry!),
        if (onSettings != null)
          _Btn(icon: Icons.more_horiz, tooltip: 'Настройки', onTap: onSettings!),
        if (onDeleteBranch != null)
          _Btn(icon: Icons.delete_outline, tooltip: 'Удалить ветку', onTap: onDeleteBranch!, color: Colors.red[300]),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _Btn({required this.icon, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onTap,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      color: color ?? Colors.grey[600],
    );
  }
}
