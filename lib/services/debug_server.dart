import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'settings.dart';
import 'vault.dart';

/// Tiny HTTP server that exposes the vault for external (debug) access.
/// Binds to 0.0.0.0 so it is reachable over any interface the device has
/// (local Wi-Fi, Tailscale, etc). Auth is a single header `X-Debug-Token`.
class DebugServer {
  final Vault vault;
  HttpServer? _server;
  String? _boundUri;

  DebugServer(this.vault);

  String? get boundUri => _boundUri;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final port = await Settings.getDebugPort();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    _boundUri = 'http://0.0.0.0:$port';
    server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _boundUri = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final token = await Settings.getDebugToken();
      final given = req.headers.value('x-debug-token') ?? '';
      if (token.isEmpty || given != token) {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
      final path = req.uri.path;
      final method = req.method;

      if (method == 'GET' && path == '/vault/list') {
        await _list(req);
        return;
      }
      if (method == 'GET' && path.startsWith('/vault/atoms/')) {
        final id = path.substring('/vault/atoms/'.length);
        await _readAtom(req, id);
        return;
      }
      if (method == 'GET' && path.startsWith('/vault/moves/')) {
        final id = path.substring('/vault/moves/'.length);
        await _readMove(req, id);
        return;
      }
      if (method == 'POST' && path == '/vault/prompt') {
        await _prompt(req);
        return;
      }
      if (method == 'POST' && path == '/vault/atoms') {
        await _writeAtom(req);
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    } catch (e) {
      try {
        req.response.statusCode = 500;
        req.response.write(jsonEncode({'error': e.toString()}));
      } catch (_) {}
      await req.response.close();
    }
  }

  Future<void> _list(HttpRequest req) async {
    final atoms = await vault.listAtoms();
    final moves = await vault.listMoves();
    final body = jsonEncode({
      'atoms': atoms.map((f) => f.path.split('/').last).toList(),
      'moves': moves.map((f) => f.path.split('/').last).toList(),
    });
    req.response
      ..headers.contentType = ContentType.json
      ..write(body);
    await req.response.close();
  }

  Future<void> _readAtom(HttpRequest req, String id) async {
    final name = id.endsWith('.md') ? id : '$id.md';
    final f = File('${vault.root.path}/$name');
    if (!await f.exists()) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response
      ..headers.contentType = ContentType('text', 'markdown')
      ..write(await f.readAsString());
    await req.response.close();
  }

  Future<void> _readMove(HttpRequest req, String id) async {
    final name = id.endsWith('.md') ? id : '$id.md';
    final f = File('${vault.moves.path}/$name');
    if (!await f.exists()) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response
      ..headers.contentType = ContentType('text', 'markdown')
      ..write(await f.readAsString());
    await req.response.close();
  }

  Future<void> _prompt(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final prompt = body['prompt'] as String? ?? '';
    if (prompt.isEmpty) {
      req.response.statusCode = 400;
      req.response.write(jsonEncode({'error': 'prompt is empty'}));
      await req.response.close();
      return;
    }
    final apiKey = await Settings.getApiKey();
    if (apiKey.isEmpty) {
      req.response.statusCode = 400;
      req.response.write(jsonEncode({'error': 'api key not set'}));
      await req.response.close();
      return;
    }
    final model = await Settings.getModel();
    final maxTokens = await Settings.getMaxTokens();
    final result = await vault.runMove(
      apiKey: apiKey,
      model: model,
      maxTokens: maxTokens,
      prompt: prompt,
    );
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'prompt_id': result.promptId,
        'response_id': result.responseId,
        'move_id': result.moveId,
        'tokens_in': result.tokensIn,
        'tokens_out': result.tokensOut,
      }));
    await req.response.close();
  }

  Future<void> _writeAtom(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final type = body['type'] as String? ?? 'note';
    final text = body['body'] as String? ?? '';
    if (text.isEmpty) {
      req.response.statusCode = 400;
      req.response.write(jsonEncode({'error': 'body is empty'}));
      await req.response.close();
      return;
    }
    final id = await vault.writeAtom(type: type, body: text);
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'id': id}));
    await req.response.close();
  }
}
