import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live_markdown/live_markdown.dart';

void main() {
  testWidgets('Controller can be created and content replaced', (WidgetTester tester) async {
    final controller = LiveMarkdownController(initialMarkdown: '# Hello');
    expect(controller.text, '# Hello');

    controller.replaceContent('New **content**');
    expect(controller.text, 'New **content**');
  });

  testWidgets('Controller getContentBetween returns substring', (WidgetTester tester) async {
    final controller = LiveMarkdownController(initialMarkdown: 'Hello **bold** world');
    expect(controller.getContentBetween(6, 10), '**bo');
  });
}
