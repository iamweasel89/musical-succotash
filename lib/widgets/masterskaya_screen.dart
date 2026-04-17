import 'package:flutter/material.dart';

import '../models/app_model.dart';
import 'cases_screen.dart';
import 'debug_screen.dart';
import 'decision_tree_screen.dart';
import 'excerpt_extractor.dart';
import 'help_screen.dart';
import 'inbox_screen.dart';
import 'razrabotki_screen.dart';
import 'reminders_screen.dart';
import 'thesis_workshop_screen.dart';
import 'web_search_screen.dart';

// ── Мастерская — экран с комнатами ────────────────────────────────────────────

class MasterskayaScreen extends StatelessWidget {
  final AppModel model;
  const MasterskayaScreen({super.key, required this.model});

  static const _excerptText =
      'Это экспериментальный режим извлечения текста.\n\n'
      'Проведите горизонтальный свайп чтобы выделить слова в строке. '
      'Продолжите вертикально чтобы захватить строки ниже или выше. '
      'Отпустите палец — выделение попадёт в буфер внизу.\n\n'
      'Свайп вправо расширяется только вниз. '
      'Свайп влево расширяется только вверх. '
      'Если изменить направление — выделение перестраивается динамически.\n\n'
      'Вертикальный свайп прокручивает текст. '
      'Кнопка со стрелкой отменяет последнее выделение.\n\n'
      'Здесь пока тестовый текст. В финальной версии сюда '
      'будет передаваться содержимое выбранных нод с канваса.\n\n'
      'Первый абзац продолжается. Можно выделять отдельные слова '
      'или целые предложения за один свайп. Длинные тексты '
      'прокручиваются вертикальным жестом без выделения.\n\n'
      'Второй абзац для проверки прокрутки. Текст должен быть '
      'достаточно длинным чтобы не помещаться на экране. '
      'Именно поэтому здесь добавлены дополнительные абзацы.\n\n'
      'Третий абзац. Выделение сохраняется в буфер в нижней части '
      'экрана. Каждый отрывок отображается как чип с кнопкой удаления. '
      'Все отрывки можно скопировать одним нажатием.\n\n'
      'Четвёртый абзац. Попробуйте выделить слова в этом абзаце '
      'после прокрутки к нему. Жест должен работать одинаково '
      'в любом месте текста независимо от позиции прокрутки.\n\n'
      'Пятый абзац. Проверка поворота: свайп вправо от слова в середине '
      'строки захватывает слова вправо, затем при продолжении вниз '
      'захватывает строки ниже. Свайп влево работает симметрично.\n\n'
      'Шестой абзац. Ещё один длинный блок текста для того чтобы '
      'суммарная высота контента превышала высоту экрана '
      'и прокрутка была необходима для достижения этого места.\n\n'
      'Седьмой абзац. Финальный блок тестового контента. '
      'Если вы видите этот текст значит прокрутка работает корректно '
      'и вертикальный жест доставил вас сюда без случайных выделений.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мастерская')),
      body: ListView(
        children: [
          _Room(
            icon: Icons.format_quote_outlined,
            title: 'Извлечение отрывков',
            subtitle: 'Свайп для выбора слов из текста',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ExcerptExtractor(text: _excerptText),
            )),
          ),
          _Room(
            icon: Icons.edit_note_outlined,
            title: 'Режим тезисов',
            subtitle: 'Формулировка и ответы — Я1–Я8',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ThesisWorkshopScreen(model: model),
            )),
          ),
          _Room(
            icon: Icons.account_tree_outlined,
            title: 'Дерево решений',
            subtitle: 'Архитектура, термины, статусы',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DecisionTreeScreen(model: model),
            )),
          ),
          _Room(
            icon: Icons.inbox_outlined,
            title: 'Инбокс',
            subtitle: 'Дампы тезисов и диалогов',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const InboxScreen(),
            )),
          ),
          _Room(
            icon: Icons.travel_explore_outlined,
            title: 'Веб-поиск',
            subtitle: 'Агент с web_search (Tavily / DuckDuckGo)',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WebSearchScreen(model: model),
            )),
          ),
          _Room(
            icon: Icons.help_outline,
            title: 'Справка',
            subtitle: 'Термины: тезис, канва, инбокс, мастерская',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const HelpScreen(),
            )),
          ),
          _Room(
            icon: Icons.bug_report_outlined,
            title: 'Отладка',
            subtitle: 'HTTP-сервер состояния + скриншот для Claude Code',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DebugScreen(model: model),
            )),
          ),
          _Room(
            icon: Icons.construction_outlined,
            title: 'Разработки',
            subtitle: 'Паспорт проекта, бэклог, архитектура',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const RazrabotkiScreen(),
            )),
          ),
          _Room(
            icon: Icons.alarm_outlined,
            title: 'Напоминания',
            subtitle: 'Локальные таймеры с уведомлениями',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RemindersScreen(model: model),
            )),
          ),
          _Room(
            icon: Icons.collections_bookmark_outlined,
            title: 'Кейсы',
            subtitle: 'База проектных решений (cases/ в репо)',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CasesScreen(),
            )),
          ),
        ],
      ),
    );
  }
}

class _Room extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Room({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}
