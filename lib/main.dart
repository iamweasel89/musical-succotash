import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'main_screen.dart';
import 'models/app_model.dart';
import 'services/debug_server.dart';
import 'services/reminder_service.dart';
import 'services/session_tracker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<String>('state');
  SessionTracker.init();
  final model = AppModel();
  await model.load();
  // Fire-and-forget — errors logged internally.
  ReminderService.init();
  if (model.settings.debugServerEnabled) {
    DebugServer.start(model, model.settings.debugServerPort);
  }
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
      // Обёртка вокруг Navigator (не home) — чтобы скриншот захватывал
      // модальные шторки и pushed-экраны, живущие в root Overlay.
      builder: (context, child) => RepaintBoundary(
        key: DebugServer.screenshotKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: MainScreen(model: model),
    );
  }
}

