import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../models/app_model.dart';
import '../models/settings.dart';
import 'logger.dart';

// ── Debug HTTP server ────────────────────────────────────────────────────────
// Read-only introspection of app state. Toggled via settings (Мастерская →
// Отладка). Binds on 0.0.0.0 so it's reachable via LAN + Tailscale.
//
// Endpoints (GET):
//   /state        — JSON summary (route hint, counts, active canvas)
//   /settings     — settings JSON (API keys masked)
//   /logs         — AppLogger entries
//   /canvas       — active canvas: nodes, edges, chainPath
//   /theses       — thesis list
//   /decisions    — decision tree
//   /websearch    — web search room history
//   /ips          — local interfaces the server binds to
//   /screenshot   — PNG of current root widget
//   /             — help page with endpoint list

class DebugServer {
  static final GlobalKey screenshotKey = GlobalKey();

  static HttpServer? _server;
  static AppModel? _model;
  static final List<void Function()> _listeners = [];

  static bool get isRunning => _server != null;
  static int get port => _server?.port ?? 0;

  static void addListener(void Function() fn) => _listeners.add(fn);
  static void removeListener(void Function() fn) => _listeners.remove(fn);
  static void _notify() {
    for (final fn in List.of(_listeners)) {
      try {
        fn();
      } catch (_) {}
    }
  }

  static Future<void> start(AppModel model, int desiredPort) async {
    if (_server != null) return;
    _model = model;
    try {
      _server =
          await HttpServer.bind(InternetAddress.anyIPv4, desiredPort, shared: true);
      AppLogger.log('debug', 'server bound on :${_server!.port}');
      _server!.listen(_handle);
      _notify();
    } catch (e) {
      AppLogger.log('debug', 'bind failed: $e');
      _server = null;
      _notify();
      rethrow;
    }
  }

