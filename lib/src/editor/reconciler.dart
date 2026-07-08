import 'package:super_editor/super_editor.dart';

import '../model/markdown_block.dart';
import '../parsing/inline_formatter.dart';
import '../parsing/markdown_splitter.dart';

class MarkdownReconciler extends EditReaction {
  final DocumentNode Function(MarkdownBlock) createNodeForBlock;

  MarkdownReconciler({required this.createNodeForBlock});

  @override
  void modifyContent(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final document = editorContext.find(Editor.documentKey) as Document;
    final composer = editorContext.find(Editor.composerKey) as MutableDocumentComposer;
    final selection = composer.selection;

    final allRequests = <EditRequest>[];
    bool selectionHandled = false;

    // Pass 1: raw-mode multi-block splits (Scenario A)
    for (final editEvent in changeList) {
      if (editEvent is! DocumentEdit) continue;
      final change = editEvent.change;
      if (change is! NodeDocumentChange) continue;

      final node = document.getNodeById(change.nodeId);
      if (node is! TextNode) continue;
      if (node.metadata['isRawMode'] != true) continue;

      final text = node.text.toPlainText();
      final blocks = splitMarkdownIntoBlocks(text);
      if (blocks.length <= 1) continue;

      final nodeIndex = document.getNodeIndexById(node.id);
      if (nodeIndex == -1) continue;
      allRequests.add(DeleteNodeRequest(nodeId: node.id));

      String? prevId;
      for (int i = 0; i < blocks.length; i++) {
        final newNode = _createRawModeNode(blocks[i]);
        if (i == 0) {
          allRequests.add(InsertNodeAtIndexRequest(nodeIndex: nodeIndex, newNode: newNode));
        } else {
          allRequests.add(InsertNodeAfterNodeRequest(existingNodeId: prevId!, newNode: newNode));
        }
        if (!selectionHandled) {
          _preserveSelectionOnSplit(selection, node.id, blocks[i], newNode, allRequests);
          if (allRequests.isNotEmpty && allRequests.last is ChangeSelectionRequest) {
            selectionHandled = true;
          }
        }
        prevId = newNode.id;
      }
    }

    // Collect IDs of all nodes changed in this edit
    final changedNodeIds = <String>{};
    for (final editEvent in changeList) {
      if (editEvent is! DocumentEdit) continue;
      final change = editEvent.change;
      if (change is! NodeDocumentChange) continue;
      changedNodeIds.add(change.nodeId);
    }

    // Pass 2: detect paste events — collect candidate node IDs
    // that need group-based markdown parsing
    final affectedIds = <String>{};
    bool hasPasteEvent = false;

    for (final editEvent in changeList) {
      if (editEvent is! DocumentEdit) continue;
      final change = editEvent.change;
      if (change is! NodeDocumentChange) continue;

      final node = document.getNodeById(change.nodeId);
      if (node is! TextNode) continue;
      if (node.metadata['isRawMode'] == true) continue;

      final rawMd = node.metadata['rawMarkdown'] as String?;

      // Naked node (no rawMd at all)
      if (rawMd == null) {
        affectedIds.add(node.id);
        hasPasteEvent = true;
        continue;
      }

      // Empty placeholder that just received content
      if (rawMd.isEmpty && node.text.toPlainText().isNotEmpty) {
        affectedIds.add(node.id);
        hasPasteEvent = true;
        continue;
      }
    }

    if (hasPasteEvent) {
      // Walk document to find first consecutive group of affected nodes
      final group = <TextNode>[];
      int groupStartIndex = 0;
      bool inGroup = false;

      for (int i = 0; i < document.length; i++) {
        final n = document.getNodeAt(i);
        if (n is TextNode && affectedIds.contains(n.id)) {
          if (!inGroup) {
            inGroup = true;
            groupStartIndex = i;
          }
          group.add(n);
        } else if (inGroup) {
          break;
        }
      }

      // Include the preceding node if it was changed in this edit,
      // which happens when the first pasted line was merged into
      // the existing formatted node (paste handler)
      if (group.isNotEmpty && groupStartIndex > 0) {
        final prevNode = document.getNodeAt(groupStartIndex - 1);
        if (prevNode is TextNode &&
            changedNodeIds.contains(prevNode.id) &&
            prevNode.metadata['isRawMode'] != true) {
          group.insert(0, prevNode);
          groupStartIndex -= 1;
        }
      }

      if (group.isNotEmpty) {
        _reconcileNakedGroup(
          document, selection, group, groupStartIndex, allRequests, selectionHandled,
        );
      }
    }

    if (allRequests.isNotEmpty) {
      requestDispatcher.execute(allRequests);
    }
  }

