import 'package:flutter/services.dart';

class AppLogger {
  static const int _maxEntries = 200;
  static final List<_LogEntry> _entries = [];
  static final List<void Function()> _listeners = [];

  static void log(String tag, String message) {
    final entry = _LogEntry(
      time: DateTime.now(),
      tag: tag,
      message: message,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    for (final fn in _listeners) {
      fn();
    }
  }

  static List<_LogEntry> get entries => List.unmodifiable(_entries);

  static void addListener(void Function() fn) => _listeners.add(fn);
  static void removeListener(void Function() fn) => _listeners.remove(fn);

  static Future<void> copyAll() async {
    final buf = StringBuffer();
    for (final e in _entries) {
      buf.writeln(e.formatted);
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
  }
}

class _LogEntry {
  final DateTime time;
  final String tag;
  final String message;

  const _LogEntry(
      {required this.time, required this.tag, required this.message});

  String get formatted {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s [$tag] $message';
  }
}
