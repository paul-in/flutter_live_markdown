import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class ImageWrapperBuilder implements ComponentBuilder {
  final Document document;
  final List<ComponentBuilder> innerBuilders;

  ImageWrapperBuilder(this.document, this.innerBuilders);

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    return null;
  }

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext context, SingleColumnLayoutComponentViewModel viewModel) {
    final node = document.getNodeById(viewModel.nodeId);
    if (node == null || node.metadata['isImage'] != true) {
      return null;
    }

    Widget? innerWidget;
    for (final builder in innerBuilders) {
      innerWidget = builder.createComponent(context, viewModel);
      if (innerWidget != null) break;
    }
    if (innerWidget == null) return null;

    final imageUrl = node.metadata['imageUrl'] as String?;
    if (imageUrl == null) return innerWidget;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Image.network(imageUrl),
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
