import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'models/app_model.dart';
import 'models/attachment.dart';
import 'models/edge.dart';
import 'models/hex_layout.dart';
import 'models/hex_pos.dart';
import 'models/node.dart';
import 'models/thesis_entry.dart';
import 'services/api_runner.dart';
import 'services/dump_service.dart';
import 'widgets/api_node_sheet.dart';
import 'widgets/compress_sheet.dart';
import 'widgets/excerpt_extractor.dart';
import 'widgets/thesis_workshop_screen.dart';

// ── Emoji stripping ───────────────────────────────────────────────────────

bool _isEmojiCodePoint(int r) =>
    (r >= 0x1F000 && r <= 0x1FFFF) || // All emoji in Plane 1
    (r >= 0x2600 && r <= 0x27BF) || // Misc symbols, dingbats
    (r >= 0xFE00 && r <= 0xFE0F) || // Variation selectors
    r == 0x200D || // ZWJ
    r == 0x20E3; // Combining enclosing keycap

String _stripEmoji(String s) =>
    String.fromCharCodes(s.runes.where((r) => !_isEmojiCodePoint(r)));

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
  CancelToken? _runToken;
  final List<Attachment> _pendingAttachments = [];

  // Markup / thesis mode
  bool _markupMode = false;

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

  // Sync local _chainPath from model (needed after undo/redo)
  void _syncChainPath() {
    if (listEquals(_chainPath, widget.model.chainPath)) return;
    _chainPath..clear()..addAll(widget.model.chainPath);
    _collapsedOverrides.clear();
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

  List<Map<String, dynamic>> _buildMessages({int upTo = -1}) {
    final end = upTo < 0 ? _chainPath.length : upTo + 1;
    final messages = <Map<String, dynamic>>[];
    for (int i = 0; i < end; i++) {
      final n = widget.model.nodeById(_chainPath[i]);
      if (n == null) continue;
      if (n.text.isEmpty && n.attachments.isEmpty) continue;
      final role = n.type == NodeType.text ? 'user' : 'assistant';
      if (n.attachments.isEmpty) {
        messages.add({'role': role, 'content': n.text});
      } else {
        messages.add({
          'role': role,
          'content': n.text,
          '_attachments': n.attachments,
        });
      }
    }
    return messages;
  }

  String _buildInputPreview(int chainIndex) =>
      _buildMessages(upTo: chainIndex)
          .map((m) => m['content'] as String? ?? '')
          .join('\n\n');

  // ── Placement helpers ─────────────────────────────────────────────────────

  Set<HexPos> get _occupied {
    final activeIds = widget.model.activeCanvas.nodeIds.toSet();
    return widget.model.nodes
        .where((n) => activeIds.contains(n.id))
        .map((n) => n.position)
        .toSet();
  }

  BranchSlot _continuationSlot(Node lastNode) {
    final pos = chainNextPos(lastNode.position, lastNode.growthDir);
    return BranchSlot(pos, lastNode.growthDir);
  }

  BranchSlot _branchSlot(Node branchPoint) {
    final usedDirs = widget.model.activeCanvasEdges
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

  // ── Attachments ───────────────────────────────────────────────────────────

  void _showAttachOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Изображение'),
              onTap: () { Navigator.pop(ctx); _pickImages(); },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Файл'),
              onTap: () { Navigator.pop(ctx); _pickFiles(); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null) return;
      final added = <Attachment>[];
      for (final file in result.files) {
        final bytes = await _readPickedFileBytes(file);
        if (bytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${file.name}: не удалось прочитать'),
              duration: const Duration(seconds: 2),
            ));
          }
          continue;
        }
        added.add(Attachment(
          filename: file.name,
          mimeType: _imageMime(file.extension ?? ''),
          base64Data: base64Encode(bytes),
        ));
      }
      if (added.isEmpty) return;
      setState(() => _pendingAttachments.addAll(added));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка выбора изображения: $e'),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  /// Tries three methods to read bytes from a picked file, in order:
  /// 1. inline bytes (withData: true)
  /// 2. read stream (withReadStream: true — works with Android content URIs)
  /// 3. file path (older Android / desktop)
  Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes;
    if (file.readStream != null) {
      try {
        final chunks = await file.readStream!.toList();
        return Uint8List.fromList(chunks.expand((x) => x).toList());
      } catch (_) {}
    }
    if (file.path != null) {
      try {
        return await File(file.path!).readAsBytes();
      } catch (_) {}
    }
    return null;
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    final added = <Attachment>[];
    for (final file in result.files) {
      if (file.bytes == null) continue;
      try {
        final text = utf8.decode(file.bytes!, allowMalformed: false);
        added.add(Attachment(
          filename: file.name,
          mimeType: 'text/plain',
          textContent: text,
        ));
      } catch (_) {
        // Not valid UTF-8 (e.g. binary PDF) — skip with feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${file.name}: не удалось прочитать как текст'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
    if (added.isEmpty) return;
    setState(() => _pendingAttachments.addAll(added));
  }

  String _imageMime(String ext) {
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

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final raw = _inputCtrl.text.trim();
    if ((raw.isEmpty && _pendingAttachments.isEmpty) || _sending) return;
    final text = raw.isEmpty
        ? ''
        : raw[0].toUpperCase() + raw.substring(1);
    _inputCtrl.clear();
    setState(() => _sending = true);
    widget.model.snapshot('Отправить сообщение');

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
      final hasChildren = widget.model.activeCanvasEdges.any((e) => e.fromId == lastNode.id);
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
      attachments: List.from(_pendingAttachments),
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
      _pendingAttachments.clear();
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

    final token = CancelToken();
    if (mounted) setState(() => _runToken = token);

    await runApiNode(
      node: apiNode,
      messages: messages,
      settings: widget.model.settings,
      apiSettings: apiSettings,
      cancelToken: token,
      onChunk: (chunk) {
        if (!mounted) return;
        final current = widget.model.nodeById(apiNode.id);
        if (current == null) return;
        widget.model.updateNode(
          current.copyWith(status: NodeStatus.running, text: current.text + chunk),
        );
        _scrollToBottom();
      },
      onComplete: (result, stats) {
        if (!mounted) return;
        widget.model.updateNode(apiNode.copyWith(status: NodeStatus.done, text: result));
        widget.model.addTokenUsage(apiSettings.provider, stats.inputTokens, stats.outputTokens);
        _scrollToBottom();
      },
      onError: (error) {
        if (!mounted) return;
        widget.model.updateNode(apiNode.copyWith(status: NodeStatus.error, text: error));
      },
    );

    if (mounted) setState(() => _runToken = null);
  }

  void _stopGeneration() {
    _runToken?.cancel();
    setState(() => _runToken = null);
  }

  // ── Bubble actions ────────────────────────────────────────────────────────

  Future<void> _dumpBranch() async {
    if (_chainPath.isEmpty) return;
    final messages = _buildMessages();
    if (messages.isEmpty) return;
    try {
      final file = await DumpService.saveDump(
        messages: messages,
        canvasName: widget.model.activeCanvas.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Дамп сохранён: ${file.path.split('/').last}'),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка дампа: $e')),
      );
    }
  }

  void _enterMarkup(Node node) {
    setState(() => _markupMode = true);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExcerptExtractor(
        text: node.text,
        onConfirm: (excerpts) {
          for (final e in excerpts) {
            widget.model.theses.add(
              ThesisEntry(sourceNodeId: node.id, excerpt: e),
            );
          }
          widget.model.notifyThesesChanged();
        },
      ),
    ));
  }

  void _exitMarkup() => setState(() => _markupMode = false);

  void _compressNode(Node node) {
    openCompressSheet(
      context,
      text: node.text,
      settings: widget.model.settings,
      onApply: (result) {
        final idx = widget.model.nodes.indexWhere((n) => n.id == node.id);
        if (idx < 0) return;
        widget.model.snapshot('Сжатие ноды');
        widget.model.updateNode(node.copyWith(
          text: result,
          updatedAt: DateTime.now(),
        ));
      },
    );
  }

  void _copyNode(Node node) {
    final text = widget.model.settings.hideEmoji
        ? _stripEmoji(node.text)
        : node.text;
    Clipboard.setData(ClipboardData(text: text));
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
    widget.model.snapshot('Ветвление');
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
    widget.model.snapshot('Ветвление');
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
    return widget.model.activeCanvasEdges
        .where((e) => e.fromId == parentId)
        .map((e) => e.toId)
        .toList();
  }

  List<String> _followChain(String startId) {
    final result = <String>[startId];
    var current = startId;
    for (int i = 0; i < 200; i++) {
      final children = widget.model.activeCanvasEdges
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
        content: const Text('Эта нода и все что от неё будут удалены. Можно отменить через ↩.'),
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

    // BFS: collect only the selected branch and its descendants
    final toDelete = <String>{};
    final queue = <String>[_chainPath[chainIndex]];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      toDelete.add(current);
      for (final e in widget.model.activeCanvasEdges) {
        if (e.fromId == current && !toDelete.contains(e.toId)) {
          queue.add(e.toId);
        }
      }
    }

    // Find a sibling to switch to after deletion
    final siblings = _siblingsOf(chainIndex);
    final remaining = siblings.where((id) => !toDelete.contains(id)).toList();

    // Snapshot for undo before any mutation
    widget.model.snapshot('Удалить ветку');

    // Update chain: truncate, then switch to sibling if available
    _chainPath.removeRange(chainIndex, _chainPath.length);
    if (remaining.isNotEmpty) {
      _chainPath.addAll(_followChain(remaining.first));
    }

    setState(() {});
    widget.model.chainPath..clear()..addAll(_chainPath);
    widget.model.removeNodes(toDelete); // saves + notifies
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
      child: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          _syncChainPath();
          return Column(
            children: [
              if (_markupMode)
                _MarkupBanner(
                  count: widget.model.theses.length,
                  onExit: _exitMarkup,
                  onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ThesisWorkshopScreen(model: widget.model),
                  )),
                ),
              Expanded(child: _buildList()),
              if (_chainPath.isNotEmpty) _buildChatToolbar(),
              _buildInputBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChatToolbar() {
    final canvasName = widget.model.activeCanvas.name;
    final msgCount = _chainPath.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _ToolBtn(
            icon: Icons.undo,
            tooltip: widget.model.canUndo
                ? 'Отменить: ${widget.model.undoStack.last.description}'
                : 'Нечего отменять',
            onTap: widget.model.canUndo ? widget.model.undo : null,
          ),
          _ToolBtn(
            icon: Icons.redo,
            tooltip: widget.model.canRedo ? 'Повторить' : 'Нечего повторять',
            onTap: widget.model.canRedo ? widget.model.redo : null,
          ),
          if (widget.model.canUndo)
            _ToolBtn(
              icon: Icons.history,
              tooltip: 'История',
              onTap: () => _showHistory(),
            ),
          const Spacer(),
          if (canvasName.isNotEmpty)
            Text(
              canvasName,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(width: 8),
          Text(
            '$msgCount',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
          const SizedBox(width: 4),
          _ToolBtn(
            icon: _globalCollapse ? Icons.unfold_more : Icons.unfold_less,
            tooltip: _globalCollapse ? 'Развернуть все' : 'Свернуть все',
            onTap: _toggleAll,
          ),
        ],
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      builder: (_) => _HistorySheet(model: widget.model),
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
          renderMarkdown: widget.model.settings.renderMarkdown,
          hideEmoji: widget.model.settings.hideEmoji,
          showTime: widget.model.settings.showBubbleTime,
          showId: widget.model.settings.showBubbleId,
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
          onMarkup: (node.text.isNotEmpty && !widget.model.settings.hideThesisButton)
              ? () => _enterMarkup(node)
              : null,
          markupActive: _markupMode,
          onCompress: node.text.isNotEmpty ? () => _compressNode(node) : null,
        );
      },
    );
  }

  Widget _buildInputBar() {
    final running = _runToken != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12, 8, 12,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warn when images are attached but the active provider doesn't support vision
          if (_pendingAttachments.any((a) => a.isImage) &&
              widget.model.settings.defaultProvider == 'deepseek')
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.warning_amber_outlined,
                    size: 14, color: Colors.orange[700]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'deepseek-chat не поддерживает изображения — смените провайдера на Anthropic или OpenAI',
                    style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                  ),
                ),
              ]),
            ),
          if (_pendingAttachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _pendingAttachments.map((a) => Chip(
                  avatar: Icon(
                    a.isImage ? Icons.image_outlined : Icons.description_outlined,
                    size: 14,
                  ),
                  label: Text(
                    a.filename,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onDeleted: running
                      ? null
                      : () => setState(() => _pendingAttachments.remove(a)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                )).toList(),
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.download_for_offline_outlined),
                tooltip: 'Сохранить дамп ветки',
                onPressed: _chainPath.isEmpty ? null : _dumpBranch,
              ),
              IconButton(
                icon: Icon(
                  Icons.attach_file,
                  color: _pendingAttachments.isNotEmpty
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                tooltip: 'Прикрепить файл',
                onPressed: running ? null : _showAttachOptions,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Сообщение…',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: running ? null : (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              if (running)
                IconButton(
                  icon: const Icon(Icons.stop_circle_outlined),
                  color: Colors.red[400],
                  tooltip: 'Остановить',
                  onPressed: _stopGeneration,
                )
              else
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
            ],
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
  final bool renderMarkdown;
  final bool hideEmoji;
  final bool showTime;
  final bool showId;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final VoidCallback? onDeleteBranch;
  final VoidCallback? onMarkup;
  final VoidCallback? onCompress;
  final bool markupActive;

  const _ChatBubble({
    required this.node,
    this.siblingCount = 1,
    this.siblingIndex = 0,
    this.isCollapsed = false,
    this.maxLines = 5,
    this.renderMarkdown = false,
    this.hideEmoji = false,
    this.showTime = false,
    this.showId = false,
    this.onDoubleTap,
    this.onSwipeLeft,
    this.onSwipeRight,
    required this.onCopy,
    this.onEdit,
    this.onBranch,
    this.onRetry,
    this.onSettings,
    this.onDeleteBranch,
    this.onMarkup,
    this.onCompress,
    this.markupActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = node.type == NodeType.text;
    final displayText =
        hideEmoji ? _stripEmoji(node.text) : node.text;

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
            displayText,
            style: const TextStyle(color: Colors.red),
            maxLines: isCollapsed ? maxLines : null,
            overflow: isCollapsed ? TextOverflow.ellipsis : null,
          );
        default:
          if (!isCollapsed && renderMarkdown && node.status == NodeStatus.done && node.text.isNotEmpty) {
            content = MarkdownBody(
              data: displayText,
              selectable: true,
              softLineBreak: true,
            );
          } else {
            content = Text(
              displayText,
              maxLines: isCollapsed ? maxLines : null,
              overflow: isCollapsed ? TextOverflow.ellipsis : null,
            );
          }
      }
    } else {
      content = Text(
        displayText,
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
              onMarkup: onMarkup,
              onCompress: onCompress,
              markupActive: markupActive,
            ),
            if (showTime || showId)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showTime)
                      Text(
                        _formatBubbleTime(node.createdAt),
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    if (showTime && showId)
                      Text('  ·  ',
                          style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    if (showId)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: node.id));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Скопировано: ${node.id.substring(0, 6)}'),
                            duration: const Duration(seconds: 1),
                          ));
                        },
                        child: Text(
                          node.id.substring(0, 6),
                          style: TextStyle(fontSize: 10, color: Colors.teal[400]),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatBubbleTime(DateTime dt) {
  final now = DateTime.now();
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return '$h:$m';
  }
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} $h:$m';
}

