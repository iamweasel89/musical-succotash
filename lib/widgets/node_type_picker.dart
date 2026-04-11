import 'package:flutter/material.dart';
import '../models/node.dart';

class NodeTypePicker extends StatelessWidget {
  const NodeTypePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Create node',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF2196F3),
                child: Icon(Icons.text_fields, color: Colors.white, size: 20),
              ),
              title: const Text('Text Node'),
              subtitle: const Text('Store and edit text'),
              onTap: () => Navigator.pop(context, NodeType.text),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF44336),
                child: Icon(Icons.api, color: Colors.white, size: 20),
              ),
              title: const Text('API Node'),
              subtitle: const Text('Call LLM provider'),
              onTap: () => Navigator.pop(context, NodeType.api),
            ),
          ],
        ),
      ),
    );
  }
}
