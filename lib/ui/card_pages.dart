import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/entity_id.dart';
import '../models/library_data.dart';
import '../state/app_controller.dart';

class RoleDetailPage extends StatefulWidget {
  const RoleDetailPage({
    super.key,
    required this.initialRole,
    required this.controller,
  });

  final RoleCard initialRole;
  final AppController controller;

  @override
  State<RoleDetailPage> createState() => _RoleDetailPageState();
}

class _RoleDetailPageState extends State<RoleDetailPage> {
  late RoleCard _role = widget.initialRole;

  Future<void> _edit() async {
    final updated = await Navigator.push<RoleCard>(
      context,
      MaterialPageRoute(
        builder: (context) => RoleEditPage(
          role: _role,
          allRoles: widget.controller.activeBook?.roles ?? const [],
          baseFields: widget.controller.activeBook?.roleBaseFields ?? const [],
          sharedFields: (widget.controller.activeBook?.roleFields ?? const [])
              .where((field) => field.enabled && !field.deleted)
              .toList(),
        ),
      ),
    );
    if (updated == null || !mounted) return;
    widget.controller.saveRole(updated);
    setState(() => _role = updated);
  }

  Future<void> _delete() async {
    final references =
        widget.controller.activeBook?.events
            .where(
              (event) =>
                  event.roleIds.contains(_role.id) ||
                  event.persons.contains(_role.name),
            )
            .length ??
        0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除角色？'),
        content: Text(
          references == 0
              ? '正文不会被改写。角色数据会保留软删除记录。'
              : '发现 $references 个可能含此姓名的事件；正文与事件文字不会被改写。',
        ),
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
    if (confirmed != true || !mounted) return;
    widget.controller.deleteRole(_role.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final relatedRoles =
        widget.controller.activeBook?.roles ?? const <RoleCard>[];
    final hasRelations =
        _role.relations.isNotEmpty ||
        relatedRoles.any(
          (role) =>
              role.id != _role.id &&
              role.relations.any(
                (relation) => relation.targetRoleId == _role.id,
              ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(_role.name),
        actions: [
          IconButton(
            tooltip: '编辑角色',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _delete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Center(
              child: CircleAvatar(
                radius: 38,
                child: Text(
                  _role.name.characters.first,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                _role.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            if (_role.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _role.tags
                      .map((tag) => Chip(label: Text(tag)))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 26),
            _DetailSection(
              title: '概览',
              values: {
                '简介': _role.description,
                '别名': _role.alias,
                '年龄': _role.age,
                '身份 / 职业': _role.identity,
              },
            ),
            _DetailSection(
              title: '完整设定',
              values: {
                '外貌': _role.appearance,
                '性格': _role.personality,
                '背景经历': _role.background,
                '目标 / 动机': _role.goal,
                '能力 / 特长': _role.ability,
                '弱点': _role.weakness,
                '备注': _role.notes,
              },
            ),
            if (_role.relationships.isNotEmpty)
              _DetailSection(
                title: '旧版关系备注',
                values: {'内容': _role.relationships},
              ),
            if (_role.relations.isNotEmpty)
              _RelationSection(
                relations: _role.relations,
                allRoles: relatedRoles,
              ),
            if (hasRelations)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: OutlinedButton.icon(
                  key: const ValueKey('open-role-relationship-map'),
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => _RoleRelationshipMapPage(
                        role: _role,
                        roles: relatedRoles,
                        controller: widget.controller,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('查看人物关系图'),
                ),
              ),
            _DetailSection(
              title: '自定义条目',
              values: {
                for (final field in [
                  ...(widget.controller.activeBook?.roleFields ?? const []),
                  ..._role.customFields,
                ])
                  field.name: _customValueText(_role.customValues[field.id]),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class RoleEditPage extends StatefulWidget {
  const RoleEditPage({
    super.key,
    required this.role,
    required this.allRoles,
    this.baseFields = const [],
    this.sharedFields = const [],
    this.isNew = false,
  });

  final RoleCard role;
  final List<RoleCard> allRoles;
  final List<CustomFieldDefinition> baseFields;
  final List<CustomFieldDefinition> sharedFields;
  final bool isNew;

  @override
  State<RoleEditPage> createState() => _RoleEditPageState();
}

class _RoleEditPageState extends State<RoleEditPage> {
  late final Map<String, TextEditingController> _fields = {
    'name': TextEditingController(text: widget.role.name),
    'description': TextEditingController(text: widget.role.description),
    'alias': TextEditingController(text: widget.role.alias),
    'age': TextEditingController(text: widget.role.age),
    'identity': TextEditingController(text: widget.role.identity),
    'appearance': TextEditingController(text: widget.role.appearance),
    'personality': TextEditingController(text: widget.role.personality),
    'background': TextEditingController(text: widget.role.background),
    'goal': TextEditingController(text: widget.role.goal),
    'ability': TextEditingController(text: widget.role.ability),
    'weakness': TextEditingController(text: widget.role.weakness),
    'relationships': TextEditingController(text: widget.role.relationships),
    'notes': TextEditingController(text: widget.role.notes),
    'tags': TextEditingController(text: widget.role.tags.join('、')),
  };
  late final List<RoleRelation> _relations = widget.role.relations
      .map(
        (item) => RoleRelation(
          id: item.id,
          targetRoleId: item.targetRoleId,
          name: item.name,
          direction: item.direction,
          description: item.description,
          stage: item.stage,
        ),
      )
      .toList();
  late final List<CustomFieldDefinition> _customFields = [
    ...widget.sharedFields,
    ...widget.role.customFields,
  ].map(_copyCustomField).toList();
  late final Map<String, dynamic> _customValues = {
    for (final entry in widget.role.customValues.entries)
      entry.key: entry.value is List
          ? List<String>.from(entry.value as List)
          : entry.value,
  };

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _fields['name']!.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写角色姓名')));
      return;
    }
    Navigator.pop(
      context,
      RoleCard(
        id: widget.role.id,
        name: name,
        description: _fields['description']!.text.trim(),
        alias: _fields['alias']!.text.trim(),
        age: _fields['age']!.text.trim(),
        identity: _fields['identity']!.text.trim(),
        appearance: _fields['appearance']!.text.trim(),
        personality: _fields['personality']!.text.trim(),
        background: _fields['background']!.text.trim(),
        goal: _fields['goal']!.text.trim(),
        ability: _fields['ability']!.text.trim(),
        weakness: _fields['weakness']!.text.trim(),
        relationships: _fields['relationships']!.text.trim(),
        notes: _fields['notes']!.text.trim(),
        tags: _splitValues(_fields['tags']!.text),
        relations: _relations,
        customFields: _customFields,
        customValues: _customValues,
      ),
    );
  }

  Future<void> _addCustomField() async {
    final field = await _createCustomFieldDialog(context, world: false);
    if (field == null) return;
    setState(() {
      _customFields.add(field);
      _customValues[field.id] = field.type == 'multiChoice' ? <String>[] : '';
    });
  }

  Future<void> _addRelation() async {
    final targets = widget.allRoles
        .where((item) => item.id != widget.role.id)
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先创建另一个角色')));
      return;
    }
    var targetId = targets.first.id;
    var direction = '单向';
    final name = TextEditingController();
    final description = TextEditingController();
    final stage = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新增人物关系'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: targetId,
                    decoration: const InputDecoration(labelText: '目标角色'),
                    items: targets
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => targetId = value ?? targetId,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '关系名称'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: direction,
                    decoration: const InputDecoration(labelText: '方向'),
                    items: const ['单向', '双向']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => direction = value ?? direction),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stage,
                    decoration: const InputDecoration(labelText: '有效故事阶段'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '说明'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (mounted && created == true && name.text.trim().isNotEmpty) {
      setState(() {
        _relations.add(
          RoleRelation(
            id: newEntityId('relation'),
            targetRoleId: targetId,
            name: name.text.trim(),
            direction: direction,
            description: description.text.trim(),
            stage: stage.text.trim(),
          ),
        );
      });
    }
    // The dialog remains in the overlay during its reverse transition.
    // Keep its text controllers alive until its TextFields are unmounted.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    description.dispose();
    stage.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final enteredName = _fields['name']!.text.trim();
    final avatarSource = enteredName.isNotEmpty
        ? enteredName
        : role.name.trim().isNotEmpty
        ? role.name.trim()
        : '未';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text(widget.isNew ? '新建角色' : '编辑角色'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.viewInsetsOf(context).bottom + 32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        child: Text(
                          avatarSource.characters.first,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fields['name']!.text.trim().isEmpty
                                  ? '未命名角色'
                                  : _fields['name']!.text.trim(),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '12 项基础字段 · 本书共用模板',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _ReferenceField(
                    label: '${_baseLabel('name', '姓名')} *',
                    controller: _fields['name']!,
                    autofocus: widget.isNew,
                    onChanged: (_) => setState(() {}),
                  ),
                  _baseInput('alias', '别名', _fields['alias']!),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _baseInput('age', '年龄', _fields['age']!)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _baseInput(
                          'identity',
                          '身份 / 职业',
                          _fields['identity']!,
                        ),
                      ),
                    ],
                  ),
                  _baseInput('goal', '目标 / 动机', _fields['goal']!, maxLines: 3),
                  _ReferenceExpansionGroup(
                    title: '外貌、性格与经历',
                    filled: _filledCount([
                      'appearance',
                      'personality',
                      'background',
                    ]),
                    total: 3,
                    children: [
                      _baseInput(
                        'appearance',
                        '外貌',
                        _fields['appearance']!,
                        maxLines: 4,
                      ),
                      _baseInput(
                        'personality',
                        '性格',
                        _fields['personality']!,
                        maxLines: 4,
                      ),
                      _baseInput(
                        'background',
                        '背景经历',
                        _fields['background']!,
                        maxLines: 5,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ReferenceExpansionGroup(
                    title: '能力、弱点与人物关系',
                    filled:
                        _filledCount(['ability', 'weakness']) +
                        (_relations.isEmpty ? 0 : 1),
                    total: 3,
                    children: [
                      _baseInput(
                        'ability',
                        '能力 / 特长',
                        _fields['ability']!,
                        maxLines: 4,
                      ),
                      _baseInput(
                        'weakness',
                        '弱点',
                        _fields['weakness']!,
                        maxLines: 4,
                      ),
                      if (_baseEnabled('relationships'))
                        Row(
                          children: [
                            const Expanded(child: Text('人物关系')),
                            TextButton.icon(
                              onPressed: _addRelation,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('新增'),
                            ),
                          ],
                        ),
                      if (_baseEnabled('relationships') && _relations.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: Text('还没有结构化人物关系。'),
                        ),
                      if (_baseEnabled('relationships'))
                        ..._relations.map((relation) {
                          final target = widget.allRoles
                              .where((item) => item.id == relation.targetRoleId)
                              .firstOrNull;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${relation.name} · ${target?.name ?? '已删除角色'}',
                            ),
                            subtitle: Text(
                              [
                                relation.direction,
                                relation.stage,
                                relation.description,
                              ].where((value) => value.isNotEmpty).join(' · '),
                            ),
                            trailing: IconButton(
                              tooltip: '移除关系',
                              onPressed: () =>
                                  setState(() => _relations.remove(relation)),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          );
                        }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ReferenceExpansionGroup(
                    title: '简介、标签与备注',
                    filled: _filledCount(['description', 'tags', 'notes']),
                    total: 3,
                    children: [
                      _baseInput(
                        'description',
                        '一句话简介',
                        _fields['description']!,
                        maxLines: 3,
                      ),
                      _ReferenceField(
                        label: '分类标签',
                        controller: _fields['tags']!,
                      ),
                      _baseInput('notes', '备注', _fields['notes']!, maxLines: 5),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _CustomFieldsSection(
                    fields: _customFields,
                    values: _customValues,
                    originalSharedIds: widget.sharedFields
                        .map((field) => field.id)
                        .toSet(),
                    onChanged: (fieldId, value) =>
                        _customValues[fieldId] = value,
                    onAdd: _addCustomField,
                    onRemove: (field) => setState(() {
                      _customFields.remove(field);
                      _customValues.remove(field.id);
                    }),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '基础字段共用；自定义条目可仅用于此角色，或加入本书角色模板。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _filledCount(List<String> keys) =>
      keys.where((key) => _fields[key]?.text.trim().isNotEmpty == true).length;

  CustomFieldDefinition? _baseDefinition(String id) =>
      widget.baseFields.where((field) => field.id == id).firstOrNull;

  bool _baseEnabled(String id) {
    final definition = _baseDefinition(id);
    return definition == null || definition.enabled && !definition.deleted;
  }

  String _baseLabel(String id, String fallback) =>
      _baseDefinition(id)?.name ?? fallback;

  Widget _baseInput(
    String id,
    String fallback,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    if (!_baseEnabled(id)) return const SizedBox.shrink();
    return _ReferenceField(
      label: _baseLabel(id, fallback),
      controller: controller,
      maxLines: maxLines,
    );
  }
}

class WorldDetailPage extends StatefulWidget {
  const WorldDetailPage({
    super.key,
    required this.initialWorld,
    required this.controller,
  });

  final WorldCard initialWorld;
  final AppController controller;

  @override
  State<WorldDetailPage> createState() => _WorldDetailPageState();
}

class _WorldDetailPageState extends State<WorldDetailPage> {
  late WorldCard _world = widget.initialWorld;

  Future<void> _search() async {
    final selected = await showSearch<WorldCard?>(
      context: context,
      delegate: _WorldCardSearchDelegate(
        widget.controller.activeBook?.worlds ?? const [],
      ),
    );
    if (selected != null && mounted) setState(() => _world = selected);
  }

  void _navigateBookPage(WorkspacePage page) {
    Navigator.pop(context);
    widget.controller.navigateBook(page);
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<WorldCard>(
      context,
      MaterialPageRoute(
        builder: (context) => WorldEditPage(
          world: _world,
          baseFields: widget.controller.activeBook?.worldBaseFields ?? const [],
          sharedFields: (widget.controller.activeBook?.worldFields ?? const [])
              .where((field) => field.enabled && !field.deleted)
              .toList(),
        ),
      ),
    );
    if (updated == null || !mounted) return;
    widget.controller.saveWorld(updated);
    setState(() => _world = updated);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除设定？'),
        content: const Text('正文不会被改写；设定数据会保留软删除记录。'),
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
    if (confirmed != true || !mounted) return;
    widget.controller.deleteWorld(_world.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dedicated = _world.details.entries.where(
      (entry) => entry.value.isNotEmpty,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('世界观详情'),
        actions: [
          IconButton(
            tooltip: '搜索世界观',
            onPressed: _search,
            icon: const Icon(Icons.search_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _delete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _SoftLabel(text: _world.type),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _world.title,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            if (_world.description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _world.description,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(onPressed: _edit, child: const Text('编辑')),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _ReferenceDetailCard(
                    title: '简介',
                    body: _world.description.isEmpty
                        ? '尚未填写'
                        : _world.description,
                  ),
                  const SizedBox(height: 14),
                  _ReferenceDetailCard(
                    title: '规则与限制',
                    body: _world.rule.isEmpty ? '尚未填写' : _world.rule,
                  ),
                  if (_world.features.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _ReferenceDetailCard(title: '核心特点', body: _world.features),
                  ],
                  if (dedicated.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text(
                      '类别专属信息',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    ...dedicated.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 108,
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(child: Text(entry.value)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  _DetailSection(
                    title: '自定义条目',
                    values: {
                      for (final field
                          in [
                            ...(widget.controller.activeBook?.worldFields ??
                                const <CustomFieldDefinition>[]),
                            ..._world.customFields,
                          ].where(
                            (field) =>
                                field.scope != 'type' ||
                                field.appliesTo == _world.type,
                          ))
                        field.name: _customValueText(
                          _world.customValues[field.id],
                        ),
                    },
                  ),
                  if (_world.references.isNotEmpty ||
                      _world.tags.isNotEmpty ||
                      _world.notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_world.references.isNotEmpty)
                          _OutlineLabel(text: '关联：${_world.references}'),
                        if (_world.tags.isNotEmpty)
                          ..._world.tags.map((tag) => _OutlineLabel(text: tag)),
                        if (_world.notes.isNotEmpty)
                          const _SoftLabel(text: '作者私有'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: 1,
          onDestinationSelected: (index) => _navigateBookPage(
            const [
              WorkspacePage.writing,
              WorkspacePage.characters,
              WorkspacePage.timeline,
              WorkspacePage.export,
            ][index],
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.edit_note_rounded),
              label: '写作',
            ),
            NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              label: '设定',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_tree_outlined),
              label: '情节',
            ),
            NavigationDestination(
              icon: Icon(Icons.ios_share_rounded),
              label: '导出',
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldCardSearchDelegate extends SearchDelegate<WorldCard?> {
  _WorldCardSearchDelegate(this.worlds);

  final List<WorldCard> worlds;

  @override
  String? get searchFieldLabel => '搜索世界观资料';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: '清空',
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: '返回',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_ios_new_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final needle = query.trim().toLowerCase();
    final result = worlds
        .where(
          (world) =>
              needle.isEmpty ||
              world.title.toLowerCase().contains(needle) ||
              world.type.toLowerCase().contains(needle) ||
              world.description.toLowerCase().contains(needle),
        )
        .toList();
    if (result.isEmpty) return const Center(child: Text('没有找到匹配设定'));
    return ListView.separated(
      itemCount: result.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final world = result[index];
        return ListTile(
          title: Text(world.title),
          subtitle: Text('${world.type} · ${world.description}'),
          onTap: () => close(context, world),
        );
      },
    );
  }
}

class _ReferenceDetailCard extends StatelessWidget {
  const _ReferenceDetailCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                height: 1.55,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftLabel extends StatelessWidget {
  const _SoftLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.onPrimaryContainer),
      ),
    );
  }
}

class _OutlineLabel extends StatelessWidget {
  const _OutlineLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

const _worldTypeFields = <String, List<String>>{
  '地点': ['所属地区', '环境', '重要建筑'],
  '组织': ['宗旨', '成员', '组织结构'],
  '世界规则': ['来源', '使用条件', '代价'],
  '物品': ['用途', '持有者', '来历'],
  '历史': ['年代', '参与者', '影响'],
  '自定义': [],
};

class WorldEditPage extends StatefulWidget {
  const WorldEditPage({
    super.key,
    required this.world,
    this.baseFields = const [],
    this.sharedFields = const [],
    this.isNew = false,
  });

  final WorldCard world;
  final List<CustomFieldDefinition> baseFields;
  final List<CustomFieldDefinition> sharedFields;
  final bool isNew;

  @override
  State<WorldEditPage> createState() => _WorldEditPageState();
}

class _WorldEditPageState extends State<WorldEditPage> {
  late String _type = _worldTypeFields.containsKey(widget.world.type)
      ? widget.world.type
      : '自定义';
  late final Map<String, TextEditingController> _fields = {
    'title': TextEditingController(text: widget.world.title),
    'description': TextEditingController(text: widget.world.description),
    'features': TextEditingController(text: widget.world.features),
    'rule': TextEditingController(text: widget.world.rule),
    'references': TextEditingController(text: widget.world.references),
    'notes': TextEditingController(text: widget.world.notes),
    'tags': TextEditingController(text: widget.world.tags.join('、')),
  };
  late final Map<String, TextEditingController> _details = {
    for (final name in {
      ..._worldTypeFields.values.expand((items) => items),
      ...widget.world.details.keys,
    })
      name: TextEditingController(text: widget.world.details[name] ?? ''),
  };
  late final List<CustomFieldDefinition> _customFields = [
    ...widget.sharedFields,
    ...widget.world.customFields,
  ].map(_copyCustomField).toList();
  late final Map<String, dynamic> _customValues = {
    for (final entry in widget.world.customValues.entries)
      entry.key: entry.value is List
          ? List<String>.from(entry.value as List)
          : entry.value,
  };

  @override
  void dispose() {
    for (final controller in [..._fields.values, ..._details.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final title = _fields['title']!.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写设定名称')));
      return;
    }
    Navigator.pop(
      context,
      WorldCard(
        id: widget.world.id,
        title: title,
        type: _type,
        description: _fields['description']!.text.trim(),
        features: _fields['features']!.text.trim(),
        rule: _fields['rule']!.text.trim(),
        references: _fields['references']!.text.trim(),
        notes: _fields['notes']!.text.trim(),
        tags: _splitValues(_fields['tags']!.text),
        details: {
          for (final entry in _details.entries)
            if (entry.value.text.trim().isNotEmpty)
              entry.key: entry.value.text.trim(),
        },
        customFields: _customFields,
        customValues: _customValues,
      ),
    );
  }

  Future<void> _addCustomField() async {
    final field = await _createCustomFieldDialog(
      context,
      world: true,
      appliesTo: _type,
    );
    if (field == null) return;
    setState(() {
      _customFields.add(field);
      _customValues[field.id] = field.type == 'multiChoice' ? <String>[] : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeNames = _worldTypeFields[_type] ?? const <String>[];
    final inactiveValues = _details.entries
        .where(
          (entry) =>
              !activeNames.contains(entry.key) && entry.value.text.isNotEmpty,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(widget.isNew ? '新建设定' : '编辑设定'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 40,
          ),
          children: [
            _FormSection(
              title: '共用信息',
              children: [
                _formField(
                  _fields['title']!,
                  _worldBaseLabel('title', '名称'),
                  autofocus: widget.isNew,
                ),
                if (_worldBaseEnabled('type'))
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: InputDecoration(
                      labelText: _worldBaseLabel('type', '类别'),
                    ),
                    items: _worldTypeFields.keys
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _type = value ?? _type),
                  ),
                const SizedBox(height: 12),
                _worldBaseInput(
                  'description',
                  '简介',
                  _fields['description']!,
                  maxLines: 4,
                ),
                _worldBaseInput(
                  'features',
                  '核心特点',
                  _fields['features']!,
                  maxLines: 4,
                ),
                _worldBaseInput('rule', '规则与限制', _fields['rule']!, maxLines: 5),
                _worldBaseInput(
                  'references',
                  '关联资料',
                  _fields['references']!,
                  maxLines: 4,
                ),
                _worldBaseInput('notes', '备注', _fields['notes']!, maxLines: 5),
                _formField(_fields['tags']!, '分类标签（用顿号或逗号分隔）'),
              ],
            ),
            if (activeNames.isNotEmpty)
              _FormSection(
                title: '$_type专属字段',
                children: activeNames
                    .map(
                      (name) => _formField(_details[name]!, name, maxLines: 4),
                    )
                    .toList(),
              ),
            if (inactiveValues.isNotEmpty)
              Card(
                child: ExpansionTile(
                  title: Text('其他类别内容（${inactiveValues.length}）'),
                  subtitle: const Text('切回原类别后可继续编辑'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: inactiveValues
                      .map(
                        (entry) =>
                            _formField(entry.value, entry.key, maxLines: 4),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 14),
            _CustomFieldsSection(
              fields: _customFields
                  .where(
                    (field) =>
                        field.scope != 'type' || field.appliesTo == _type,
                  )
                  .toList(),
              values: _customValues,
              originalSharedIds: widget.sharedFields
                  .map((field) => field.id)
                  .toSet(),
              onChanged: (fieldId, value) => _customValues[fieldId] = value,
              onAdd: _addCustomField,
              onRemove: (field) => setState(() {
                _customFields.remove(field);
                _customValues.remove(field.id);
              }),
            ),
          ],
        ),
      ),
    );
  }

  CustomFieldDefinition? _worldBaseDefinition(String id) =>
      widget.baseFields.where((field) => field.id == id).firstOrNull;

  bool _worldBaseEnabled(String id) {
    final definition = _worldBaseDefinition(id);
    return definition == null || definition.enabled && !definition.deleted;
  }

  String _worldBaseLabel(String id, String fallback) =>
      _worldBaseDefinition(id)?.name ?? fallback;

  Widget _worldBaseInput(
    String id,
    String fallback,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    if (!_worldBaseEnabled(id)) return const SizedBox.shrink();
    return _formField(
      controller,
      _worldBaseLabel(id, fallback),
      maxLines: maxLines,
    );
  }
}

CustomFieldDefinition _copyCustomField(CustomFieldDefinition field) =>
    CustomFieldDefinition(
      id: field.id,
      name: field.name,
      type: field.type,
      scope: field.scope,
      appliesTo: field.appliesTo,
      enabled: field.enabled,
      required: field.required,
      deleted: field.deleted,
      options: List<String>.from(field.options),
    );

String _customValueText(dynamic value) {
  if (value is Iterable) return value.map((item) => '$item').join('、');
  return value?.toString() ?? '';
}

String _customTypeLabel(String type) => switch (type) {
  'longText' => '长文本',
  'number' => '数字',
  'singleChoice' => '单选',
  'multiChoice' => '多选',
  _ => '短文本',
};

String _customScopeLabel(CustomFieldDefinition field) => switch (field.scope) {
  'book' => '本书共用',
  'type' => '${field.appliesTo ?? '当前'}类别共用',
  _ => '仅此条目',
};

Future<CustomFieldDefinition?> _createCustomFieldDialog(
  BuildContext context, {
  required bool world,
  String? appliesTo,
}) async {
  final name = TextEditingController();
  final options = TextEditingController();
  var type = 'shortText';
  var scope = 'local';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(world ? '新增世界观条目' : '新增角色条目'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '条目名称 *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '内容类型'),
                  items:
                      const [
                            'shortText',
                            'longText',
                            'number',
                            'singleChoice',
                            'multiChoice',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_customTypeLabel(value)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? 'shortText'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  decoration: const InputDecoration(labelText: '作用范围'),
                  items: [
                    const DropdownMenuItem(
                      value: 'local',
                      child: Text('仅用于当前卡片'),
                    ),
                    DropdownMenuItem(
                      value: 'book',
                      child: Text(world ? '本书全部世界观' : '本书全部角色'),
                    ),
                    if (world)
                      DropdownMenuItem(
                        value: 'type',
                        child: Text('本书“${appliesTo ?? '当前'}”类别'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => scope = value ?? 'local'),
                ),
                if (type == 'singleChoice' || type == 'multiChoice') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: options,
                    decoration: const InputDecoration(
                      labelText: '选项',
                      hintText: '用顿号或逗号分隔',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    ),
  );
  final trimmedName = name.text.trim();
  final optionValues = _splitValues(options.text);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  name.dispose();
  options.dispose();
  return confirmed == true && trimmedName.isNotEmpty
      ? CustomFieldDefinition(
          id: newEntityId(world ? 'world-field' : 'role-field'),
          name: trimmedName,
          type: type,
          scope: scope,
          appliesTo: scope == 'type' ? appliesTo : null,
          options: optionValues,
        )
      : null;
}

class _CustomFieldsSection extends StatelessWidget {
  const _CustomFieldsSection({
    required this.fields,
    required this.values,
    required this.originalSharedIds,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
  });

  final List<CustomFieldDefinition> fields;
  final Map<String, dynamic> values;
  final Set<String> originalSharedIds;
  final void Function(String fieldId, dynamic value) onChanged;
  final VoidCallback onAdd;
  final ValueChanged<CustomFieldDefinition> onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '自定义条目',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新增'),
                ),
              ],
            ),
            if (fields.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '还没有自定义条目。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ...fields.map(
              (field) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            field.name,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        _OutlineLabel(text: _customTypeLabel(field.type)),
                        const SizedBox(width: 6),
                        _SoftLabel(text: _customScopeLabel(field)),
                        if (!originalSharedIds.contains(field.id))
                          IconButton(
                            tooltip: '删除条目',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onRemove(field),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CustomFieldInput(
                      key: ValueKey(field.id),
                      field: field,
                      value: values[field.id],
                      onChanged: (value) => onChanged(field.id, value),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomFieldInput extends StatelessWidget {
  const _CustomFieldInput({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final CustomFieldDefinition field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    if (field.type == 'singleChoice') {
      final current = field.options.contains(value) ? value as String : null;
      return DropdownButtonFormField<String>(
        initialValue: current,
        decoration: const InputDecoration(hintText: '请选择'),
        items: field.options
            .map(
              (option) => DropdownMenuItem(value: option, child: Text(option)),
            )
            .toList(),
        onChanged: onChanged,
      );
    }
    if (field.type == 'multiChoice') {
      final selected = value is Iterable
          ? value.map((item) => '$item').toSet()
          : <String>{};
      return FormField<Set<String>>(
        initialValue: selected,
        builder: (state) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: field.options.map((option) {
            final checked = state.value?.contains(option) ?? false;
            return FilterChip(
              label: Text(option),
              selected: checked,
              onSelected: (enabled) {
                final next = {...state.value ?? <String>{}};
                enabled ? next.add(option) : next.remove(option);
                state.didChange(next);
                onChanged(next.toList());
              },
            );
          }).toList(),
        ),
      );
    }
    return TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: switch (field.type) {
        'number' => const TextInputType.numberWithOptions(decimal: true),
        'longText' => TextInputType.multiline,
        _ => TextInputType.text,
      },
      textInputAction: field.type == 'longText'
          ? TextInputAction.newline
          : null,
      minLines: field.type == 'longText' ? 3 : 1,
      maxLines: field.type == 'longText' ? 6 : 1,
      onChanged: onChanged,
      decoration: const InputDecoration(isDense: true),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.values});

  final String title;
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) {
    final visible = values.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...visible.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        entry.value,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(height: 1.55),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationSection extends StatelessWidget {
  const _RelationSection({required this.relations, required this.allRoles});

  final List<RoleRelation> relations;
  final List<RoleCard> allRoles;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('人物关系', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...relations.map((relation) {
              final target = allRoles
                  .where((item) => item.id == relation.targetRoleId)
                  .firstOrNull;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hub_outlined),
                title: Text('${relation.name} · ${target?.name ?? '已删除角色'}'),
                subtitle: Text(
                  [
                    relation.direction,
                    relation.stage,
                    relation.description,
                  ].where((value) => value.isNotEmpty).join(' · '),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _RelationshipLink {
  const _RelationshipLink({
    required this.other,
    required this.relation,
    required this.outgoing,
  });

  final RoleCard other;
  final RoleRelation relation;
  final bool outgoing;
}

class _RoleRelationshipMapPage extends StatefulWidget {
  const _RoleRelationshipMapPage({
    required this.role,
    required this.roles,
    required this.controller,
  });

  final RoleCard role;
  final List<RoleCard> roles;
  final AppController controller;

  @override
  State<_RoleRelationshipMapPage> createState() =>
      _RoleRelationshipMapPageState();
}

class _RoleRelationshipMapPageState extends State<_RoleRelationshipMapPage> {
  final TransformationController _graphTransform = TransformationController();
  bool _initialScaleSet = false;

  @override
  void dispose() {
    _graphTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final item in widget.roles) item.id: item};
    final links =
        <_RelationshipLink>[
          for (final relation in widget.role.relations)
            if (byId[relation.targetRoleId] case final RoleCard other)
              _RelationshipLink(
                other: other,
                relation: relation,
                outgoing: true,
              ),
          for (final other in widget.roles)
            if (other.id != widget.role.id)
              for (final relation in other.relations)
                if (relation.targetRoleId == widget.role.id)
                  _RelationshipLink(
                    other: other,
                    relation: relation,
                    outgoing: false,
                  ),
        ]..sort((a, b) {
          final nameOrder = a.other.name.compareTo(b.other.name);
          return nameOrder != 0
              ? nameOrder
              : a.relation.name.compareTo(b.relation.name);
        });
    final scheme = Theme.of(context).colorScheme;
    const canvasWidth = 650.0;
    final canvasHeight = math.max(320.0, 60.0 + links.length * 116.0);
    final rootTop = canvasHeight / 2 - 38;
    if (!_initialScaleSet) {
      final screenSize = MediaQuery.sizeOf(context);
      final width = screenSize.width;
      final scale = math.min(1.0, (width - 24) / canvasWidth);
      final availableHeight =
          screenSize.height -
          MediaQuery.paddingOf(context).vertical -
          kToolbarHeight -
          100;
      _graphTransform.value = Matrix4.diagonal3Values(scale, scale, 1)
        ..setTranslationRaw(
          (width - canvasWidth * scale) / 2,
          availableHeight / 2 - (rootTop + 38) * scale,
          0,
        );
      _initialScaleSet = true;
    }
    return Scaffold(
      appBar: AppBar(title: Text('${widget.role.name} · 人物关系')),
      body: SafeArea(
        top: false,
        child: links.isEmpty
            ? const Center(child: Text('还没有与这个角色相关的人物关系。'))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '拖动查看 · 双指缩放 · 点击角色查看详情',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: InteractiveViewer(
                        transformationController: _graphTransform,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(100),
                        minScale: .4,
                        maxScale: 2.5,
                        child: SizedBox(
                          width: canvasWidth,
                          height: canvasHeight,
                          child: Stack(
                            children: [
                              CustomPaint(
                                size: Size(canvasWidth, canvasHeight),
                                painter: _RelationshipLinesPainter(
                                  links: links,
                                  rootCenterY: rootTop + 38,
                                  color: scheme.primary,
                                ),
                              ),
                              Positioned(
                                left: 20,
                                top: rootTop,
                                width: 180,
                                child: _RelationshipNode(
                                  key: const ValueKey('relationship-root-node'),
                                  name: widget.role.name,
                                  detail: widget.role.identity.isEmpty
                                      ? '当前角色'
                                      : widget.role.identity,
                                  primary: true,
                                ),
                              ),
                              for (final (index, link) in links.indexed)
                                Positioned(
                                  left: 424,
                                  top: 50 + index * 116.0,
                                  width: 204,
                                  child: _RelationshipNode(
                                    key: ValueKey(
                                      'relationship-node-${link.relation.id}',
                                    ),
                                    name: link.other.name,
                                    detail: [
                                      link.relation.name,
                                      if (link.relation.stage.isNotEmpty)
                                        link.relation.stage,
                                    ].join(' · '),
                                    onTap: () => Navigator.push<void>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => RoleDetailPage(
                                          initialRole: link.other,
                                          controller: widget.controller,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                    child: Text(
                      '箭头表示关系方向；双向关系两端均有箭头。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RelationshipNode extends StatelessWidget {
  const _RelationshipNode({
    super.key,
    required this.name,
    required this.detail,
    this.primary = false,
    this.onTap,
  });

  final String name;
  final String detail;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: primary ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationshipLinesPainter extends CustomPainter {
  const _RelationshipLinesPainter({
    required this.links,
    required this.rootCenterY,
    required this.color,
  });

  final List<_RelationshipLink> links;
  final double rootCenterY;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final (index, link) in links.indexed) {
      final start = Offset(200, rootCenterY);
      final end = Offset(424, 88 + index * 116.0);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(286, start.dy, 338, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
      if (link.outgoing || link.relation.direction == '双向') {
        _drawArrow(canvas, paint, end, const Offset(1, 0));
      }
      if (!link.outgoing || link.relation.direction == '双向') {
        _drawArrow(canvas, paint, start, const Offset(-1, 0));
      }
    }
  }

  void _drawArrow(Canvas canvas, Paint paint, Offset tip, Offset direction) {
    const arrowSize = 8.0;
    final base = tip - direction * arrowSize;
    final perpendicular = Offset(-direction.dy, direction.dx) * 5;
    canvas.drawPath(
      Path()
        ..moveTo(base.dx + perpendicular.dx, base.dy + perpendicular.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(base.dx - perpendicular.dx, base.dy - perpendicular.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RelationshipLinesPainter oldDelegate) =>
      oldDelegate.links != links ||
      oldDelegate.rootCenterY != rootCenterY ||
      oldDelegate.color != color;
}

class _ReferenceField extends StatelessWidget {
  const _ReferenceField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            key: ValueKey('field-$label'),
            controller: controller,
            autofocus: autofocus,
            minLines: maxLines == 1 ? 1 : 2,
            maxLines: maxLines,
            onChanged: onChanged,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceExpansionGroup extends StatelessWidget {
  const _ReferenceExpansionGroup({
    required this.title,
    required this.filled,
    required this.total,
    required this.children,
  });

  final String title;
  final int filled;
  final int total;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filled > 0)
              Text('$filled 项已填', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
        children: children,
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

Widget _formField(
  TextEditingController controller,
  String label, {
  int maxLines = 1,
  bool autofocus = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: maxLines == 1 ? 1 : 2,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

List<String> _splitValues(String value) => value
    .split(RegExp(r'[,，、]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList();
