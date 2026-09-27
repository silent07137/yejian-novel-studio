import '../models/library_data.dart';

/// A bounded, inspectable snapshot of the current book for one AI request.
class AiContextBuilder {
  const AiContextBuilder();

  String build({
    required Book book,
    required Chapter chapter,
    required String currentBody,
    required int selectionStart,
    required int selectionEnd,
  }) {
    final start = (selectionStart - 500).clamp(0, currentBody.length);
    final end = (selectionEnd + 500).clamp(start, currentBody.length);
    final nearby = _clean(currentBody.substring(start, end));
    final searchable = nearby.toLowerCase();
    final roles = book.roles
        .where(
          (role) =>
              _mentions(searchable, role.name) ||
              _mentions(searchable, role.alias),
        )
        .take(4)
        .toList();
    final worlds = book.worlds
        .where((world) => _mentions(searchable, world.title))
        .take(3)
        .toList();
    final roleIds = roles.map((role) => role.id).toSet();
    final events = book.events
        .where(
          (event) =>
              _mentions(searchable, event.title) ||
              event.roleIds.any(roleIds.contains),
        )
        .take(3)
        .toList();

    final sections = <String>[
      '【当前作品】${_limit(book.title, 100)}',
      '【当前章节】${_limit(chapter.title, 100)}',
      if (chapter.summary.trim().isNotEmpty)
        '【章节摘要】${_limit(chapter.summary, 300)}',
      if (nearby.isNotEmpty) '【选区附近正文】${_limit(nearby, 1200)}',
      if (roles.isNotEmpty)
        '【相关角色】\n${roles.map((role) => [role.name, if (role.alias.trim().isNotEmpty) '别名：${_limit(role.alias, 60)}', if (role.identity.trim().isNotEmpty) '身份：${_limit(role.identity, 80)}', if (role.personality.trim().isNotEmpty) '性格：${_limit(role.personality, 180)}', if (role.goal.trim().isNotEmpty) '目标：${_limit(role.goal, 150)}'].join('；')).join('\n')}',
      if (worlds.isNotEmpty)
        '【相关设定】\n${worlds.map((world) => [world.title, if (world.type.trim().isNotEmpty) '类别：${_limit(world.type, 60)}', if (world.description.trim().isNotEmpty) '简介：${_limit(world.description, 180)}', if (world.rule.trim().isNotEmpty) '规则：${_limit(world.rule, 180)}'].join('；')).join('\n')}',
      if (events.isNotEmpty)
        '【相关时间线事件】\n${events.map((event) => [event.title, if (event.storyDate.trim().isNotEmpty) '故事时间：${_limit(event.storyDate, 60)}', if (event.description.trim().isNotEmpty) '说明：${_limit(event.description, 160)}'].join('；')).join('\n')}',
    ];
    return _limit(sections.join('\n\n'), 4800);
  }

  bool _mentions(String body, String term) {
    final name = term.trim().toLowerCase();
    return name.length >= 2 && body.contains(name);
  }

  String _clean(String value) => value
      .replaceAll(RegExp(r'!\[[^\]]*\]\(yejian-image:[^)]+\)'), '[图片]')
      .trim();

  String _limit(String value, int max) {
    final cleaned = value.trim();
    return cleaned.length <= max ? cleaned : '${cleaned.substring(0, max)}…';
  }
}