  static Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
    AppLogger.log('debug', 'server stopped');
    _notify();
  }

  // ── Request dispatch ──────────────────────────────────────────────────────

  static Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    try {
      switch (path) {
        case '/':
          _html(req, _indexHtml());
        case '/state':
          _json(req, await _state());
        case '/settings':
          _json(req, _settings());
        case '/logs':
          _json(req, _logs());
        case '/canvas':
          _json(req, _canvas());
        case '/theses':
          _json(req, _theses());
        case '/decisions':
          _json(req, _decisions());
        case '/websearch':
          _json(req, _webSearch());
        case '/ips':
          _json(req, await currentIps());
        case '/screenshot':
          await _screenshot(req);
        default:
          req.response.statusCode = 404;
          await req.response.close();
      }
    } catch (e) {
      req.response.statusCode = 500;
      req.response.write('error: $e');
      await req.response.close();
    }
  }

  static void _json(HttpRequest req, Object data) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
      ..write(const JsonEncoder.withIndent('  ').convert(data));
    req.response.close();
  }

  static void _html(HttpRequest req, String body) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(body);
    req.response.close();
  }

  // ── Endpoint payloads ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _state() async {
    final m = _model!;
    return {
      'app': 'hex-canvas-mobile',
      'activeCanvas': {
        'id': m.activeCanvasId,
        'name': m.activeCanvas.name,
        'nodeCount': m.activeCanvasNodes.length,
        'edgeCount': m.activeCanvasEdges.length,
      },
      'counts': {
        'canvases': m.canvases.length,
        'nodes': m.nodes.length,
        'edges': m.edges.length,
        'theses': m.theses.length,
        'decisions': m.decisions.length,
        'webSearchMessages': m.webSearchMessages.length,
      },
      'chainPathLength': m.chainPath.length,
      'canUndo': m.canUndo,
      'canRedo': m.canRedo,
      'debugMode': kDebugMode,
    };
  }

  static Map<String, dynamic> _settings() {
    final s = _model!.settings;
    String mask(String v) => v.isEmpty
        ? ''
        : (v.length <= 8 ? '••••' : '${v.substring(0, 4)}••••${v.substring(v.length - 4)}');
    return {
      'anthropicKey': mask(s.anthropicKey),
      'openAiKey': mask(s.openAiKey),
      'deepSeekKey': mask(s.deepSeekKey),
      'tavilyKey': mask(s.tavilyKey),
      'defaultProvider': s.defaultProvider,
      'defaultModel': s.defaultModel,
      'streamingMode': s.streamingMode,
      'renderMarkdown': s.renderMarkdown,
      'hideEmoji': s.hideEmoji,
      'showBubbleTime': s.showBubbleTime,
      'showBubbleId': s.showBubbleId,
      'hideThesisButton': s.hideThesisButton,
      'compactChat': s.compactChat,
      'compactLines': s.compactLines,
      'debugServerEnabled': s.debugServerEnabled,
      'debugServerPort': s.debugServerPort,
    };
  }

  static Map<String, dynamic> _logs() => {
        'entries':
            AppLogger.entries.map((e) => {'line': e.formatted}).toList(),
      };

  static Map<String, dynamic> _canvas() {
    final m = _model!;
    return {
      'active': m.activeCanvas.toJson(),
      'nodes': m.activeCanvasNodes.map((n) => n.toJson()).toList(),
      'edges': m.activeCanvasEdges.map((e) => e.toJson()).toList(),
      'chainPath': m.chainPath,
    };
  }

  static Map<String, dynamic> _theses() => {
        'items': _model!.theses.map((t) => t.toJson()).toList(),
      };

  static Map<String, dynamic> _decisions() => {
        'items': _model!.decisions.map((d) => d.toJson()).toList(),
      };

  static Map<String, dynamic> _webSearch() {
    final m = _model!;
    return {
      'config': m.webSearchConfig.toJson(),
      'messages': m.webSearchMessages.map((mm) => mm.toJson()).toList(),
    };
  }

  // ── Screenshot ────────────────────────────────────────────────────────────

  static Future<void> _screenshot(HttpRequest req) async {
    final ctx = screenshotKey.currentContext;
    if (ctx == null) {
      req.response.statusCode = 503;
      req.response.write('no render context yet');
      await req.response.close();
      return;
    }
    final boundary = ctx.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      req.response.statusCode = 500;
      req.response.write('root is not RenderRepaintBoundary');
      await req.response.close();
      return;
    }
    final dpr = req.uri.queryParameters['dpr'];
    final pixelRatio = double.tryParse(dpr ?? '') ?? 2.0;
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      req.response.statusCode = 500;
      req.response.write('encode failed');
      await req.response.close();
      return;
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType('image', 'png')
      ..add(Uint8List.view(bytes.buffer));
    await req.response.close();
  }

  // ── IP enumeration ────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> currentIps() async {
    final out = <Map<String, dynamic>>[];
    out.add({'iface': 'loopback', 'ip': '127.0.0.1'});
    try {
      final ifaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          final tag = ip.startsWith('100.') ? 'tailscale' : 'lan';
          out.add({'iface': iface.name, 'ip': ip, 'kind': tag});
        }
      }
    } catch (_) {}
    return out;
  }

  // ── Index page ────────────────────────────────────────────────────────────

  static String _indexHtml() {
    return '''
<!doctype html>
<meta charset="utf-8">
<title>hex-canvas debug</title>
<style>body{font-family:monospace;padding:20px;line-height:1.6}a{color:#06f}</style>
<h2>hex-canvas-mobile debug</h2>
<ul>
  <li><a href="/state">/state</a></li>
  <li><a href="/settings">/settings</a></li>
  <li><a href="/logs">/logs</a></li>
  <li><a href="/canvas">/canvas</a></li>
  <li><a href="/theses">/theses</a></li>
  <li><a href="/decisions">/decisions</a></li>
  <li><a href="/websearch">/websearch</a></li>
  <li><a href="/ips">/ips</a></li>
  <li><a href="/screenshot">/screenshot</a> (png)</li>
</ul>
''';
  }
}
