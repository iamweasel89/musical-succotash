import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_model.dart';
import '../services/debug_server.dart';

// ── Мастерская: Отладка ──────────────────────────────────────────────────────

class DebugScreen extends StatefulWidget {
  final AppModel model;
  const DebugScreen({super.key, required this.model});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  List<Map<String, dynamic>> _ips = [];
  String? _startError;

  @override
  void initState() {
    super.initState();
    DebugServer.addListener(_onServerChange);
    _refreshIps();
  }

  @override
  void dispose() {
    DebugServer.removeListener(_onServerChange);
    super.dispose();
  }

  void _onServerChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshIps() async {
    final ips = await DebugServer.currentIps();
    if (mounted) setState(() => _ips = ips);
  }

  Future<void> _toggle(bool v) async {
    final s = widget.model.settings;
    s.debugServerEnabled = v;
    widget.model.notifySettingsChanged();
    setState(() => _startError = null);
    try {
      if (v) {
        await DebugServer.start(widget.model, s.debugServerPort);
      } else {
        await DebugServer.stop();
      }
    } catch (e) {
      if (mounted) setState(() => _startError = e.toString());
    }
    _refreshIps();
  }

  @override
  Widget build(BuildContext context) {
    final port = widget.model.settings.debugServerPort;
    final running = DebugServer.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Отладка'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshIps,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Debug HTTP server'),
            subtitle: Text(
              running
                  ? 'Запущен на :${DebugServer.port}'
                  : 'Выключен',
              style: TextStyle(color: running ? Colors.green : Colors.grey),
            ),
            value: widget.model.settings.debugServerEnabled,
            onChanged: _toggle,
          ),
          if (_startError != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Ошибка: $_startError',
                  style: const TextStyle(color: Colors.red)),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Доступные адреса',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (_ips.isEmpty)
            const Text('(нет сетевых интерфейсов)',
                style: TextStyle(color: Colors.grey)),
          ..._ips.map((ip) => _IpTile(
                ip: ip['ip'] as String,
                iface: ip['iface'] as String,
                kind: ip['kind'] as String? ?? '',
                port: port,
              )),
          const SizedBox(height: 24),
          const Text('Endpoints',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ..._endpoints.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText('  $e',
                    style: const TextStyle(fontFamily: 'monospace')),
              )),
          const SizedBox(height: 24),
          const Text('Claude Code с ПК',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const SelectableText(
            'curl http://<ip>:8080/state\n'
            'curl http://<ip>:8080/screenshot --output screen.png',
            style: TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Сервер слушает только GET и не принимает команд. '
            'Ключи API в /settings замаскированы. '
            'Через Tailscale — доступ вне локальной сети.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

const List<String> _endpoints = [
  '/state',
  '/settings',
  '/logs',
  '/canvas',
  '/theses',
  '/decisions',
  '/websearch',
  '/ips',
  '/screenshot',
];

class _IpTile extends StatelessWidget {
  final String ip;
  final String iface;
  final String kind;
  final int port;

  const _IpTile({
    required this.ip,
    required this.iface,
    required this.kind,
    required this.port,
  });

  @override
  Widget build(BuildContext context) {
    final url = 'http://$ip:$port';
    Color? chipColor;
    if (kind == 'tailscale') chipColor = Colors.teal[100];
    if (iface == 'loopback') chipColor = Colors.grey[300];

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: SelectableText(url,
          style: const TextStyle(fontFamily: 'monospace')),
      subtitle: Text('$iface${kind.isNotEmpty ? ' · $kind' : ''}',
          style: const TextStyle(fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chipColor != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                kind.isNotEmpty ? kind : iface,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Скопировано: $url'),
                    duration: const Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
    );
  }
}
