import 'package:flutter/material.dart';

import '../models/library_data.dart';
import '../state/app_controller.dart';

Future<void> editBookDetails(
  BuildContext context,
  AppController controller,
  Book book,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _DetailsDialog(
      title: '编辑作品资料',
      nameLabel: '书名',
      initialName: book.title,
      initialSummary: book.description,
      summaryLabel: '作品简介',
      onSave: (name, summary) =>
          controller.updateBookInfo(book.id, title: name, description: summary),
    ),
  );
}

Future<void> confirmBookDeletion(
  BuildContext context,
  AppController controller,
  Book book,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除作品？'),
      content: Text('将删除《${book.title}》及其全部章节、设定和情节。请先导出需要保留的内容。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true) controller.deleteBook(book.id);
}

Future<void> showChapterSettings(
  BuildContext context,
  AppController controller,
  Chapter chapter,
) => showDialog<void>(
  context: context,
  builder: (_) =>
      _ChapterSettingsDialog(controller: controller, chapter: chapter),
);

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({
    required this.title,
    required this.nameLabel,
    required this.initialName,
    required this.initialSummary,
    required this.summaryLabel,
    required this.onSave,
  });

  final String title;
  final String nameLabel;
  final String initialName;
  final String initialSummary;
  final String summaryLabel;
  final void Function(String name, String summary) onSave;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _summary = TextEditingController(text: widget.initialSummary);

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(labelText: widget.nameLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summary,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(labelText: widget.summaryLabel),
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
        onPressed: () {
          widget.onSave(_name.text, _summary.text);
          Navigator.pop(context);
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _ChapterSettingsDialog extends StatefulWidget {
  const _ChapterSettingsDialog({
    required this.controller,
    required this.chapter,
  });

  final AppController controller;
  final Chapter chapter;

  @override
  State<_ChapterSettingsDialog> createState() => _ChapterSettingsDialogState();
}

class _ChapterSettingsDialogState extends State<_ChapterSettingsDialog> {
  late final _title = TextEditingController(text: widget.chapter.title);
  late final _summary = TextEditingController(text: widget.chapter.summary);
  late var _status = widget.chapter.status;
  late var _volumeId = widget.chapter.volumeId ?? '';
  late var _exportEnabled = widget.chapter.exportEnabled;

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('章节设置'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '章节标题'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _volumeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '所属分卷'),
              items: [
                const DropdownMenuItem(value: '', child: Text('未分卷')),
                ...?widget.controller.activeBook?.volumes.map(
                  (volume) => DropdownMenuItem(
                    value: volume.id,
                    child: Text(volume.title, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _volumeId = value ?? ''),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: '写作状态'),
              items: ['草稿', '修订中', '定稿']
                  .map(
                    (status) =>
                        DropdownMenuItem(value: status, child: Text(status)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _status = value ?? '草稿'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _summary,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '章节目标／梗概'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('纳入正文导出'),
              value: _exportEnabled,
              onChanged: (value) =>
                  setState(() => _exportEnabled = value ?? true),
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
        onPressed: () {
          widget.controller.updateChapterSettings(
            widget.chapter.id,
            title: _title.text,
            summary: _summary.text,
            status: _status,
            volumeId: _volumeId.isEmpty ? null : _volumeId,
            exportEnabled: _exportEnabled,
          );
          Navigator.pop(context);
        },
        child: const Text('保存'),
      ),
    ],
  );
}

/// Both the mobile book home and desktop writing panel expose the same actions.
class BookDirectory extends StatefulWidget {
  const BookDirectory({
    super.key,
    required this.controller,
    required this.book,
    required this.onOpenChapter,
    this.dense = false,
  });

  final AppController controller;
  final Book book;
  final ValueChanged<String> onOpenChapter;
  final bool dense;

  @override
  State<BookDirectory> createState() => _BookDirectoryState();
}

class _BookDirectoryState extends State<BookDirectory> {
  final _chapterIds = <String>{};
  final _volumeIds = <String>{};
  final _collapsedVolumes = <String>{};
  bool _selecting = false;

  void _toggle(String id, {bool volume = false}) => setState(() {
    _selecting = true;
    final ids = volume ? _volumeIds : _chapterIds;
    if (!ids.add(id)) ids.remove(id);
  });

  void _clearSelection() => setState(() {
    _selecting = false;
    _chapterIds.clear();
    _volumeIds.clear();
  });

  Future<void> _delete({Set<String>? chapters, Set<String>? volumes}) async {
    final chapterIds = chapters ?? Set<String>.of(_chapterIds);
    final volumeIds = volumes ?? Set<String>.of(_volumeIds);
    final volumeChapterCount = widget.book.chapters
        .where(
          (chapter) =>
              volumeIds.contains(chapter.volumeId) &&
              !chapterIds.contains(chapter.id),
        )
        .length;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除所选内容？'),
        content: Text(
          [
            if (volumeIds.isNotEmpty) '已选 ${volumeIds.length} 个分卷。',
            if (chapterIds.isNotEmpty) '将删除 ${chapterIds.length} 个已选章节及其正文。',
            if (volumeChapterCount > 0)
              '分卷中另有 $volumeChapterCount 个章节，可以保留并移至“未分卷”，或一并删除。',
            '请先导出需要保留的内容。',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (volumeChapterCount > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, 'all'),
              child: const Text('连同卷内章节删除'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: Text(volumeChapterCount > 0 ? '删除分卷，保留卷内章节' : '删除'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    widget.controller.deleteDirectoryItems(
      chapterIds: chapterIds,
      volumeIds: volumeIds,
      deleteVolumeChapters: choice == 'all',
    );
    if (mounted) _clearSelection();
  }

  Widget _chapter(Chapter chapter) {
    final index = widget.book.chapters.indexOf(chapter) + 1;
    return ListTile(
      key: ValueKey('directory-chapter-${chapter.id}'),
      dense: widget.dense,
      contentPadding: const EdgeInsets.only(left: 12, right: 4),
      leading: _selecting
          ? Checkbox(
              value: _chapterIds.contains(chapter.id),
              onChanged: (_) => _toggle(chapter.id),
            )
          : Text(
              index.toString().padLeft(2, '0'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
      title: Text(chapter.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${chapter.wordCount} 字 · ${chapter.status}${chapter.exportEnabled ? '' : ' · 不导出'}',
      ),
      selected: _chapterIds.contains(chapter.id),
      onLongPress: () => _toggle(chapter.id),
      onTap: () =>
          _selecting ? _toggle(chapter.id) : widget.onOpenChapter(chapter.id),
      trailing: _selecting
          ? null
          : PopupMenuButton<String>(
              tooltip: '章节操作：${chapter.title}',
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    showChapterSettings(context, widget.controller, chapter);
                  case 'copy':
                    widget.controller.duplicateChapter(chapter.id);
                  case 'up':
                    widget.controller.moveChapter(chapter.id, -1);
                  case 'down':
                    widget.controller.moveChapter(chapter.id, 1);
                  case 'select':
                    _toggle(chapter.id);
                  case 'delete':
                    _delete(chapters: {chapter.id}, volumes: {});
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑章节 / 状态')),
                PopupMenuItem(value: 'copy', child: Text('复制章节')),
                PopupMenuItem(value: 'up', child: Text('上移')),
                PopupMenuItem(value: 'down', child: Text('下移')),
                PopupMenuItem(value: 'select', child: Text('多选')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
    );
  }

  Widget _volume(Volume volume) {
    final chapters = widget.book.chapters
        .where((chapter) => chapter.volumeId == volume.id)
        .toList();
    final collapsed = _collapsedVolumes.contains(volume.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            key: ValueKey('directory-volume-${volume.id}'),
            dense: widget.dense,
            contentPadding: const EdgeInsets.only(left: 12, right: 4),
            leading: _selecting
                ? Checkbox(
                    value: _volumeIds.contains(volume.id),
                    onChanged: (_) => _toggle(volume.id, volume: true),
                  )
                : Icon(
                    collapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                  ),
            title: Text(
              volume.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${chapters.length} 章'),
            selected: _volumeIds.contains(volume.id),
            onLongPress: () => _toggle(volume.id, volume: true),
            onTap: () => _selecting
                ? _toggle(volume.id, volume: true)
                : setState(() {
                    if (!_collapsedVolumes.add(volume.id)) {
                      _collapsedVolumes.remove(volume.id);
                    }
                  }),
            trailing: _selecting
                ? null
                : PopupMenuButton<String>(
                    tooltip: '分卷操作：${volume.title}',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          showDialog<void>(
                            context: context,
                            builder: (_) => _DetailsDialog(
                              title: '编辑分卷',
                              nameLabel: '分卷名称',
                              initialName: volume.title,
                              initialSummary: volume.summary,
                              summaryLabel: '分卷简介',
                              onSave: (title, summary) =>
                                  widget.controller.updateVolume(
                                    volume.id,
                                    title: title,
                                    summary: summary,
                                  ),
                            ),
                          );
                        case 'new':
                          widget.controller.createChapter(volumeId: volume.id);
                          widget.onOpenChapter(
                            widget.controller.selectedChapterId!,
                          );
                        case 'select':
                          _toggle(volume.id, volume: true);
                        case 'delete':
                          _delete(chapters: {}, volumes: {volume.id});
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑分卷')),
                      PopupMenuItem(value: 'new', child: Text('在此卷新建章节')),
                      PopupMenuItem(value: 'select', child: Text('多选')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
          ),
          if (!collapsed) ...[
            const Divider(height: 1),
            if (chapters.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('这一卷还没有章节'),
              ),
            ...chapters.map(_chapter),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final ungrouped = widget.book.chapters
          .where((chapter) => chapter.volumeId == null)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selecting)
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text('已选 ${_volumeIds.length} 卷、${_chapterIds.length} 章'),
                    TextButton(
                      onPressed: () => setState(() {
                        _volumeIds.addAll(
                          widget.book.volumes.map((volume) => volume.id),
                        );
                        _chapterIds.addAll(
                          widget.book.chapters.map((chapter) => chapter.id),
                        );
                      }),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: _clearSelection,
                      child: const Text('取消多选'),
                    ),
                    FilledButton.icon(
                      onPressed: _chapterIds.isEmpty && _volumeIds.isEmpty
                          ? null
                          : () => _delete(),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('删除所选'),
                    ),
                  ],
                ),
              ),
            )
          else if (widget.book.chapters.isNotEmpty ||
              widget.book.volumes.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _selecting = true),
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: const Text('多选管理'),
              ),
            ),
          if (ungrouped.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.all(10), child: Text('未分卷')),
            Card(child: Column(children: ungrouped.map(_chapter).toList())),
          ],
          ...widget.book.volumes.map(_volume),
          if (widget.book.chapters.isEmpty && widget.book.volumes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有章节，从“新建章节”开始。'),
            ),
        ],
      );
    },
  );
}
