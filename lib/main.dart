import 'package:flutter/material.dart';
import 'live_markdown.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Markdown',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Live Markdown Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late LiveMarkdownController _controller;
  final TextEditingController _rawController = TextEditingController(
    text: '# Welcome\n\nThis is **bold** and *italic*\n\n> A blockquote\n\nPlain paragraph with `code`\n\n---',
  );

  @override
  void initState() {
    super.initState();
    _controller = LiveMarkdownController(initialMarkdown: _rawController.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _rawController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: LiveMarkdownEditor(controller: _controller),
            ),
          ),
          Container(width: 1, color: Colors.grey.shade300),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey.shade100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Raw Markdown", style: TextStyle(fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        onPressed: () {
                          _controller.replaceContent(_rawController.text);
                        },
                        icon: const Icon(Icons.sync),
                        label: const Text("Apply =>"),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey.shade50,
                    child: TextField(
                      controller: _rawController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
