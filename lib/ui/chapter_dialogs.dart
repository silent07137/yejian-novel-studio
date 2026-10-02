import 'dart:io';

import 'package:flutter/material.dart';

import '../models/library_data.dart';

class ChapterSummaryDialog extends StatefulWidget {
  const ChapterSummaryDialog({super.key, required this.initialValue});
  final String initialValue;
  @override
  State<ChapterSummaryDialog> createState() => _ChapterSummaryDialogState();
}

class _ChapterSummaryDialogState extends State<ChapterSummaryDialog> {
  late final _text = TextEditingController(text: widget.initialValue);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('本章笔记'),
    content: SizedBox(
      width: 440,
      child: TextField(
        key: const ValueKey('chapter-summary-field'),
        controller: _text,
        autofocus: true,
        minLines: 4,
        maxLines: 10,
        decoration: const InputDecoration(labelText: '章节目标与大纲'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('保存'),
      ),
    ],
  );
}

class ChapterImageDialog extends StatefulWidget {
  const ChapterImageDialog({super.key, required this.image});
  final ChapterImage image;
  @override
  State<ChapterImageDialog> createState() => _ChapterImageDialogState();
}

class _ChapterImageDialogState extends State<ChapterImageDialog> {
  late double _width = widget.image.widthFactor;
  late final _caption = TextEditingController(text: widget.image.alt);
  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('图片设置'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.file(
              File(widget.image.path),
              height: 140,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text('图片文件未找到'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _caption,
              maxLength: 120,
              decoration: const InputDecoration(labelText: '图片说明'),
            ),
            Text('正文宽度的 ${(_width * 100).round()}%'),
            Slider(
              key: const ValueKey('chapter-image-width'),
              value: _width,
              min: .1,
              max: 1,
              divisions: 18,
              label: '${(_width * 100).round()}%',
              onChanged: (value) => setState(() => _width = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (alt: _caption.text, width: _width)),
        child: const Text('保存'),
      ),
    ],
  );
}
