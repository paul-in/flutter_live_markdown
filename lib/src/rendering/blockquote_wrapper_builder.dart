import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class BlockquoteWrapperBuilder implements ComponentBuilder {
  final List<ComponentBuilder> innerBuilders;

  BlockquoteWrapperBuilder(this.innerBuilders);

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    return null;
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    return null;
  }
}
