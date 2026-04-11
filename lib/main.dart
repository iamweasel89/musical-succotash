import 'package:flutter/material.dart';
import 'canvas/hex_canvas_screen.dart';

void main() {
  runApp(const HexCanvasApp());
}

class HexCanvasApp extends StatelessWidget {
  const HexCanvasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hex Canvas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const HexCanvasScreen(),
    );
  }
}
