import 'package:flutter/material.dart';

import '../models/app_model.dart';

// ── Комната: Режим тезисов (Я1–Я8) ───────────────────────────────────────────

class ThesisWorkshopScreen extends StatelessWidget {
  final AppModel model;
  const ThesisWorkshopScreen({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Режим тезисов')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note_outlined, size: 48, color: Colors.deepPurple),
              SizedBox(height: 16),
              Text(
                'В разработке',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Здесь будет тестовый стенд для режима тезисов:\n'
                'формулировка через LLM, ответы, история вариантов.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
