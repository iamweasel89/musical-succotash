import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'models/app_model.dart';

class MainScreen extends StatefulWidget {
  final AppModel model;
  const MainScreen({super.key, required this.model});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          ChatScreen(model: widget.model),
          const _CanvasPlaceholder(),
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

class _CanvasPlaceholder extends StatelessWidget {
  const _CanvasPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Canvas', style: TextStyle(color: Colors.grey, fontSize: 16)),
    );
  }
}
