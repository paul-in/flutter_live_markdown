import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class TableWrapperBuilder implements ComponentBuilder {
  final Document document;
  final List<ComponentBuilder> innerBuilders;

  TableWrapperBuilder(this.document, this.innerBuilders);

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    return null;
  }

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context, SingleColumnLayoutComponentViewModel viewModel) {
    final node = document.getNodeById(viewModel.nodeId);
    if (node == null || node.metadata['isTable'] != true) {
      return null;
    }

    Widget? innerWidget;
    for (final builder in innerBuilders) {
      innerWidget = builder.createComponent(context, viewModel);
      if (innerWidget != null) break;
    }
    if (innerWidget == null) return null;

    final rawText = (node as TextNode).text.toPlainText();
    final tempDoc = deserializeMarkdownToDocument(rawText);
    if (tempDoc.isEmpty || tempDoc.first is! TableBlockNode) {
      return innerWidget;
    }

    final tableNode = tempDoc.first as TableBlockNode;
    const tableBuilder = MarkdownTableComponentBuilder();
    final tableViewModel = tableBuilder.createViewModel(tempDoc, tableNode);
    if (tableViewModel == null) return innerWidget;

    if (tableViewModel is MarkdownTableViewModel) {
      tableViewModel.applyStyles({
        Styles.textStyle: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          height: 1.5,
        ),
        Styles.inlineTextStyler: defaultInlineTextStyler,
        TableStyles.cellPadding: const CascadingPadding.all(8),
      });
    }

    final dummyContext = SingleColumnDocumentComponentContext(
      context: context.context,
      componentKey: GlobalKey(),
    );
    final tableWidget = tableBuilder.createComponent(dummyContext, tableViewModel);
    if (tableWidget == null) return innerWidget;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          SizedBox(
            width: double.infinity,
            child: tableWidget,
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: innerWidget,
            ),
          ),
        ],
      ),
    );
  }
}
