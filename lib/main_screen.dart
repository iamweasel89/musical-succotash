import 'package:flutter/material.dart';

import 'canvas/canvas_view.dart';
import 'chat_screen.dart';
import 'models/app_model.dart';
import 'widgets/settings_sheet.dart';

class MainScreen extends StatefulWidget {
  final AppModel model;
  const MainScreen({super.key, required this.model});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettingsSheet(
        settings: widget.model.settings,
        onChanged: widget.model.save,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hex Canvas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          ChatScreen(model: widget.model),
          CanvasView(model: widget.model),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.forum), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Canvas'),
        ],
      ),
    );
  }
}

