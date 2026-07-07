import 'package:flutter/foundation.dart';

class LiveMarkdownController extends ChangeNotifier {
  String _text = '';

  String get text => _text;

  VoidCallback? onChange;
  VoidCallback? onReloadRequested;

  LiveMarkdownController({String? initialMarkdown}) {
    if (initialMarkdown != null) {
      _text = initialMarkdown;
    }
  }

  /// Public API: replace all content and reinitialize the editor.
  void replaceContent(String markdown) {
    _text = markdown;
    onReloadRequested?.call();
    notifyListeners();
    onChange?.call();
  }

  /// Internal: sync _text from the editor without reinitializing.
  void syncFromDocument(String markdown) {
    if (_text == markdown) return;
    _text = markdown;
    notifyListeners();
    onChange?.call();
  }
}