class _ActionRow extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final VoidCallback? onDeleteBranch;
  final VoidCallback? onMarkup;
  final VoidCallback? onCompress;
  final bool markupActive;

  const _ActionRow({
    required this.onCopy,
    this.onEdit,
    this.onBranch,
    this.onRetry,
    this.onSettings,
    this.onDeleteBranch,
    this.onMarkup,
    this.onCompress,
    this.markupActive = false,
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
        if (onMarkup != null)
          _Btn(
            icon: Icons.format_quote_outlined,
            tooltip: 'Добавить тезис',
            onTap: onMarkup!,
            color: markupActive ? Colors.deepPurple[300] : null,
          ),
        if (onCompress != null)
          _Btn(icon: Icons.compress, tooltip: 'Сжать…', onTap: onCompress!),
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

// ── Toolbar button (larger, supports null = disabled) ─────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _ToolBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onTap,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      color: onTap != null ? Colors.grey[700] : Colors.grey[400],
    );
  }
}

// ── History sheet ─────────────────────────────────────────────────────────

class _HistorySheet extends StatelessWidget {
  final AppModel model;
  const _HistorySheet({required this.model});

  @override
  Widget build(BuildContext context) {
    final stack = model.undoStack.reversed.toList();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 32, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text('История изменений',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
          if (stack.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Нет записей', style: TextStyle(color: Colors.grey)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stack.length,
                itemBuilder: (_, i) => ListTile(
                  leading: Icon(Icons.history,
                      size: 18, color: Colors.grey[500]),
                  title: Text(stack[i].description.isEmpty
                      ? '—'
                      : stack[i].description,
                      style: const TextStyle(fontSize: 14)),
                  dense: true,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (model.canUndo)
                  TextButton.icon(
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Отменить шаг'),
                    onPressed: () {
                      Navigator.pop(context);
                      model.undo();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Markup banner ─────────────────────────────────────────────────────────────

class _MarkupBanner extends StatelessWidget {
  final int count;
  final VoidCallback onExit;
  final VoidCallback onOpen;
  const _MarkupBanner({required this.count, required this.onExit, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.deepPurple[50],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.format_quote_outlined, size: 16, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Text('Тезисы · $count', style: const TextStyle(fontSize: 13, color: Colors.deepPurple)),
          const Spacer(),
          GestureDetector(
            onTap: onOpen,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('Открыть →', style: TextStyle(fontSize: 13, color: Colors.deepPurple, fontWeight: FontWeight.w600)),
            ),
          ),
          GestureDetector(
            onTap: onExit,
            child: const Icon(Icons.close, size: 18, color: Colors.deepPurple),
          ),
        ],
      ),
    );
  }
}
