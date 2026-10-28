import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/utils/shortcut_utils.dart';

void main() {
  group('ShortcutUtils Tests', () {
    test('keyFromName correctly resolves keys', () {
      expect(ShortcutUtils.keyFromName('A'), LogicalKeyboardKey.keyA);
      expect(ShortcutUtils.keyFromName('z'), LogicalKeyboardKey.keyZ);
      expect(ShortcutUtils.keyFromName('0'), LogicalKeyboardKey.digit0);
      expect(ShortcutUtils.keyFromName('9'), LogicalKeyboardKey.digit9);
      expect(ShortcutUtils.keyFromName('F1'), LogicalKeyboardKey.f1);
      expect(ShortcutUtils.keyFromName('f12'), LogicalKeyboardKey.f12);
      expect(ShortcutUtils.keyFromName('SPACE'), LogicalKeyboardKey.space);
      expect(ShortcutUtils.keyFromName('ENTER'), LogicalKeyboardKey.enter);
      expect(ShortcutUtils.keyFromName('UNKNOWN_KEY'), isNull);
    });

    test('parseActivators generates cross-platform activators for Ctrl combinations', () {
      final activators = ShortcutUtils.parseActivators('Ctrl+N').whereType<SingleActivator>().toList();
      expect(activators.length, 2);
      expect(activators.any((a) => a.trigger == LogicalKeyboardKey.keyN && a.control), isTrue);
      expect(activators.any((a) => a.trigger == LogicalKeyboardKey.keyN && a.meta), isTrue);
    });

    test('parseActivators handles modifiers like Alt and Shift', () {
      final activators = ShortcutUtils.parseActivators('Ctrl+Shift+D').whereType<SingleActivator>().toList();
      expect(activators.length, 2);
      expect(activators.any((a) => a.trigger == LogicalKeyboardKey.keyD && a.control && a.shift), isTrue);
      expect(activators.any((a) => a.trigger == LogicalKeyboardKey.keyD && a.meta && a.shift), isTrue);
    });

    test('parseActivators handles function keys without modifiers', () {
      final activators = ShortcutUtils.parseActivators('F5').whereType<SingleActivator>().toList();
      expect(activators.length, 1);
      expect(activators.first.trigger, LogicalKeyboardKey.f5);
      expect(activators.first.control, isFalse);
      expect(activators.first.alt, isFalse);
      expect(activators.first.shift, isFalse);
    });

    test('parseActivators returns empty for invalid shortcut string', () {
      expect(ShortcutUtils.parseActivators(''), isEmpty);
      expect(ShortcutUtils.parseActivators('InvalidKeyName'), isEmpty);
    });

    test('actionLabels and actionDescriptions covers all default shortcut actions', () {
      for (final key in AppSettings.defaultShortcuts.keys) {
        expect(ShortcutUtils.actionLabels.containsKey(key), isTrue);
        expect(ShortcutUtils.actionDescriptions.containsKey(key), isTrue);
      }
    });
  });
}
