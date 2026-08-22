import 'package:flutter/material.dart';
import 'package:flutter_live_markdown/flutter_live_markdown.dart';

const _initial = '# Welcome\n\nThis is **bold** and *italic*\n\n> A blockquote\n\nPlain paragraph with `code` inline\n\n---\n\nA [link](https://example.com)\n\n![](https://picsum.photos/400/200)\n\nI love flutter !';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Markdown',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _editorKey = GlobalKey();
  late final LiveMarkdownController _ctrl;
  final _scrollOffsetCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _replaceCursorCtrl = TextEditingController(text: '0');

  int _changeCount = 0;
  int _selCount = 0;
  int _historyCount = 0;
  bool _canUndo = false, _canRedo = false;
  bool _isFocused = false;
  String _extractedContent = '';
  bool _apiMode = true;
  bool _deferToPointerUp = true;
  bool _cursorInsideMarkers = true;

  @override
  void initState() {
    super.initState();
    _ctrl = LiveMarkdownController(initialMarkdown: _initial);
    _ctrl.onChange = () {
      _changeCount++;
      if (_apiMode) setState(() {});
    };
    _ctrl.onSelectionChange = () {
      _selCount++;
      if (_apiMode) setState(() {});
    };
    _ctrl.onFocusChange = (focused) {
      _isFocused = focused;
      if (_apiMode) setState(() {});
    };
    _ctrl.onHistoryChange = () {
      _historyCount++;
      _canUndo = _ctrl.canUndo;
      _canRedo = _ctrl.canRedo;
      if (_apiMode) setState(() {});
    };
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollOffsetCtrl.dispose();
    _replaceCtrl.dispose();
    _replaceCursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorSection = Padding(
      padding: const EdgeInsets.all(16),
      child: LiveMarkdownEditor(
        key: _editorKey,
        controller: _ctrl,
        deferToPointerUp: _deferToPointerUp,
        cursorInsideMarkers: _cursorInsideMarkers,
      ),
    );

    final controlsSection = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('Editor config'),
          const SizedBox(height: 4),
          _configToggle('Defer selection to pointer up', _deferToPointerUp, (v) {
            if (v != null) setState(() => _deferToPointerUp = v);
          }),
          _configToggle('Cursor inside markers', _cursorInsideMarkers, (v) {
            if (v != null) setState(() => _cursorInsideMarkers = v);
          }),
          const SizedBox(height: 12),
          _buildSection('API'),
          _apiToggle(),
          const SizedBox(height: 8),
          _selectionInfo(),
          const SizedBox(height: 8),
          _actionButtons(),
          const SizedBox(height: 8),
          _scrollToField(),
          const SizedBox(height: 8),
          _replaceField(),
          const SizedBox(height: 8),
          _extractField(),
          const SizedBox(height: 8),
          _callbackInfo(),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 800) {
              // Mode Bureau / Web (Côte à côte)
              return Row(
                children: [
                  Expanded(child: editorSection),
                  Container(width: 1, color: Colors.grey.shade300),
                  Expanded(child: controlsSection),
                ],
              );
            } else {
              // Mode Mobile (L'un au dessus de l'autre)
              return Column(
                children: [
                  Expanded(flex: 3, child: editorSection),
                  Container(height: 1, color: Colors.grey.shade300),
                  Expanded(flex: 2, child: controlsSection),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _configToggle(String label, bool value, ValueChanged<bool?> onChanged) => Row(
        children: [
          SizedBox(
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      );

  Widget _buildSection(String title) => Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
      );

  Widget _apiToggle() => Row(
        children: [
          const Text('Monitor', style: TextStyle(fontSize: 13)),
          Switch(
            value: _apiMode,
            onChanged: (v) => setState(() => _apiMode = v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Text('ON : events tracked in real time  OFF : max fluidity',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      );

  Widget _selectionInfo() => _infoRow(
        'Selection',
        '${_ctrl.selectionStart} – ${_ctrl.selectionEnd}',
      );

  Widget _actionButtons() => Wrap(
        spacing: 8,
        children: [
          _btn('Undo', _ctrl.canUndo, () => _ctrl.undo()),
          _btn('Redo', _ctrl.canRedo, () => _ctrl.redo()),
          _btn('Blur', true, () => _ctrl.blur()),
          _btn('Clear Sel', true, () => _ctrl.clearSelection()),
          _btn('Clear Hist', true, () => _ctrl.clearHistory()),
        ],
      );

  Widget _scrollToField() => Row(
        children: [
          const SizedBox(width: 80, child: Text('Scroll to:', style: TextStyle(fontSize: 13))),
          SizedBox(width: 80, child: TextField(
            controller: _scrollOffsetCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
          )),
          const SizedBox(width: 8),
          _btn('Go', true, () {
            final v = int.tryParse(_scrollOffsetCtrl.text);
            if (v != null) _ctrl.scrollTo(v);
          }),
        ],
      );

  Widget _replaceField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Replace content:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _replaceCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Enter new markdown...',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Cursor at:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 50,
                        child: TextField(
                          controller: _replaceCursorCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _btn('Replace', true, () {
                    if (_replaceCtrl.text.isNotEmpty) {
                      final cursor = int.tryParse(_replaceCursorCtrl.text);
                      _ctrl.replaceContent(_replaceCtrl.text, cursor: cursor);
                      _replaceCtrl.clear();
                    }
                  }),
                ],
              ),
            ],
          ),
        ],
      );

  Widget _extractField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Extract selection:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 12),
              _btn('Extract', true, () {
                int f = _ctrl.selectionStart;
                int t = _ctrl.selectionEnd;
                if (f > t) (f, t) = (t, f);
                _extractedContent = f != t ? _ctrl.getContentBetween(f, t) : '';
                setState(() {});
              }),
            ],
          ),
          const SizedBox(height: 4),
          _extractedContent.isNotEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_extractedContent, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey)),
                )
              : const SizedBox.shrink(),
        ],
      );

  Widget _callbackInfo() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Callbacks', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          _infoRow('onChange', '$_changeCount events'),
          _infoRow('onSelectionChange', '$_selCount events'),
          _infoRow('onFocusChange', _isFocused ? '✓ focused' : '✗ not focused'),
          _infoRow('onHistoryChange', '$_historyCount events  U:${_canUndo ? "✓" : "✗"} R:${_canRedo ? "✓" : "✗"}'),
        ],
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _btn(String label, bool enabled, VoidCallback onPressed) => SizedBox(
        height: 30,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
          onPressed: enabled ? onPressed : null,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );
}
