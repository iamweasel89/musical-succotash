import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'main_screen.dart';
import 'models/app_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<String>('state');
  final model = AppModel()..load();
  runApp(HexCanvasApp(model: model));
}

class HexCanvasApp extends StatelessWidget {
  final AppModel model;
  const HexCanvasApp({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hex Canvas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: MainScreen(model: model),
    );
  }
}

