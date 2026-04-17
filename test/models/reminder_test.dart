import 'package:flutter_test/flutter_test.dart';

import 'package:hex_canvas_mobile/models/reminder.dart';

void main() {
  test('Reminder round-trip через JSON', () {
    final original = Reminder(
      scheduledAt: DateTime(2026, 5, 1, 14, 30),
      text: 'Перезвонить Максу',
      linkedNodeId: 'node123',
    );
    final json = original.toJson();
    final restored = Reminder.fromJson(json);

    expect(restored.id, original.id);
    expect(restored.nativeId, original.nativeId);
    expect(restored.text, original.text);
    expect(restored.scheduledAt, original.scheduledAt);
    expect(restored.linkedNodeId, original.linkedNodeId);
    expect(restored.done, original.done);
  });

  test('Reminder без linkedNodeId', () {
    final r = Reminder(
      scheduledAt: DateTime(2026, 1, 1),
      text: 'таймер',
    );
    final restored = Reminder.fromJson(r.toJson());
    expect(restored.linkedNodeId, isNull);
    expect(restored.done, false);
  });

  test('Reminder.nativeId в допустимом int-диапазоне для Android NotificationId', () {
    for (int i = 0; i < 100; i++) {
      final r = Reminder(
        scheduledAt: DateTime.now(),
        text: 'x',
      );
      expect(r.nativeId, greaterThanOrEqualTo(0));
      expect(r.nativeId, lessThan(1 << 31));
    }
  });

  test('Reminder сохраняет done=true через JSON', () {
    final r = Reminder(
      scheduledAt: DateTime(2026, 5, 1),
      text: 'x',
      done: true,
    );
    final restored = Reminder.fromJson(r.toJson());
    expect(restored.done, true);
  });
}
