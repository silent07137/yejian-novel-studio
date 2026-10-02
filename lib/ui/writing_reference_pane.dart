import 'package:flutter/material.dart';

import '../models/library_data.dart';
import '../state/app_controller.dart';
import 'card_pages.dart';
import 'chapter_dialogs.dart';

class WritingReferencePane extends StatelessWidget {
  const WritingReferencePane({
    super.key,
    required this.book,
    required this.chapter,
    required this.controller,
  });

  final Book book;
  final Chapter? chapter;
  final AppController controller;

  Future<void> _editSummary(BuildContext context) async {
    final current = chapter;
    if (current == null) return;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => ChapterSummaryDialog(initialValue: current.summary),
    );
    if (result != null) controller.updateChapterSummary(current.id, result);
  }

  String _excerpt(String text) =>
      text.length > 240 ? '${text.substring(0, 240)}…' : text;

  @override
  Widget build(BuildContext context) {
    final events =
        book.events.where((event) => event.chapterId == chapter?.id).toList()
          ..sort(compareTimelineEvents);
    final participantIds = events.expand((event) => event.roleIds).toSet();
    final roles = book.roles.toList()
      ..sort(
        (a, b) => (participantIds.contains(b.id) ? 1 : 0).compareTo(
          participantIds.contains(a.id) ? 1 : 0,
        ),
      );
    return Container(
      key: const ValueKey('writing-reference-pane'),
      width: 276,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '本章笔记',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const ValueKey('edit-chapter-summary'),
                  tooltip: '编辑本章笔记',
                  onPressed: chapter == null
                      ? null
                      : () => _editSummary(context),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                ),
              ],
            ),
            InkWell(
              onTap: chapter == null ? null : () => _editSummary(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  chapter?.summary.isNotEmpty == true
                      ? chapter!.summary
                      : '填写章节目标与大纲',
                ),
              ),
            ),
            if (chapter != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${chapter!.status} · ${chapter!.wordCount} 字',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            const Text('角色参考', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (roles.isEmpty) const Text('还没有角色卡'),
            for (final role in roles)
              Tooltip(
                message: _excerpt(
                  [
                    role.name,
                    role.identity,
                    role.description,
                    if (role.personality.isNotEmpty) '性格：${role.personality}',
                    if (role.goal.isNotEmpty) '目标：${role.goal}',
                  ].where((text) => text.isNotEmpty).join('\n'),
                ),
                child: ListTile(
                  key: ValueKey('reference-role-${role.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(
                      role.name.isEmpty ? '未' : role.name.characters.first,
                    ),
                  ),
                  title: Text(
                    role.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    role.identity,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => RoleDetailPage(
                        initialRole: role,
                        controller: controller,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text('世界观参考', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (book.worlds.isEmpty) const Text('还没有世界观条目'),
            for (final world in book.worlds)
              Tooltip(
                message: _excerpt(
                  '${world.title}\n${world.description}\n${world.rule}',
                ),
                child: ListTile(
                  key: ValueKey('reference-world-${world.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.public_outlined),
                  title: Text(
                    world.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    world.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => WorldDetailPage(
                        initialWorld: world,
                        controller: controller,
                      ),
                    ),
                  ),
                ),
              ),
            if (events.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('本章情节', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final event in events)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(event.title),
                  subtitle: Text(event.storyDate),
                  onTap: () =>
                      controller.openStoryEvent(event.id, fromWriting: true),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
