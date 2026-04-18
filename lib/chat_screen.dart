import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat/helpers/bubble_time.dart';
import 'chat/helpers/emoji.dart';
import 'chat/helpers/hex_placement.dart';
import 'chat/widgets/action_row.dart';
import 'chat/widgets/chat_bubble.dart';
import 'chat/widgets/history_sheet.dart';
import 'chat/widgets/markup_banner.dart';
import 'models/app_model.dart';
import 'models/attachment.dart';
import 'models/edge.dart';
import 'models/hex_layout.dart';
import 'models/hex_pos.dart';
import 'models/node.dart';
import 'models/screen_snapshot.dart';
import 'models/thesis_entry.dart';
import 'services/api_runner.dart';
import 'services/debug_server.dart';
import 'services/dump_service.dart';
import 'widgets/api_node_sheet.dart';
import 'widgets/shared/compress_sheet.dart';
import 'widgets/excerpt_extractor.dart';
import 'widgets/thesis_workshop_screen.dart';

class ChatScreen extends StatefulWidget {
  final AppModel model;
  const ChatScreen({super.key, required this.model});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    implements ScreenSnapshotProvider {
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

  // ── Visible viewport tracking для ScreenSnapshot ───────────────────────────
  // Оценка видимого диапазона индексов в chainPath. Обновляется по scroll'у
  // и при изменениях chainPath. Неточная (использует средний размер item),
  // но достаточна чтобы внешний клиент понимал «где оператор сейчас».
  int _visibleFirst = 0;
  int _visibleLast = 0;

  @override
  void initState() {
    super.initState();
    _chainPath.addAll(widget.model.chainPath);
    _globalCollapse = widget.model.settings.compactChat;
    widget.model.registerBaseProvider(this);
    _scrollCtrl.addListener(_updateVisibleRange);
    DebugServer.registerAction('chat.addNote', (model, args) async {
      final text = (args['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) return {'done': false, 'reason': 'empty text'};
      final node = _appendTextNote(text);
      return {
        'done': true,
        'nodeId': node.id,
        'chainLength': _chainPath.length,
      };
    });
    DebugServer.registerAction('chat.setChainPath', (model, args) async {
      final raw = args['chainPath'];
      if (raw is! List) {
        return {'done': false, 'reason': 'chainPath must be list of node ids'};
      }
      final ids = raw.whereType<String>().toList();
      // Проверяем, что все ноды существуют.
      for (final id in ids) {
        if (model.nodeById(id) == null) {
          return {'done': false, 'reason': 'unknown node: $id'};
        }
      }
      model.snapshot('Claude set chainPath');
      setState(() {
        _chainPath
          ..clear()
          ..addAll(ids);
      });
      _saveChain();
      return {'done': true, 'chainLength': _chainPath.length};
    });
  }

  // Добавляет текст-ноду в конец chainPath (без api-ноды, LLM не дёргается).
  // Используется action'ом chat.addNote — Claude постит заметку.
  Node _appendTextNote(String text) {
    widget.model.snapshot('Claude добавил заметку');
    final HexPos pos;
    final int dir;
    if (_chainPath.isEmpty) {
      pos = const HexPos(0, 0);
      dir = 0;
    } else {
      final lastNode = widget.model.nodeById(_chainPath.last)!;
      final slot = continuationSlot(lastNode);
      pos = slot.pos;
      dir = slot.dir;
    }
    final node = Node(
      type: NodeType.text,
      position: pos,
      text: text,
      growthDir: dir,
    );
    widget.model.addNode(node);
    if (_chainPath.isNotEmpty) {
      widget.model.addEdge(Edge(fromId: _chainPath.last, toId: node.id));
    }
    setState(() => _chainPath.add(node.id));
    _saveChain();
    _scrollToBottom();
    return node;
  }

  void _updateVisibleRange() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (_chainPath.isEmpty || pos.maxScrollExtent <= 0) {
      _visibleFirst = 0;
      _visibleLast = _chainPath.length - 1;
      return;
    }
    // Средняя высота item = полный extent / count. Приближённая оценка.
    final total = pos.maxScrollExtent + pos.viewportDimension;
    final avgH = total / _chainPath.length;
    if (avgH <= 0) return;
    final first = (pos.pixels / avgH).floor();
    final last = ((pos.pixels + pos.viewportDimension) / avgH).ceil();
    _visibleFirst = first.clamp(0, _chainPath.length - 1);
    _visibleLast = last.clamp(0, _chainPath.length - 1);
  }

  @override
  String get screenName => 'chat';

  @override
  Map<String, dynamic> capture() {
    _updateVisibleRange();
    final items = <Map<String, dynamic>>[];
    final from = _visibleFirst.clamp(0, _chainPath.length);
    final to = (_visibleLast + 1).clamp(0, _chainPath.length);
    for (var i = from; i < to; i++) {
      final n = widget.model.nodeById(_chainPath[i]);
      if (n == null) continue;
      final text = n.text;
      items.add({
        'index': i,
        'nodeId': n.id,
        'kind': n.type.name,
        'textPreview': text.length > 200 ? '${text.substring(0, 200)}…' : text,
        'collapsed': _isNodeCollapsed(n.id),
      });
    }
    return {
      'kind': 'chat',
      'title': widget.model.activeCanvas.name,
      'chainLength': _chainPath.length,
      'visibleRange': [_visibleFirst, _visibleLast],
      'sending': _sending,
      'markupMode': _markupMode,
      'globalCollapse': _globalCollapse,
      'pendingAttachments': _pendingAttachments.length,
      'items': items,
    };
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
    DebugServer.unregisterAction('chat.addNote');
    DebugServer.unregisterAction('chat.setChainPath');
    widget.model.clearBaseProvider(this);
    _scrollCtrl.removeListener(_updateVisibleRange);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Messages builder ──────────────────────────────────────────────────────

  List<Map<String, dynamic>> _buildMessages({int upTo = -1}) {
    final end = upTo < 0 ? _chainPath.length : upTo + 1;
    final messages = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (int i = 0; i < end; i++) {
      final n = widget.model.nodeById(_chainPath[i]);
      if (n == null) continue;
      if (n.text.isEmpty && n.attachments.isEmpty) continue;
      final role = n.type == NodeType.text ? 'user' : 'assistant';
      // ВР8 — подшиваем временной префикс к каждому сообщению для LLM,
      // чтобы модель видела хронологию, а не только плоский список.
      final stamp = _relativeStamp(n.createdAt, now);
      final stamped = '[$stamp] ${n.text}';
      if (n.attachments.isEmpty) {
        messages.add({'role': role, 'content': stamped});
      } else {
        messages.add({
          'role': role,
          'content': stamped,
          '_attachments': n.attachments,
        });
      }
    }
    return messages;
  }

  static String _relativeStamp(DateTime t, DateTime now) {
    final diff = now.difference(t);
    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    // Absolute for older
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  String _buildInputPreview(int chainIndex) =>
      _buildMessages(upTo: chainIndex)
          .map((m) => m['content'] as String? ?? '')
          .join('\n\n');

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
      final occ = occupiedPositions(widget.model);
      textSlot = BranchSlot(
        occ.contains(startPos) ? chainNextPos(startPos, 0) : startPos,
        0,
      );
    } else {
      final lastNode = widget.model.nodeById(_chainPath.last)!;
      final hasChildren = widget.model.activeCanvasEdges.any((e) => e.fromId == lastNode.id);
      textSlot = hasChildren
          ? branchSlot(branchPoint: lastNode, model: widget.model)
          : continuationSlot(lastNode);
    }

    final occ = occupiedPositions(widget.model)..add(textSlot.pos);
    final apiPos = chainNextPos(textSlot.pos, textSlot.dir);
    // If api position is taken, find nearest free in same direction
    final finalApiPos = occ.contains(apiPos)
        ? fallbackPos(textSlot.pos, textSlot.dir, occ)
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
        widget.model.addTokenUsage(apiSettings.provider, stats.inputTokens,
            stats.outputTokens,
            context: 'chat');
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
        ? stripEmoji(node.text)
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
    final slot = branchSlot(branchPoint: textNode, model: widget.model);
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
                MarkupBanner(
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
          ToolBtn(
            icon: Icons.undo,
            tooltip: widget.model.canUndo
                ? 'Отменить: ${widget.model.undoStack.last.description}'
                : 'Нечего отменять',
            onTap: widget.model.canUndo ? widget.model.undo : null,
          ),
          ToolBtn(
            icon: Icons.redo,
            tooltip: widget.model.canRedo ? 'Повторить' : 'Нечего повторять',
            onTap: widget.model.canRedo ? widget.model.redo : null,
          ),
          if (widget.model.canUndo)
            ToolBtn(
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
          ToolBtn(
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
      builder: (_) => HistorySheet(model: widget.model),
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
        return ChatBubble(
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
          onCompress: (node.text.isNotEmpty &&
                  !widget.model.settings.hideCompressButton)
              ? () => _compressNode(node)
              : null,
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



