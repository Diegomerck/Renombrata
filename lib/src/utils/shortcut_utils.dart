import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ShortcutUtils {
  static const Map<String, String> actionLabels = {
    'new_take': 'Nueva Toma',
    'duplicate_take': 'Duplicar Toma',
    'stamp_cut': 'Marcar Corte',
    'undo_delete': 'Deshacer Eliminación',
    'save_project': 'Guardar Proyecto',
  };

  static const Map<String, String> actionDescriptions = {
    'new_take': 'Crear una nueva toma vacía',
    'duplicate_take': 'Duplica la última toma incrementando el número',
    'stamp_cut': 'Estampa el código de tiempo actual en TC Out de la última toma',
    'undo_delete': 'Restaurar las últimas tomas eliminadas',
    'save_project': 'Guardar el proyecto en disco',
  };

  static const List<String> availableKeys = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12',
  ];

  static LogicalKeyboardKey? keyFromName(String name) {
    final upper = name.trim().toUpperCase();
    if (upper.length == 1) {
      final code = upper.codeUnitAt(0);
      if (code >= 'A'.codeUnitAt(0) && code <= 'Z'.codeUnitAt(0)) {
        final offset = code - 'A'.codeUnitAt(0);
        return LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + offset);
      }
      if (code >= '0'.codeUnitAt(0) && code <= '9'.codeUnitAt(0)) {
        final offset = code - '0'.codeUnitAt(0);
        return LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + offset);
      }
    }
    switch (upper) {
      case 'F1':
        return LogicalKeyboardKey.f1;
      case 'F2':
        return LogicalKeyboardKey.f2;
      case 'F3':
        return LogicalKeyboardKey.f3;
      case 'F4':
        return LogicalKeyboardKey.f4;
      case 'F5':
        return LogicalKeyboardKey.f5;
      case 'F6':
        return LogicalKeyboardKey.f6;
      case 'F7':
        return LogicalKeyboardKey.f7;
      case 'F8':
        return LogicalKeyboardKey.f8;
      case 'F9':
        return LogicalKeyboardKey.f9;
      case 'F10':
        return LogicalKeyboardKey.f10;
      case 'F11':
        return LogicalKeyboardKey.f11;
      case 'F12':
        return LogicalKeyboardKey.f12;
      case 'SPACE':
        return LogicalKeyboardKey.space;
      case 'ENTER':
        return LogicalKeyboardKey.enter;
      case 'ESCAPE':
        return LogicalKeyboardKey.escape;
      case 'DELETE':
        return LogicalKeyboardKey.delete;
      case 'BACKSPACE':
        return LogicalKeyboardKey.backspace;
      default:
        return null;
    }
  }

  /// Parses a shortcut string into activators.
  /// If the shortcut includes 'Ctrl' (or 'Cmd'), returns activators with both
  /// control: true and meta: true to support Windows/Linux and macOS seamlessly.
  static List<ShortcutActivator> parseActivators(String shortcutStr) {
    if (shortcutStr.trim().isEmpty) return const [];
    final parts = shortcutStr.split('+').map((s) => s.trim()).toList();
    if (parts.isEmpty) return const [];

    bool hasCtrl = false;
    bool hasCmd = false;
    bool hasAlt = false;
    bool hasShift = false;
    LogicalKeyboardKey? targetKey;

    for (final part in parts) {
      final lower = part.toLowerCase();
      if (lower == 'ctrl' || lower == 'control') {
        hasCtrl = true;
      } else if (lower == 'cmd' || lower == 'command' || lower == 'meta') {
        hasCmd = true;
      } else if (lower == 'alt' || lower == 'option') {
        hasAlt = true;
      } else if (lower == 'shift') {
        hasShift = true;
      } else {
        targetKey = keyFromName(part);
      }
    }

    if (targetKey == null) return const [];

    final result = <ShortcutActivator>[];
    if (hasCtrl && !hasCmd) {
      result.add(SingleActivator(targetKey, control: true, alt: hasAlt, shift: hasShift));
      result.add(SingleActivator(targetKey, meta: true, alt: hasAlt, shift: hasShift));
    } else if (hasCmd && !hasCtrl) {
      result.add(SingleActivator(targetKey, meta: true, alt: hasAlt, shift: hasShift));
      result.add(SingleActivator(targetKey, control: true, alt: hasAlt, shift: hasShift));
    } else {
      result.add(SingleActivator(
        targetKey,
        control: hasCtrl,
        meta: hasCmd,
        alt: hasAlt,
        shift: hasShift,
      ));
    }
    return result;
  }
}
