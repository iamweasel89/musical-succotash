# Архитектура hex-canvas-mobile — черновик v0.1

**Статус:** черновик. Не утверждено. Ветка `arch/draft`, отдельно от основной разработки. Цель ветки — спроектировать структуру до того как упрёмся в потолок текущей, не ломая живой main.

**Дата:** 2026-04-17
**Автор контекста:** совместная разработка оператор + Claude

---

## 1. Что есть сейчас (текущие слои)

### 1.1 Фактическая организация кода

```
lib/
  models/            — data classes (Node, Edge, Reminder, UsageEvent…)
  services/          — сервисы (api_runner, agent_runner, llm_transform, 
                        llm_client, web_search, reminder_service, 
                        debug_server, session_tracker, dump_service, 
                        logger, updater)
  widgets/           — UI (chat_screen, settings_sheet, 
                        masterskaya_screen, web_search_screen, 
                        thesis_workshop_screen, decision_tree_screen, 
                        reminders_screen, cases_screen, usage_screen, 
                        debug_screen, razrabotki_screen, help_screen, 
                        shared/, settings/)
  canvas/            — canvas_view, hex_canvas_screen, hex_painter, hex_math
  main.dart, main_screen.dart, chat_screen.dart, search_screen.dart
```

### 1.2 Потоки данных

- **UI → AppModel напрямую** (widget.model.theses.add(...) и т.п.)
- **AppModel → Hive через save()/load()** — единственный persistence
- **UI ↔ Services** через прямые вызовы (runApiNode, llmTransform, webSearch)
- **Settings** — глобальный GlobalSettings внутри AppModel
- **ChangeNotifier** как единственный signal state-менеджмент

### 1.3 Persistence

Hive Box<String>, одна «state»-коробка. Всё через JSON-сериализацию. Сущности: nodes, edges, chainPath, canvases, settings, theses, decisions, webSearchMessages, webSearchConfig, reminders, recentUsage, history.

---

## 2. Болевые точки (собраны из опыта)

1. **God-файлы.** `chat_screen.dart` 1367, `settings_sheet.dart` 582 (было 860), `app_model.dart` 640. Любое изменение требует чтения пол-файла.
2. **Прямой доступ к модели из UI.** `widget.model.theses.add(...)` — нет абстракции данных. Любое изменение схемы распространяется на все виджеты.
3. **Три параллельных представления схемы.** Dart-класс + toJson/fromJson + UI-форма — три места при каждом новом поле. Уже был баг (copyFrom не обновлялся при добавлении fields).
4. **Ручная проверка API-контрактов.** Backwards-compat через `j['x'] as bool? ?? false` — есть только в fromJson, но не в UI и не в миграции.
5. **ChangeNotifier тянет весь AppModel.** Изменение тезиса — rebuild виджетов канвы. Неэффективно при росте.
6. **Нет слоёв.** UI → AppModel → Hive. Domain-логика и presentation-логика смешаны в widgets. Сервисы напрямую дёргают модель.
7. **Tests — только на моделях.** Виджеты, логика, интеграция — не покрыты. Refactoring-страшно.
8. **Нет feature-based организации.** Чтобы понять «как работает веб-поиск», надо собрать из `web_search_screen` + `agent_runner` + `web_search` + `web_search_room` + `compress_sheet` — в разных папках.
9. **Settings-флаги растут линейно.** 20+ полей плоским списком. Нет группировки, нет валидации.

---

## 3. Требования к целевой архитектуре

Из опыта + желаний оператора:

1. **Feature-based структура.** Добавить фичу = одна папка, не правки в 8 файлов.
2. **Спецификация как источник истины.** Схема данных → генерит класс + сериализатор + базовый UI-binding.
3. **Domain отделён от UI.** Сервисы и use-cases не зависят от Flutter.
4. **Reactive state по гранулярности.** Подписка на кусочек состояния, не на всё.
5. **Тестируемо.** Domain и services — unit-тестируемы без Flutter-binding.
6. **Переносимость (future-proof).** Подстава для ПМ1 (external memory), МЦ (MCP), БК (multi-thread) не должна требовать переписать UI.

---

## 4. Возможные подходы

