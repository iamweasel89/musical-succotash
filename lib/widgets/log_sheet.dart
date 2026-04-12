import 'package:flutter/material.dart';
import '../services/logger.dart';

class LogSheet extends StatefulWidget {
  final VoidCallback onDump;
  const LogSheet({super.key, required this.onDump});

  @override
  State<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<LogSheet> {
  late List entries;

  @override
  void initState() {
    super.initState();
    entries = AppLogger.entries.toList();
    AppLogger.addListener(_refresh);
  }

  @override
  void dispose() {
    AppLogger.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => entries = AppLogger.entries.toList());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Log',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('(${entries.length})',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[500])),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('Dump'),
                  onPressed: widget.onDump,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy all'),
                  onPressed: () async {
                    await AppLogger.copyAll();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Log copied to clipboard'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Entries
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text('No log entries yet.',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    controller: ctrl,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      // reverse: true shows newest at bottom
                      final e = entries[entries.length - 1 - i]
                          as dynamic;
                      return _EntryRow(formatted: e.formatted, tag: e.tag);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final String formatted;
  final String tag;

  const _EntryRow({required this.formatted, required this.tag});

  Color _tagColor() {
    switch (tag) {
      case 'API':
        return Colors.red.shade300;
      case 'SLOT':
        return Colors.green.shade600;
      case 'EDGE':
        return Colors.blue.shade400;
      case 'NODE':
        return Colors.orange.shade400;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 14,
            margin: const EdgeInsets.only(top: 2, right: 6),
            decoration: BoxDecoration(
                color: _tagColor(),
                borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Text(
              formatted,
              style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
