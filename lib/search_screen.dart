import 'dart:math' show max, min;

import 'package:flutter/material.dart';

import 'models/app_model.dart';
import 'models/node.dart';

class SearchScreen extends StatefulWidget {
  final AppModel model;
  const SearchScreen({super.key, required this.model});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryCtrl = TextEditingController();
  final _pageCtrl = PageController();
  List<Node> _results = [];
  int _currentIdx = 0;

  @override
  void dispose() {
    _queryCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _currentIdx = 0;
      });
      return;
    }
    final lower = trimmed.toLowerCase();
    final results = widget.model.nodes
        .where((n) => n.text.toLowerCase().contains(lower))
        .toList();
    setState(() {
      _results = results;
      _currentIdx = 0;
    });
    if (results.isNotEmpty && _pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(0);
    }
  }

  void _goTo(int idx) {
    if (idx < 0 || idx >= _results.length) return;
    setState(() => _currentIdx = idx);
    _pageCtrl.animateToPage(idx,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Поиск по нодам…',
            border: InputBorder.none,
          ),
          onChanged: _search,
        ),
      ),
      body: _results.isEmpty
          ? Center(
              child: Text(
                _queryCtrl.text.trim().isEmpty
                    ? 'Введите запрос'
                    : 'Ничего не найдено',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            )
          : Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  '${_currentIdx + 1} / ${_results.length}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    onPageChanged: (i) => setState(() => _currentIdx = i),
                    itemCount: _results.length,
                    itemBuilder: (_, i) => _ResultCard(
                      node: _results[i],
                      query: _queryCtrl.text.trim(),
                      onNavigate: () => Navigator.pop(context, _results[i].id),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed:
                            _currentIdx > 0 ? () => _goTo(_currentIdx - 1) : null,
                      ),
                      const SizedBox(width: 32),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _currentIdx < _results.length - 1
                            ? () => _goTo(_currentIdx + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Result card ───────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final Node node;
  final String query;
  final VoidCallback onNavigate;

  const _ResultCard({
    required this.node,
    required this.query,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = node.type == NodeType.text;
    const ctxLen = 120;
    final text = node.text;
    final lower = text.toLowerCase();
    final matchIdx = query.isNotEmpty ? lower.indexOf(query.toLowerCase()) : -1;

    final start = matchIdx >= 0 ? max(0, matchIdx - ctxLen) : 0;
    final rawEnd = matchIdx >= 0
        ? min(text.length, matchIdx + query.length + ctxLen)
        : min(text.length, ctxLen * 2);
    final raw = text.substring(start, rawEnd);
    final prefix = start > 0 ? '…' : '';
    final suffix = rawEnd < text.length ? '…' : '';

    final ts = DefaultTextStyle.of(context)
        .style
        .copyWith(fontSize: 14, height: 1.5);

    Widget contentWidget;
    if (matchIdx >= 0) {
      final mStart = matchIdx - start;
      final mEnd = mStart + query.length;
      contentWidget = RichText(
        text: TextSpan(style: ts, children: [
          if (prefix.isNotEmpty)
            TextSpan(
                text: prefix, style: TextStyle(color: Colors.grey[500])),
          TextSpan(text: raw.substring(0, mStart)),
          TextSpan(
            text: raw.substring(mStart, mEnd),
            style: TextStyle(
              backgroundColor: Colors.yellow.shade200,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: raw.substring(mEnd)),
          if (suffix.isNotEmpty)
            TextSpan(
                text: suffix, style: TextStyle(color: Colors.grey[500])),
        ]),
      );
    } else {
      contentWidget =
          Text('$prefix$raw$suffix', style: ts);
    }

    return GestureDetector(
      onTap: onNavigate,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(
                  isUser ? Icons.person_outline : Icons.smart_toy_outlined,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  isUser ? 'Пользователь' : 'Ассистент',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (node.name.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(node.name,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ]),
              const SizedBox(height: 8),
              contentWidget,
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onNavigate,
                  child: const Text('Перейти к ноде'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