### 4.1 Минимальный (Clean-ish)

- Выделить `features/` с под-папками (thesis, web_search, reminders, canvas, chat)
- Внутри фичи: `data/`, `domain/`, `ui/`
- Repository-паттерн: `ThesisRepository` / `WebSearchRepository` — интерфейс, реализация на Hive
- Services остаются как есть
- State: оставить `ChangeNotifier`, но per-feature, не один глобальный

**Плюсы:** минимум миграции, постепенно. Совместимо с текущим кодом.
**Минусы:** не решает вопроса схемы (три параллели остаются).

### 4.2 Средний (freezed + codegen)

- Модели → `freezed` (immutable + copyWith + toJson автоматически)
- Сохраняется AppModel-подобный агрегатор, но на сгенерированных классах
- UI-формы по-прежнему ручные, но сериализация одна точка

**Плюсы:** устраняет параллель Dart+toJson. Один раз напиcал — всё сгенерировалось. Тесты упрощаются.
**Минусы:** генерация требует `build_runner`, дополнительные команды. Не решает UI-binding.

### 4.3 Сильный (Spec-first с UI-binding)

- Схема описана в отдельных YAML/JSON файлах или через Dart-аннотации
- Кодогенерация: класс + сериализатор + базовый UI-биндер (TextField / Switch / Chips по типу поля)
- Settings-экран рисуется **автоматически** из схемы
- Validation встроена в схему

**Плюсы:** радикальное снижение дублирования. Новое поле → правка в одной строке спеки → всё обновляется.
**Минусы:** требует написания генератора (2-3 недели работы). Риск over-engineering. В Flutter готовых хороших решений мало.

### 4.4 Гибрид (рекомендую)

- **Переход на freezed** для всех моделей → устраняет toJson/copyFrom-параллель
- **Repository per feature** → UI через абстракцию, Hive за ней
- **Settings по-прежнему вручную в UI**, НО описание полей — в отдельном реестре (dart-map), чтобы была одна точка добавления
- **State через `ValueNotifier` per feature** (или riverpod-подход если соглашаемся на эту зависимость)
- **Feature-based папки** как организация
- Spec-first — в будущем (отдельная большая работа), не сейчас

---

## 5. Миграционная стратегия

Не all-at-once. Миграция через «пилот»:

1. **Выбрать ОДНУ сущность** для пилота — рекомендую **Reminders** (самая новая, изолированная, мало связей).
2. Применить к ней целевую арх: `features/reminders/{data,domain,ui}` + freezed + Repository.
3. AppModel остаётся — временно хранит старое + делегирует в новое.
4. Оценить: 
   - Писать легче?
   - Тесты проще?
   - Добавить новое поле — сколько правок?
5. Если «да» — мигрировать остальные сущности по очереди (Thesis → WebSearch → Decision → Node).
6. Когда все мигрированы — AppModel распускается, остаётся тонкий агрегатор.

---

## 6. Открытые вопросы

1. **Riverpod или остаёмся на ChangeNotifier?** Riverpod даёт гранулярность + DI, но ещё одна зависимость.
2. **Spec-first сейчас или отложить?** Сейчас — 2-3 недели; отложить — вероятно так и не придём.
3. **Где живёт navigation?** Сейчас все `Navigator.push` разбросаны. Централизовать в router?
4. **Как переходить на feature-папки без долгой заморозки main?** Ответ: через arch-ветку, сливать после пилота.

---

## 7. Следующий шаг

Пилот на **Reminders**:
- Создать `features/reminders/`
- Модель через freezed
- `ReminderRepository` (интерфейс) + `HiveReminderRepository` (реализация)
- `RemindersScreen` читает через репо, не через AppModel
- Проверить: можно ли запустить без AppModel?

Если пилот удаётся — план на остальные фичи. Если нет — пересматриваем подход (вернуться к 4.1 минимальному или 4.3 spec-first).

---

## Связь с backlog

- Р8 (реархитектура) — этот документ её конкретизирует
- Р1, Р4 (god-файлы, sub-managers) — становятся частью миграции, не отдельными задачами
- СП — «Спецификация как источник» — отдельная горизонт-группа, если решим пойти туда
