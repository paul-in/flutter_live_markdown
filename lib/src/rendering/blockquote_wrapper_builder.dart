import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import '../model/markdown_node_metadata.dart';

class BlockquoteWrapperBuilder implements ComponentBuilder {
  final Document document;
  final List<ComponentBuilder> innerBuilders;

  BlockquoteWrapperBuilder(this.document, this.innerBuilders);

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    return null;
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    final node = document.getNodeById(viewModel.nodeId);
    if (node == null) return null;

    final meta = MarkdownNodeMetadata.fromNode(node);
    if (!meta.isBlockquote) return null;

    Widget? innerWidget;
    for (final builder in innerBuilders) {
      innerWidget = builder.createComponent(context, viewModel);
      if (innerWidget != null) break;
    }

    if (innerWidget == null) return null;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.grey.shade300, width: 4),
        ),
      ),
      padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
      child: innerWidget,
    );
  }
}
