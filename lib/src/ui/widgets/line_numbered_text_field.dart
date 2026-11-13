import 'package:flutter/material.dart';

/// A code-editor-style text field featuring a left line-number gutter
/// and active line highlighting.
class LineNumberedTextField extends StatefulWidget {
  final TextEditingController controller;
  final UndoHistoryController? undoController;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final int? activeLineNumber;
  final ValueChanged<String>? onChanged;
  final String? hintText;
  final double gutterWidth;
  final double fontSize;
  final double lineHeight;

  const LineNumberedTextField({
    super.key,
    required this.controller,
    this.undoController,
    this.focusNode,
    this.scrollController,
    this.activeLineNumber,
    this.onChanged,
    this.hintText,
    this.gutterWidth = 38.0,
    this.fontSize = 13.0,
    this.lineHeight = 1.5,
  });

  @override
  State<LineNumberedTextField> createState() => _LineNumberedTextFieldState();
}

class _LineNumberedTextFieldState extends State<LineNumberedTextField> {
  late final ScrollController _textScrollController;
  late final ScrollController _gutterScrollController;
  bool _ownsTextScrollController = false;

  static const double _verticalPadding = 12.0;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _textScrollController = widget.scrollController!;
      _ownsTextScrollController = false;
    } else {
      _textScrollController = ScrollController();
      _ownsTextScrollController = true;
    }
    _gutterScrollController = ScrollController();

    _textScrollController.addListener(_syncGutterScroll);
    widget.controller.addListener(_handleTextChanged);
  }

  void _syncGutterScroll() {
    if (_gutterScrollController.hasClients &&
        _textScrollController.hasClients) {
      final target = _textScrollController.offset.clamp(
        0.0,
        _gutterScrollController.position.maxScrollExtent,
      );
      if (_gutterScrollController.offset != target) {
        _gutterScrollController.jumpTo(target);
      }
    }
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _textScrollController.removeListener(_syncGutterScroll);
    widget.controller.removeListener(_handleTextChanged);
    if (_ownsTextScrollController) {
      _textScrollController.dispose();
    }
    _gutterScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final text = widget.controller.text;
    final lines = text.split('\n');
    final lineCount = lines.isEmpty ? 1 : lines.length;
    final singleLineHeight = widget.fontSize * widget.lineHeight;

    final gutterBg = isDark ? const Color(0xFF18181D) : const Color(0xFFE9ECEF);
    final borderColor = theme.dividerColor.withValues(alpha: 25 / 100);

    final strutStyle = StrutStyle(
      fontFamily: 'monospace',
      fontSize: widget.fontSize,
      height: widget.lineHeight,
      forceStrutHeight: true,
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121214) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Gutter
          Container(
            width: widget.gutterWidth,
            decoration: BoxDecoration(
              color: gutterBg,
              border: Border(right: BorderSide(color: borderColor)),
            ),
            child: ListView.builder(
              controller: _gutterScrollController,
              padding: const EdgeInsets.only(
                top: _verticalPadding,
                bottom: _verticalPadding,
              ),
              itemCount: lineCount,
              itemExtent: singleLineHeight,
              itemBuilder: (context, index) {
                final lineNum = index + 1;
                final isActive = widget.activeLineNumber == lineNum;

                return Container(
                  key: ValueKey(
                    isActive
                        ? 'gutter_line_active_$lineNum'
                        : 'gutter_line_$lineNum',
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? theme.colorScheme.primary.withValues(alpha: 18 / 100)
                        : Colors.transparent,
                    border: isActive
                        ? Border(
                            right: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 2.5,
                            ),
                          )
                        : null,
                  ),
                  child: Text(
                    '$lineNum',
                    key: ValueKey('gutter_line_number_$lineNum'),
                    strutStyle: strutStyle,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: widget.fontSize,
                      height: widget.lineHeight,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.hintColor.withValues(alpha: 50 / 100),
                    ),
                  ),
                );
              },
            ),
          ),

          // Right Text Field
          Expanded(
            child: TextField(
              key: const ValueKey('studio_convention_editor_field'),
              controller: widget.controller,
              undoController: widget.undoController,
              focusNode: widget.focusNode,
              scrollController: _textScrollController,
              enableInteractiveSelection: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              strutStyle: strutStyle,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: widget.fontSize,
                height: widget.lineHeight,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: widget.fontSize - 1,
                  color: theme.hintColor.withValues(alpha: 60 / 100),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: _verticalPadding,
                ),
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
