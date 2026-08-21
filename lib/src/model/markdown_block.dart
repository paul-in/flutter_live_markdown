// Block created during initial splitting of the document;
class MarkdownBlock {
  final String text;
  final int startOffset;
  final int endOffset;

  const MarkdownBlock(this.text, this.startOffset, this.endOffset);

  @override
  String toString() => 'MarkdownBlock(start=$startOffset, end=$endOffset, text=${text.length}chars)';
}
