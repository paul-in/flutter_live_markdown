import 'package:super_editor/super_editor.dart';

import '../model/markdown_block.dart';
import '../model/markdown_node_metadata.dart';
import '../parsing/markdown_splitter.dart';
import 'editor_state.dart';

class NodeReconciliationReaction extends EditReaction {
  final EditorState editorState;

  NodeReconciliationReaction({required this.editorState});

  @override
  void modifyContent(EditContext context, RequestDispatcher requestDispatcher, List<EditEvent> changes) {
    final document = context.find(Editor.documentKey) as MutableDocument;
    final composer = context.find(Editor.composerKey) as MutableDocumentComposer;

    bool needsReconciliation = false;
    for (final event in changes) {
      if (event is NodeChangeEvent || event is NodeInsertedEvent) {
        needsReconciliation = true;
        break;
      }
    }

    if (!needsReconciliation) return;

    _reconcileNodes(document, composer, requestDispatcher);
  }

  void _reconcileNodes(
    MutableDocument document,
    MutableDocumentComposer composer,
    RequestDispatcher requestDispatcher,
  ) {
    final selection = composer.selection;
    final requests = <EditRequest>[];
    final nodesList = document.toList();
    int i = 0;

    while (i < nodesList.length) {
      final node = nodesList[i];

      if (node is TextNode) {
        final meta = MarkdownNodeMetadata.fromNode(node);

        if (meta.isRawMode) {
          final raw = node.text.toPlainText();
          final blocks = splitMarkdownIntoBlocks(raw);

          if (blocks.length > 1) {
            // Multi-block content in raw mode → split
            requests.add(DeleteNodeRequest(nodeId: node.id));
            int insertIndex = i;

            for (final block in blocks) {
              final newNode = _createNodeFromBlock(block, true);
              if (newNode != null) {
                requests.add(InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: newNode));

                if (selection != null && selection.extent.nodeId == node.id) {
                  final oldOffset = (selection.extent.nodePosition as TextNodePosition).offset;
                  if (oldOffset >= block.startOffset && oldOffset <= block.endOffset) {
                    final newOffset = oldOffset - block.startOffset;
                    requests.add(ChangeSelectionRequest(
                      DocumentSelection.collapsed(
                        position: DocumentPosition(
                          nodeId: newNode.id,
                          nodePosition: TextNodePosition(offset: newOffset),
                        ),
                      ),
                      SelectionChangeType.placeCaret,
                      SelectionReason.userInteraction,
                    ));
                  }
                }
                insertIndex++;
              }
            }
            break;
          }
        } else if (!node.metadata.containsKey('rawMarkdown')) {
          // Naked node (from paste, drag&drop) — needs reconciliation
          final group = <TextNode>[];
          int j = i;
          while (j < nodesList.length) {
            final n = nodesList[j];
            if (n is TextNode && !n.metadata.containsKey('rawMarkdown')) {
              group.add(n);
              j++;
            } else {
              break;
            }
          }

          final reconstructedRaw = group.map((n) => n.text.toPlainText()).join('\n');
          final blocks = splitMarkdownIntoBlocks(reconstructedRaw);

          if (blocks.isEmpty) {
            for (final _ in group) {
              blocks.add(MarkdownBlock('', 0, 0));
            }
          }

          for (final n in group) {
            requests.add(DeleteNodeRequest(nodeId: n.id));
          }

          int? globalOldOffset;
          if (selection != null) {
            for (int g = 0; g < group.length; g++) {
              if (group[g].id == selection.extent.nodeId) {
                globalOldOffset = 0;
                for (int k = 0; k < g; k++) {
                  globalOldOffset = globalOldOffset! + group[k].text.toPlainText().length + 1;
                }
                globalOldOffset = globalOldOffset! + (selection.extent.nodePosition as TextNodePosition).offset;
                break;
              }
            }
          }

          int insertIndex = i;
          for (final block in blocks) {
            final newNode = _createNodeFromBlock(block, false);
            if (newNode != null) {
              requests.add(InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: newNode));

              if (globalOldOffset != null && globalOldOffset >= block.startOffset && globalOldOffset <= block.endOffset) {
                final newOffset = globalOldOffset - block.startOffset;
                requests.add(ChangeSelectionRequest(
                  DocumentSelection.collapsed(
                    position: DocumentPosition(
                      nodeId: newNode.id,
                      nodePosition: TextNodePosition(offset: newOffset),
                    ),
                  ),
                  SelectionChangeType.placeCaret,
                  SelectionReason.userInteraction,
                ));
              }
              insertIndex++;
            }
          }
          break;
        }
      }
      i++;
    }

    if (requests.isNotEmpty) {
      requestDispatcher.execute(requests);
    }
  }

  DocumentNode? _createNodeFromBlock(MarkdownBlock block, bool isRawMode) {
    final nodeId = Editor.createNodeId();
    final raw = block.text;

    if (raw.isEmpty) {
      return ParagraphNode(
        id: nodeId,
        text: AttributedText(''),
        metadata: MarkdownNodeMetadata(
          rawMarkdown: '',
          isRawMode: isRawMode,
        ).toMap(),
      );
    }

    bool isBlockquote = false;
    String innerRaw = raw;
    if (raw.trim().startsWith('>')) {
      isBlockquote = true;
      innerRaw = raw.split('\n').map((l) {
        final match = RegExp(r'^>\s?').firstMatch(l);
        return match != null ? l.substring(match.end) : l;
      }).join('\n');
    }

    final doc = deserializeMarkdownToDocument(innerRaw);
    if (doc.isEmpty) return null;

    final parsedNode = doc.first;
    final baseMeta = MarkdownNodeMetadata(
      rawMarkdown: raw,
      isRawMode: isRawMode,
      isBlockquote: isBlockquote,
    );

    return ParagraphNode(
      id: nodeId,
      text: parsedNode is TextNode ? parsedNode.text : AttributedText(raw),
      metadata: {
        ...parsedNode.metadata,
        ...baseMeta.toMap(),
      },
    );
  }
}
