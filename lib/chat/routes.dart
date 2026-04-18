import 'package:flutter/material.dart';

import '../models/app_model.dart';
import '../widgets/cases_screen.dart';
import '../widgets/debug_screen.dart';
import '../widgets/decision_tree_screen.dart';
import '../widgets/help_screen.dart';
import '../widgets/inbox_screen.dart';
import '../widgets/masterskaya_screen.dart';
import '../widgets/razrabotki_screen.dart';
import '../widgets/reminders_screen.dart';
import '../widgets/thesis_workshop_screen.dart';
import '../widgets/usage_screen.dart';
import '../widgets/web_search_screen.dart';

// Реестр имени-экрана → builder'а. Используется action'ом ui.navigate
// чтобы я (Claude) мог программно открывать любой экран. Для корневых
// вкладок MainScreen (chat/canvas) имена зарезервированы — в stack они
// ставятся через setBaseScreen + switchTab, не через этот реестр.
//
// Как добавить новый экран в реестр: один маппинг здесь. Название совпадает
// с тем что экран передаёт в model.pushScreen(...) — тогда снимок и
// навигация говорят на одном языке.
final Map<String, WidgetBuilder Function(AppModel)> chatRoutes = {
  'masterskaya': (m) => (ctx) => MasterskayaScreen(model: m),
  'web-search': (m) => (ctx) => WebSearchScreen(model: m),
  'thesis-workshop': (m) => (ctx) => ThesisWorkshopScreen(model: m),
  'cases': (m) => (ctx) => const CasesScreen(),
  'decisions': (m) => (ctx) => DecisionTreeScreen(model: m),
  'debug': (m) => (ctx) => DebugScreen(model: m),
  'inbox': (m) => (ctx) => const InboxScreen(),
  'razrabotki': (m) => (ctx) => const RazrabotkiScreen(),
  'reminders': (m) => (ctx) => RemindersScreen(model: m),
  'usage': (m) => (ctx) => UsageScreen(model: m),
  'help': (m) => (ctx) => const HelpScreen(),
};
