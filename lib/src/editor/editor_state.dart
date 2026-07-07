import 'package:super_editor/super_editor.dart';

class EditorState {
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;
  late final ScrollController scrollController;

  void initializeFromMarkdown(String raw) {
    document = MutableDocument(nodes: []);
    composer = MutableDocumentComposer();
    scrollController = ScrollController();
    final editableMap = <String, Editable>{
      Editor.documentKey: document,
      Editor.composerKey: composer,
    };
    editor = Editor(
      editables: editableMap,
      requestHandlers: [...defaultRequestHandlers],
      isHistoryEnabled: true,
    );
  }

  void rebuild() {
    dispose();
    initializeFromMarkdown('');
  }

  void dispose() {
    document.dispose();
    composer.dispose();
    editor.dispose();
    scrollController.dispose();
  }
}
