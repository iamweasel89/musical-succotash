import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'canvas/hex_canvas_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<String>('state');
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