  void _reconcileNakedGroup(
    Document document,
    DocumentSelection? selection,
    List<TextNode> group,
    int groupStartIndex,
    List<EditRequest> allRequests,
    bool selectionHandled,
  ) {
    // Reconstruct raw text by joining individual lines with \n
    // (matching the \n split that PasteEditorCommand used)
    final reconstructedRaw = group.map((n) => n.text.toPlainText()).join('\n');
    final blocks = splitMarkdownIntoBlocks(reconstructedRaw);

    // Compute global old offset for selection preservation
    int? globalOldOffset;
    if (selection != null) {
      for (int g = 0; g < group.length; g++) {
        if (group[g].id == selection.extent.nodeId) {
          int offset = 0;
          for (int k = 0; k < g; k++) {
            offset += group[k].text.toPlainText().length + 1; // +1 for \n
          }
          offset += (selection.extent.nodePosition as TextNodePosition).offset;
          globalOldOffset = offset;
          break;
        }
      }
    }

    // Handle empty blocks (preserve empty paragraphs)
    if (blocks.isEmpty) {
      for (final n in group) {
        final meta = Map<String, dynamic>.from(n.metadata);
        meta['rawMarkdown'] = '';
        meta['isRawMode'] = false;
        allRequests.add(ReplaceNodeRequest(
          existingNodeId: n.id,
          newNode: ParagraphNode(id: n.id, text: AttributedText(''), metadata: meta),
        ));
      }
      return;
    }

    // Delete all nodes in the group
    for (final n in group) {
      allRequests.add(DeleteNodeRequest(nodeId: n.id));
    }

    // Insert new typed nodes
    String? prevId;
    for (int i = 0; i < blocks.length; i++) {
      final newNode = _createFormattedNode(blocks[i]);
      if (i == 0) {
        allRequests.add(InsertNodeAtIndexRequest(nodeIndex: groupStartIndex, newNode: newNode));
      } else {
        allRequests.add(InsertNodeAfterNodeRequest(existingNodeId: prevId!, newNode: newNode));
      }

      // Selection preservation via global offset
      if (globalOldOffset != null &&
          globalOldOffset >= blocks[i].startOffset &&
          globalOldOffset <= blocks[i].endOffset &&
          !selectionHandled) {
        if (newNode is TextNode) {
          allRequests.add(ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: newNode.id,
                nodePosition: TextNodePosition(offset: globalOldOffset - blocks[i].startOffset),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ));
        } else {
          allRequests.add(ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: newNode.id,
                nodePosition: const UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ));
        }
      }
      prevId = newNode.id;
    }
  }

  DocumentNode _createFormattedNode(MarkdownBlock block) {
    final base = createNodeForBlock(block);
    if (base is! TextNode) return base;
    final meta = Map<String, dynamic>.from(base.metadata);
    meta['rawMarkdown'] = block.text;
    meta['isRawMode'] = false;
    return base.copyTextNodeWith(metadata: meta);
  }

  DocumentNode _createRawModeNode(MarkdownBlock block) {
    final base = createNodeForBlock(block);
    if (base is! TextNode) return base;

    final formatted = applyInlineFormatting(block.text);
    final meta = Map<String, dynamic>.from(base.metadata);
    meta['rawMarkdown'] = block.text;
    meta['isRawMode'] = true;

    return base.copyTextNodeWith(text: formatted, metadata: meta);
  }

  void _preserveSelectionOnSplit(
    DocumentSelection? selection,
    String oldNodeId,
    MarkdownBlock block,
    DocumentNode newNode,
    List<EditRequest> requests,
  ) {
    if (selection == null) return;
    if (selection.extent.nodeId != oldNodeId && selection.base.nodeId != oldNodeId) return;

    for (final pos in [selection.extent, selection.base]) {
      if (pos.nodeId != oldNodeId) continue;
      if (pos.nodePosition is! TextNodePosition) continue;

      final offset = (pos.nodePosition as TextNodePosition).offset;
      if (offset >= block.startOffset && offset <= block.endOffset) {
        if (newNode is TextNode) {
          requests.add(ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: newNode.id,
                nodePosition: TextNodePosition(offset: offset - block.startOffset),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ));
        } else {
          requests.add(ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: newNode.id,
                nodePosition: const UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ));
        }
        return;
      }
    }
  }
}
