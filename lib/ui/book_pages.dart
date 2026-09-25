import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/library_data.dart';
import '../state/app_controller.dart';
import 'card_pages.dart';

class BookSettingsPage extends StatefulWidget {
  const BookSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<BookSettingsPage> createState() => _BookSettingsPageState();
}

class _BookSettingsPageState extends State<BookSettingsPage> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final book = widget.controller.activeBook;
    if (book == null) return const Center(child: Text('请先从书架打开一本书。'));
    final baseFields = _tab == 0 ? book.roleBaseFields : book.worldBaseFields;
    final enabledFields = baseFields
        .where((field) => field.enabled && !field.deleted)
        .toList();
    return Column(
      children: [
        const _FixedPageHeader(title: '人物与世界', subtitle: '共用基础模板，写下各自的不同。'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('create-setting-entry'),
                  onPressed: () =>
                      _tab == 0 ? _createRole(context) : _createWorld(context),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(_tab == 0 ? '新建角色卡' : '新建世界观条目'),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _PageScroller(
            topPadding: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsTypeTabs(
                  value: _tab,
                  onChanged: (value) => setState(() => _tab = value),
                ),
                const SizedBox(height: 14),
                _TemplateBanner(
                  count: enabledFields.length,
                  summary: enabledFields
                      .take(4)
                      .map((field) => field.name)
                      .join('、'),
                  onManage: () => _showTemplateFields(context, book),
                ),
                const SizedBox(height: 14),
                if (_tab == 0)
                  _RoleGrid(
                    book: book,
                    roles: book.roles,
                    controller: widget.controller,
                  )
                else
                  _WorldGrid(
                    worlds: book.worlds,
                    controller: widget.controller,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showTemplateFields(BuildContext context, Book book) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .9,
        child: _TemplateManagerSheet(
          controller: widget.controller,
          role: _tab == 0,
        ),
      ),
    );
  }

  Future<void> _createRole(BuildContext context) async {
    final role = await Navigator.push<RoleCard>(
      context,
      MaterialPageRoute(
        builder: (context) => RoleEditPage(
          role: widget.controller.newRoleDraft(),
          allRoles: widget.controller.activeBook?.roles ?? const [],
          baseFields: widget.controller.activeBook?.roleBaseFields ?? const [],
          sharedFields: (widget.controller.activeBook?.roleFields ?? const [])
              .where((field) => field.enabled && !field.deleted)
              .toList(),
          isNew: true,
        ),
      ),
    );
    if (role != null) widget.controller.saveRole(role);
  }

  Future<void> _createWorld(BuildContext context) async {
    final world = await Navigator.push<WorldCard>(
      context,
      MaterialPageRoute(
        builder: (context) => WorldEditPage(
          world: widget.controller.newWorldDraft(),
          baseFields: widget.controller.activeBook?.worldBaseFields ?? const [],
          sharedFields: (widget.controller.activeBook?.worldFields ?? const [])
              .where((field) => field.enabled && !field.deleted)
              .toList(),
          isNew: true,
        ),
      ),
    );
    if (world != null) widget.controller.saveWorld(world);
  }
}

class _TemplateManagerSheet extends StatelessWidget {
  const _TemplateManagerSheet({required this.controller, required this.role});

  final AppController controller;
  final bool role;

  Future<void> _edit(
    BuildContext context,
    CustomFieldDefinition field, {
    required bool base,
  }) async {
    final updated = await _showTemplateFieldDialog(
      context,
      initial: field,
      base: base,
    );
    if (updated != null) {
      controller.updateTemplateField(role: role, base: base, field: updated);
    }
  }

  Future<void> _add(BuildContext context) async {
    final field = await _showTemplateFieldDialog(context);
    if (field == null) return;
    controller.addTemplateField(
      role: role,
      name: field.name,
      type: field.type,
      options: field.options,
    );
  }

  Future<void> _delete(
    BuildContext context,
    CustomFieldDefinition field,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除自定义字段？'),
        content: Text('“${field.name}”将不再显示在新表单中，已填内容保留在本地数据内。'),
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
    if (confirmed == true) {
      controller.deleteTemplateField(role: role, fieldId: field.id);
    }
  }

  Widget _fieldTile(
    BuildContext context,
    CustomFieldDefinition field, {
    required bool base,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: Switch(
          value: field.enabled && !field.deleted,
          onChanged: field.required
              ? null
              : (enabled) => controller.updateTemplateField(
                  role: role,
                  base: base,
                  field: _copyTemplateField(field)..enabled = enabled,
                ),
        ),
        title: Text(field.name),
        subtitle: Text(
          [
            _fieldTypeLabel(field.type),
            if (field.required) '必填',
            if (!field.enabled || field.deleted) '已停用',
          ].join(' · '),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '字段操作',
          onSelected: (value) {
            if (value == 'edit') _edit(context, field, base: base);
            if (value == 'up') {
              controller.moveTemplateField(
                role: role,
                base: base,
                fieldId: field.id,
                delta: -1,
              );
            }
            if (value == 'down') {
              controller.moveTemplateField(
                role: role,
                base: base,
                fieldId: field.id,
                delta: 1,
              );
            }
            if (value == 'delete') _delete(context, field);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑字段')),
            const PopupMenuItem(value: 'up', child: Text('上移')),
            const PopupMenuItem(value: 'down', child: Text('下移')),
            if (!base) const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final book = controller.activeBook;
      if (book == null) return const SizedBox.shrink();
      final baseFields = role ? book.roleBaseFields : book.worldBaseFields;
      final customFields = (role ? book.roleFields : book.worldFields)
          .where((field) => !field.deleted)
          .toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Text(
            role ? '角色卡字段模板' : '世界观字段模板',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '开关控制表单中是否显示；点菜单可改名、更改类型或调整顺序。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text('基础字段', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...baseFields.map((field) => _fieldTile(context, field, base: true)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  '自定义字段',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新增字段'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (customFields.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('还没有自定义字段，可在这里新增“阵营”等条目。'),
              ),
            )
          else
            ...customFields.map(
              (field) => _fieldTile(context, field, base: false),
            ),
        ],
      );
    },
  );
}

Future<CustomFieldDefinition?> _showTemplateFieldDialog(
  BuildContext context, {
  CustomFieldDefinition? initial,
  bool base = false,
}) async {
  final name = TextEditingController(text: initial?.name ?? '');
  final options = TextEditingController(text: initial?.options.join('、') ?? '');
  var type = initial?.type ?? 'shortText';
  var required = initial?.required ?? false;
  final result = await showDialog<CustomFieldDefinition>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(initial == null ? '新增自定义字段' : '编辑字段'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '字段名称'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '内容类型'),
                  items:
                      const [
                            ('shortText', '短文本'),
                            ('longText', '长文本'),
                            ('number', '数字'),
                            ('singleChoice', '单选'),
                            ('multiChoice', '多选'),
                            ('date', '日期'),
                            ('boolean', '开关'),
                          ]
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.$1,
                              child: Text(item.$2),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? type),
                ),
                if (type == 'singleChoice' || type == 'multiChoice') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: options,
                    decoration: const InputDecoration(
                      labelText: '选项',
                      hintText: '例如：主角阵营、中立、反派阵营',
                    ),
                  ),
                ],
                if (!base || initial?.required != true)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('必填'),
                    value: required,
                    onChanged: (value) =>
                        setDialogState(() => required = value),
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
              if (name.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                CustomFieldDefinition(
                  id: initial?.id ?? '',
                  name: name.text.trim(),
                  type: type,
                  scope: initial?.scope ?? 'book',
                  appliesTo: initial?.appliesTo,
                  enabled: initial?.enabled ?? true,
                  required: required,
                  deleted: false,
                  options: _splitTemplateOptions(options.text),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  name.dispose();
  options.dispose();
  return result;
}

CustomFieldDefinition _copyTemplateField(CustomFieldDefinition field) =>
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

List<String> _splitTemplateOptions(String value) => value
    .split(RegExp(r'[、，,\n]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

String _fieldTypeLabel(String type) => switch (type) {
  'longText' => '长文本',
  'number' => '数字',
  'choice' || 'singleChoice' => '单选',
  'multiChoice' => '多选',
  'date' => '日期',
  'boolean' => '开关',
  _ => '短文本',
};

class _RoleGrid extends StatelessWidget {
  const _RoleGrid({
    required this.book,
    required this.roles,
    required this.controller,
  });

  final Book book;
  final List<RoleCard> roles;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (roles.isEmpty) return const _EmptyPanel(text: '这本书还没有角色卡。');
    return _ResponsiveGrid(
      children: roles
          .map(
            (role) =>
                _RoleCardView(book: book, role: role, controller: controller),
          )
          .toList(),
    );
  }
}

class _RoleCardView extends StatelessWidget {
  const _RoleCardView({
    required this.book,
    required this.role,
    required this.controller,
  });

  final Book book;
  final RoleCard role;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final relatedChapters = book.events
        .where(
          (event) =>
              event.chapterId != null &&
              (event.roleIds.contains(role.id) ||
                  event.persons.contains(role.name)),
        )
        .map((event) => event.chapterId)
        .toSet()
        .length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                RoleDetailPage(initialRole: role, controller: controller),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(child: Text(role.name.characters.first)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          role.identity.isEmpty ? '身份待补充' : role.identity,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                role.description.isEmpty ? '尚未填写角色简介。' : role.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (role.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: role.tags
                      .map((tag) => Chip(label: Text(tag)))
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$relatedChapters 个关联章节',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '基础字段＋自定义  ↗',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldGrid extends StatelessWidget {
  const _WorldGrid({required this.worlds, required this.controller});

  final List<WorldCard> worlds;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (worlds.isEmpty) return const _EmptyPanel(text: '这本书还没有世界观设定。');
    return _ResponsiveGrid(
      children: worlds
          .map((world) => _WorldCardView(world: world, controller: controller))
          .toList(),
    );
  }
}

class _WorldCardView extends StatelessWidget {
  const _WorldCardView({required this.world, required this.controller});

  final WorldCard world;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                WorldDetailPage(initialWorld: world, controller: controller),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: Icon(
                      Icons.public_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      world.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    world.type,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                world.description.isEmpty ? '尚未填写简介。' : world.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (world.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: world.tags
                      .map((tag) => Chip(label: Text(tag)))
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${world.details.length} 个类别专属项',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '基础字段＋自定义  ↗',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PlotTool { structure, outline, clues, notes }

enum _StoryView { axis, mind, flow }

class StoryPlanningPage extends StatefulWidget {
  const StoryPlanningPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<StoryPlanningPage> createState() => _StoryPlanningPageState();
}

class _StoryPlanningPageState extends State<StoryPlanningPage> {
  _PlotTool _tool = _PlotTool.structure;
  _StoryView _view = _StoryView.axis;
  final Set<String> _selectedTracks = {};
  final Set<String> _collapsedMindGroups = {};
  final ScrollController _timelineController = ScrollController();
  final TransformationController _graphController = TransformationController();

  @override
  void initState() {
    super.initState();
    _graphController.addListener(_handleGraphTransform);
    _selectedTracks.addAll(
      (_book?.tracks ?? const <StoryTrack>[]).take(2).map((track) => track.id),
    );
  }

  @override
  void dispose() {
    _graphController.removeListener(_handleGraphTransform);
    _timelineController.dispose();
    _graphController.dispose();
    super.dispose();
  }

  void _handleGraphTransform() {
    if (mounted && _view != _StoryView.axis) setState(() {});
  }

  Book? get _book => widget.controller.activeBook;

  List<StoryEvent> get _visibleEvents {
    final book = _book;
    if (book == null) return [];
    final selected = _selectedTracks.isEmpty
        ? book.tracks.map((track) => track.id).toSet()
        : _selectedTracks;
    final events = book.events
        .where((event) => event.trackIds.any(selected.contains))
        .toList();
    events.sort(compareTimelineEvents);
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    if (book == null) return const Center(child: Text('请先从书架打开一本书。'));
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      children: [
        const _FixedPageHeader(title: '故事结构', subtitle: '一套事件，三种看故事的方式。'),
        Expanded(
          child: compact && _tool == _PlotTool.structure
              ? _buildMobileStructure(context, book)
              : _PageScroller(
                  maxWidth: 1180,
                  topPadding: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPlotToolTabs(),
                      const SizedBox(height: 16),
                      if (_tool != _PlotTool.structure)
                        Align(
                          alignment: Alignment.centerRight,
                          child: _buildAction(context),
                        ),
                      if (_tool != _PlotTool.structure)
                        const SizedBox(height: 12),
                      switch (_tool) {
                        _PlotTool.structure => _buildStructure(context, book),
                        _PlotTool.outline => _buildOutline(context, book),
                        _PlotTool.clues => _buildClues(context, book),
                        _PlotTool.notes => _buildNotes(context, book),
                      },
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPlotToolTabs() => _ChoiceStrip(
    labels: const ['结构', '大纲', '伏笔', '灵感'],
    selectedIndex: _tool.index,
    onSelected: (index) => setState(() => _tool = _PlotTool.values[index]),
  );

  Widget _buildMobileStructure(BuildContext context, Book book) {
    final scheme = Theme.of(context).colorScheme;
    final selectedTracks = book.tracks
        .where((track) => _selectedTracks.contains(track.id))
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPlotToolTabs(),
          const SizedBox(height: 10),
          _MobileStoryTabs(
            value: _view,
            onChanged: (value) {
              setState(() => _view = value);
              _resetStoryViewport();
            },
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CompactToolButton(
                  label: '管理时间线 · ${selectedTracks.length} 条',
                  onPressed: () => _showTrackSelector(context, book),
                ),
                const SizedBox(width: 8),
                _CompactToolButton(
                  label: '新建事件',
                  onPressed: () => _showEventDialog(context),
                ),
                if (_view == _StoryView.flow) ...[
                  const SizedBox(width: 8),
                  _CompactToolButton(
                    label: '连线',
                    onPressed: () => _showLinkDialog(context),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_view == _StoryView.axis) ...[
                Expanded(child: _buildOrderSelector()),
              ] else ...[
                const Spacer(),
                _SquareToolButton(label: '−', onPressed: () => _zoomGraph(.84)),
                const SizedBox(width: 6),
                _CompactToolSurface(label: '${(_graphScale * 100).round()}%'),
                const SizedBox(width: 6),
                _SquareToolButton(
                  label: '+',
                  onPressed: () => _zoomGraph(1.16),
                ),
                const SizedBox(width: 6),
                _CompactToolButton(label: '适配', onPressed: _resetStoryViewport),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            switch (_view) {
              _StoryView.axis => '按时间层级与同时间排序升序 · 非真实时长比例',
              _StoryView.mind => '点主题折叠，点事件查看；双指缩放与平移',
              _StoryView.flow => '因果与分歧关系 · 箭头表示方向',
            },
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_view) {
              _StoryView.axis => _MobileTimelineCanvas(
                book: book,
                tracks: selectedTracks.isEmpty
                    ? book.tracks.take(2).toList()
                    : selectedTracks,
                events: _visibleEvents,
                controller: _timelineController,
                onEventTap: (event) => _showEventPreview(context, event),
              ),
              _StoryView.mind => _MobileMindCanvas(
                book: book,
                events: _visibleEvents,
                controller: _graphController,
                collapsedGroups: _collapsedMindGroups,
                onToggleGroup: (group) => setState(() {
                  if (!_collapsedMindGroups.remove(group)) {
                    _collapsedMindGroups.add(group);
                  }
                }),
                onEventTap: (event) => _showEventPreview(context, event),
                onAddChild: (group) =>
                    _showEventDialog(context, initialGroup: group),
              ),
              _StoryView.flow => _MobileFlowCanvas(
                book: book,
                // A flow chart represents the whole causal graph. Keeping it
                // tied to timeline filters can silently hide one side of a
                // branch, so every event remains visible here.
                events: book.events,
                controller: _graphController,
                onEventTap: (event) => _showEventPreview(context, event),
              ),
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  double get _graphScale => _graphController.value.storage[0].abs();

  void _zoomGraph(double factor) {
    final next = (_graphScale * factor).clamp(.5, 2.2);
    _graphController.value = Matrix4.diagonal3Values(next, next, 1);
  }

  void _resetStoryViewport() {
    if (_view == _StoryView.axis && _timelineController.hasClients) {
      _timelineController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    final scale = _view == _StoryView.mind ? .54 : .68;
    _graphController.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  Future<void> _showTrackSelector(BuildContext context, Book book) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '管理时间线',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await _showTrackDialog(context);
                      setSheetState(() {});
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '手机端建议同时对照 1–3 条。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              ...book.tracks.map(
                (track) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selectedTracks.contains(track.id),
                  title: Text(track.name),
                  subtitle: Text(track.type),
                  secondary: PopupMenuButton<String>(
                    tooltip: '时间线操作',
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _showTrackDialog(context, existing: track);
                      } else if (value == 'delete') {
                        await _confirmDeleteTrack(context, book, track);
                        _selectedTracks.remove(track.id);
                      }
                      setSheetState(() {});
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(
                        value: 'delete',
                        enabled: book.tracks.length > 1,
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                  onChanged: (value) {
                    if (value == true && _selectedTracks.length >= 3) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('手机端最多同时显示 3 条时间线')),
                      );
                      return;
                    }
                    setState(() {
                      value == true
                          ? _selectedTracks.add(track.id)
                          : _selectedTracks.remove(track.id);
                    });
                    setSheetState(() {});
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTrack(
    BuildContext context,
    Book book,
    StoryTrack track,
  ) async {
    if (book.tracks.length <= 1) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除时间线？'),
        content: Text('事件会保留，并自动改放到其他时间线。\n\n将删除“${track.name}”。'),
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
    if (confirmed == true) widget.controller.deleteTrack(track.id);
  }

  Future<void> _showEventPreview(BuildContext context, StoryEvent event) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              event.storyDate,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(event.description),
            ],
            if (event.persons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('参与角色 · ${event.persons}'),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showEventDialog(context, existing: event);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑事件'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: '删除事件',
                  onPressed: () {
                    widget.controller.deleteEvent(event.id);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) => switch (_tool) {
    _PlotTool.structure => FilledButton.icon(
      onPressed: () => _showEventDialog(context),
      icon: const Icon(Icons.add_rounded),
      label: const Text('新增事件'),
    ),
    _PlotTool.clues => FilledButton.icon(
      onPressed: () => _showClueDialog(context),
      icon: const Icon(Icons.add_rounded),
      label: const Text('新建伏笔'),
    ),
    _PlotTool.notes => FilledButton.icon(
      onPressed: () => _showNoteDialog(context),
      icon: const Icon(Icons.add_rounded),
      label: const Text('记录灵感'),
    ),
    _PlotTool.outline => const SizedBox.shrink(),
  };

  Widget _buildStructure(BuildContext context, Book book) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileStoryTabs(
          value: _view,
          onChanged: (value) => setState(() => _view = value),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...book.tracks.map(
              (track) => FilterChip(
                selected:
                    _selectedTracks.isEmpty ||
                    _selectedTracks.contains(track.id),
                avatar: CircleAvatar(
                  backgroundColor: _trackColor(track.color),
                  radius: 5,
                ),
                label: Text('${track.name} · ${track.type}'),
                onSelected: (_) => _toggleTrack(book, track.id),
              ),
            ),
            TextButton.icon(
              onPressed: () => _showTrackSelector(context, book),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('管理时间线'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _showEventDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建事件'),
            ),
            if (_view == _StoryView.flow && book.events.length > 1)
              TextButton.icon(
                onPressed: () => _showLinkDialog(context),
                icon: const Icon(Icons.link_rounded),
                label: const Text('事件连线'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (_view == _StoryView.axis) ...[
          _buildOrderSelector(),
          const SizedBox(height: 10),
        ],
        if (_visibleEvents.isEmpty)
          const _EmptyPanel(text: '当前时间线还没有事件。')
        else
          switch (_view) {
            _StoryView.axis => _AxisView(book: book, events: _visibleEvents),
            _StoryView.mind => _MindView(book: book, events: _visibleEvents),
            _StoryView.flow => _FlowView(book: book, events: book.events),
          },
      ],
    );
  }

  void _toggleTrack(Book book, String id) {
    setState(() {
      if (_selectedTracks.isEmpty) {
        _selectedTracks.addAll(book.tracks.map((track) => track.id));
      }
      if (!_selectedTracks.remove(id)) _selectedTracks.add(id);
      if (_selectedTracks.length == book.tracks.length) _selectedTracks.clear();
    });
  }

  Widget _buildOrderSelector() => const Row(
    key: ValueKey('timeline-order-rule'),
    children: [
      Icon(Icons.sort_rounded, size: 18),
      SizedBox(width: 6),
      Expanded(child: Text('按总时间层级 ↑，同层按同时间排序 ↑')),
    ],
  );

  Widget _buildOutline(BuildContext context, Book book) {
    return Column(
      children: book.chapters.indexed.map((entry) {
        final (index, chapter) = entry;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(chapter.title),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  chapter.summary.isEmpty ? '尚未填写章节目标。' : chapter.summary,
                ),
              ),
              trailing: Text(
                '${chapter.wordCount} 字\n${chapter.status}',
                textAlign: TextAlign.end,
              ),
              onTap: () {
                widget.controller.selectChapter(chapter.id);
                widget.controller.navigateBook(WorkspacePage.writing);
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildClues(BuildContext context, Book book) {
    if (book.clues.isEmpty) return const _EmptyPanel(text: '还没有记录伏笔。');
    String chapterName(String? id) =>
        book.chapters
            .where((chapter) => chapter.id == id)
            .map((chapter) => chapter.title)
            .firstOrNull ??
        '未关联章节';
    return Column(
      children: book.clues.map((clue) {
        final resolved = clue.actualChapterId?.isNotEmpty == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          clue.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Chip(label: Text(resolved ? '已回收' : '已埋设')),
                      IconButton(
                        key: ValueKey('delete-clue-${clue.id}'),
                        tooltip: '删除伏笔',
                        onPressed: () => _confirmPlanningDelete(
                          context,
                          title: '删除伏笔？',
                          name: clue.title,
                          onDelete: () => widget.controller.deleteClue(clue.id),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  if (clue.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(clue.description),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '埋下 · ${chapterName(clue.originChapterId)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${resolved ? '实际回收' : '计划回收'} · ${chapterName(clue.actualChapterId ?? clue.plannedChapterId)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNotes(BuildContext context, Book book) {
    if (book.notes.isEmpty) return const _EmptyPanel(text: '还没有灵感碎片。');
    return _ResponsiveGrid(
      children: book.notes
          .map(
            (note) => Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const Spacer(),
                        IconButton(
                          key: ValueKey('delete-note-${note.id}'),
                          tooltip: '删除灵感',
                          onPressed: () => _confirmPlanningDelete(
                            context,
                            title: '删除灵感？',
                            name: note.body,
                            onDelete: () =>
                                widget.controller.deleteNote(note.id),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(note.body),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _confirmPlanningDelete(
    BuildContext context, {
    required String title,
    required String name,
    required VoidCallback onDelete,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          '“${name.length > 60 ? '${name.substring(0, 60)}…' : name}”删除后无法恢复。',
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
    if (confirmed == true && mounted) onDelete();
  }

  Future<void> _showTrackDialog(
    BuildContext context, {
    StoryTrack? existing,
  }) async {
    final name = TextEditingController(text: existing?.name ?? '');
    var type = existing?.type ?? '主线';
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新建时间线' : '编辑时间线'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: const ['主线', '角色线', '支线', '世界历史', '平行世界／轮回', '自定义']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? type),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(existing == null ? '创建' : '保存'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      if (existing == null) {
        widget.controller.createTrack(name.text, type);
      } else {
        widget.controller.updateTrack(existing.id, name: name.text, type: type);
      }
    }
    name.dispose();
  }

  Future<void> _showEventDialog(
    BuildContext context, {
    String? initialGroup,
    StoryEvent? existing,
  }) async {
    final book = _book;
    if (book == null) return;
    final title = TextEditingController(text: existing?.title ?? '');
    final group = TextEditingController(
      text: initialGroup ?? existing?.group ?? '',
    );
    final storyDate = TextEditingController(text: existing?.storyDate ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    var chapterId = existing?.chapterId ?? '';
    final timeLevel = TextEditingController(
      text:
          '${existing?.timeLevel ?? book.events.fold<int>(0, (max, event) => event.timeLevel > max ? event.timeLevel : max) + 1}',
    );
    final sameTimeOrder = TextEditingController(
      text: '${existing?.sameTimeOrder ?? 1}',
    );
    String? validationError;
    final selected = <String>{
      ...?existing?.trackIds,
      if (existing == null && book.tracks.isNotEmpty) book.tracks.first.id,
    };
    final selectedRoles = <String>{...?existing?.roleIds};
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新建故事事件' : '编辑故事事件'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '事件名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: group,
                    decoration: const InputDecoration(
                      labelText: '分组',
                      hintText: '例如：来信之谜、林照的选择',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('event-story-date'),
                    controller: storyDate,
                    decoration: const InputDecoration(
                      labelText: '故事时间',
                      hintText: '例如：秋二日 · 夜',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('event-time-level'),
                          controller: timeLevel,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '总时间层级',
                            helperText: '数字小的靠上',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('event-same-time-order'),
                          controller: sameTimeOrder,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '同时间排序',
                            helperText: '同层内数字小的靠上',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: const Text('更多信息'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      TextField(
                        controller: description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: '事件说明'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: chapterId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '关联章节'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('不关联章节'),
                          ),
                          ...book.chapters.map(
                            (chapter) => DropdownMenuItem(
                              value: chapter.id,
                              child: Text(
                                chapter.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => chapterId = value ?? '',
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '参与角色',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (book.roles.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '本书还没有角色，可先到“设定”中创建。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: book.roles
                            .map(
                              (role) => FilterChip(
                                key: ValueKey('event-role-${role.id}'),
                                avatar: CircleAvatar(
                                  child: Text(role.name.characters.first),
                                ),
                                selected: selectedRoles.contains(role.id),
                                label: Text(role.name),
                                onSelected: (value) => setDialogState(() {
                                  value
                                      ? selectedRoles.add(role.id)
                                      : selectedRoles.remove(role.id);
                                }),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '时间线',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: book.tracks
                          .map(
                            (track) => FilterChip(
                              selected: selected.contains(track.id),
                              label: Text(track.name),
                              onSelected: (value) => setDialogState(() {
                                value
                                    ? selected.add(track.id)
                                    : selected.remove(track.id);
                              }),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      validationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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
              onPressed: () {
                final level = int.tryParse(timeLevel.text.trim());
                final within = int.tryParse(sameTimeOrder.text.trim());
                if (title.text.trim().isEmpty ||
                    level == null ||
                    level < 1 ||
                    within == null ||
                    within < 1 ||
                    selected.isEmpty) {
                  setDialogState(
                    () => validationError = '请填写名称和正整数排序，并至少选择一条时间线',
                  );
                  return;
                }
                if (book.events.any(
                  (event) =>
                      event.id != existing?.id &&
                      event.timeLevel == level &&
                      event.sameTimeOrder == within,
                )) {
                  setDialogState(
                    () => validationError = '这个层级中的同时间排序已被占用，请换一个数字',
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final eventTitle = title.text.trim();
    final eventGroup = group.text.trim();
    final eventStoryDate = storyDate.text.trim();
    final eventDescription = description.text.trim();
    final eventLevel = int.tryParse(timeLevel.text.trim()) ?? 1;
    final eventSameOrder = int.tryParse(sameTimeOrder.text.trim()) ?? 1;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    group.dispose();
    storyDate.dispose();
    description.dispose();
    timeLevel.dispose();
    sameTimeOrder.dispose();
    if (created == true && eventTitle.isNotEmpty) {
      final roleNames = book.roles
          .where((role) => selectedRoles.contains(role.id))
          .map((role) => role.name)
          .join('、');
      if (existing == null) {
        widget.controller.createEvent(
          eventTitle,
          storyDate: eventStoryDate,
          description: eventDescription,
          chapterId: chapterId.isEmpty ? null : chapterId,
          roleIds: selectedRoles.toList(),
          group: eventGroup,
          trackIds: selected.toList(),
          timeLevel: eventLevel,
          sameTimeOrder: eventSameOrder,
        );
      } else {
        widget.controller.updateEvent(
          StoryEvent(
            id: existing.id,
            title: eventTitle,
            storyDate: eventStoryDate.isEmpty ? '时间未定' : eventStoryDate,
            order: eventLevel.toDouble(),
            timeLevel: eventLevel,
            sameTimeOrder: eventSameOrder,
            description: eventDescription,
            chapterId: chapterId.isEmpty ? null : chapterId,
            persons: roleNames,
            group: eventGroup.isEmpty ? '尚未分组' : eventGroup,
            flowLevel: existing.flowLevel,
            trackIds: selected.isEmpty
                ? [book.tracks.first.id]
                : selected.toList(),
            roleIds: selectedRoles.toList(),
          ),
        );
      }
    }
  }

  Future<void> _showLinkDialog(BuildContext context) async {
    final book = _book;
    if (book == null || book.events.length < 2) return;
    var from = book.events.first.id;
    var to = book.events[1].id;
    final label = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('建立事件连线'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: from,
                  decoration: const InputDecoration(labelText: '起点事件'),
                  items: book.events
                      .map(
                        (event) => DropdownMenuItem(
                          value: event.id,
                          child: Text(event.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => from = value ?? from),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: to,
                  decoration: const InputDecoration(labelText: '终点事件'),
                  items: book.events
                      .map(
                        (event) => DropdownMenuItem(
                          value: event.id,
                          child: Text(event.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => to = value ?? to),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: '关系名称'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: from == to ? null : () => Navigator.pop(context, true),
              child: const Text('建立'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      widget.controller.createStoryLink(from, to, label.text);
    }
    label.dispose();
  }

  Future<void> _showClueDialog(BuildContext context) async {
    final book = _book;
    if (book == null) return;
    final title = TextEditingController();
    final description = TextEditingController();
    String? origin = book.chapters.firstOrNull?.id;
    String? plan = book.chapters.length > 1 ? book.chapters[1].id : origin;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建伏笔'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '伏笔名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '说明'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: origin,
                    decoration: const InputDecoration(labelText: '埋下章节'),
                    items: book.chapters
                        .map(
                          (chapter) => DropdownMenuItem(
                            value: chapter.id,
                            child: Text(chapter.title),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => origin = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: plan,
                    decoration: const InputDecoration(labelText: '计划回收章节'),
                    items: book.chapters
                        .map(
                          (chapter) => DropdownMenuItem(
                            value: chapter.id,
                            child: Text(chapter.title),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => plan = value),
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
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      widget.controller.createClue(
        title.text,
        description.text,
        originChapterId: origin,
        plannedChapterId: plan,
      );
    }
    title.dispose();
    description.dispose();
  }

  Future<void> _showNoteDialog(BuildContext context) async {
    final body = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录灵感'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: body,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(hintText: '一句台词、一个场景、一闪而过的想法……'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('收下灵感'),
          ),
        ],
      ),
    );
    if (created == true) widget.controller.createNote(body.text);
    body.dispose();
  }
}

class _MobileStoryTabs extends StatelessWidget {
  const _MobileStoryTabs({required this.value, required this.onChanged});

  final _StoryView value;
  final ValueChanged<_StoryView> onChanged;

  @override
  Widget build(BuildContext context) => _ChoiceStrip(
    labels: const ['时间轴', '思维导图', '流程图'],
    icons: const [
      Icons.timeline_rounded,
      Icons.hub_outlined,
      Icons.schema_outlined,
    ],
    selectedIndex: value.index,
    onSelected: (index) => onChanged(_StoryView.values[index]),
  );
}

class _CompactToolButton extends StatelessWidget {
  const _CompactToolButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: _CompactToolSurface(label: label),
    );
  }
}

class _CompactToolSurface extends StatelessWidget {
  const _CompactToolSurface({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36, minWidth: 58),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _SquareToolButton extends StatelessWidget {
  const _SquareToolButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(38, 36),
        ),
        child: Text(label),
      ),
    );
  }
}

class _MobileTimelineCanvas extends StatelessWidget {
  const _MobileTimelineCanvas({
    required this.book,
    required this.tracks,
    required this.events,
    required this.controller,
    required this.onEventTap,
  });

  final Book book;
  final List<StoryTrack> tracks;
  final List<StoryEvent> events;
  final ScrollController controller;
  final ValueChanged<StoryEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const Center(child: Text('请先选择时间线'));
    if (events.isEmpty) return const Center(child: Text('当前时间线还没有事件'));
    const leftGutter = 54.0;
    const laneWidth = 146.0;
    const top = 56.0;
    const rowHeight = 108.0;
    final rows = <int, List<StoryEvent>>{};
    for (final event in events) {
      rows.putIfAbsent(event.timeLevel, () => []).add(event);
    }
    final rowEntries = rows.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final row in rowEntries) {
      row.value.sort(compareTimelineEvents);
    }
    final rowHeights = rowEntries.map((row) {
      var maxLaneEvents = 1;
      for (final track in tracks) {
        final count = row.value
            .where((event) => event.trackIds.contains(track.id))
            .length;
        if (count > maxLaneEvents) maxLaneEvents = count;
      }
      final requiredHeight = maxLaneEvents * 90.0 + 18;
      return requiredHeight > rowHeight ? requiredHeight : rowHeight;
    }).toList();
    final rowOffsets = <double>[];
    var nextRowTop = top;
    for (final height in rowHeights) {
      rowOffsets.add(nextRowTop);
      nextRowTop += height;
    }
    final contentWidth = leftGutter + laneWidth * tracks.length + 8;
    final contentHeight = nextRowTop + 22;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = contentWidth < constraints.maxWidth
            ? constraints.maxWidth
            : contentWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .45),
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              controller: controller,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: contentHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TimelineLanePainter(
                            tracks: tracks,
                            left: leftGutter,
                            laneWidth: laneWidth,
                            top: top,
                          ),
                        ),
                      ),
                      ...tracks.indexed.map((entry) {
                        final (index, track) = entry;
                        return Positioned(
                          left: leftGutter + index * laneWidth + 8,
                          top: 12,
                          width: laneWidth - 16,
                          child: Container(
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _trackColor(track.color)
                                  .withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        );
                      }),
                      ...rowEntries.indexed.expand((entry) {
                        final (rowIndex, row) = entry;
                        final topOffset = rowOffsets[rowIndex];
                        final widgets = <Widget>[
                          Positioned(
                            left: 5,
                            top: topOffset + 22,
                            width: leftGutter - 9,
                            child: Text(
                              '${row.key}',
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ];
                        for (
                          var trackIndex = 0;
                          trackIndex < tracks.length;
                          trackIndex++
                        ) {
                          final track = tracks[trackIndex];
                          final laneEvents = row.value
                              .where(
                                (event) => event.trackIds.contains(track.id),
                              )
                              .toList();
                          for (final laneEntry in laneEvents.indexed) {
                            final (laneEventIndex, event) = laneEntry;
                            widgets.add(
                              Positioned(
                                left: leftGutter + trackIndex * laneWidth + 7,
                                top: topOffset + 5 + laneEventIndex * 90,
                                width: laneWidth - 14,
                                height: 82,
                                child: _TimelineEventNode(
                                  event: event,
                                  color: _trackColor(track.color),
                                  onTap: () => onEventTap(event),
                                ),
                              ),
                            );
                          }
                        }
                        return widgets;
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelineEventNode extends StatelessWidget {
  const _TimelineEventNode({
    required this.event,
    required this.color,
    required this.onTap,
  });

  final StoryEvent event;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (event.storyDate != '时间未定')
                      Text(
                        event.storyDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Text(
                      event.group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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

class _TimelineLanePainter extends CustomPainter {
  _TimelineLanePainter({
    required this.tracks,
    required this.left,
    required this.laneWidth,
    required this.top,
  });

  final List<StoryTrack> tracks;
  final double left;
  final double laneWidth;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < tracks.length; index++) {
      final x = left + index * laneWidth + laneWidth / 2;
      final paint = Paint()
        ..color = _trackColor(tracks[index].color).withValues(alpha: .75)
        ..strokeWidth = 1.6;
      canvas.drawLine(Offset(x, top - 3), Offset(x, size.height - 18), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineLanePainter oldDelegate) => true;
}

class _MobileMindCanvas extends StatelessWidget {
  const _MobileMindCanvas({
    required this.book,
    required this.events,
    required this.controller,
    required this.collapsedGroups,
    required this.onToggleGroup,
    required this.onEventTap,
    required this.onAddChild,
  });

  final Book book;
  final List<StoryEvent> events;
  final TransformationController controller;
  final Set<String> collapsedGroups;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<StoryEvent> onEventTap;
  final ValueChanged<String> onAddChild;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<StoryEvent>>{};
    for (final event in events) {
      final group = event.group.trim().isEmpty ? '未分组' : event.group.trim();
      groups.putIfAbsent(group, () => []).add(event);
    }
    if (groups.isEmpty) {
      return const Center(child: Text('还没有可显示的故事事件'));
    }
    final scheme = Theme.of(context).colorScheme;
    const canvasWidth = 620.0;
    const rootWidth = 126.0;
    const branchX = 190.0;
    const groupWidth = 370.0;
    const childX = 220.0;
    const childWidth = 340.0;
    var nextY = 26.0;
    final placements = <_MindPlacement>[];
    final branchColors = [scheme.primary, scheme.tertiary, scheme.secondary];
    var groupIndex = 0;
    for (final entry in groups.entries) {
      final groupColor = branchColors[groupIndex % branchColors.length];
      final groupId = 'group-$groupIndex';
      final collapsed = collapsedGroups.contains(entry.key);
      placements.add(
        _MindPlacement(
          id: groupId,
          parentId: 'root',
          rect: Rect.fromLTWH(branchX, nextY, groupWidth, 62),
          title: entry.key,
          subtitle: '${entry.value.length} 个节点',
          color: groupColor,
          isGroup: true,
          collapsed: collapsed,
        ),
      );
      nextY += 78;
      if (!collapsed) {
        for (final event in entry.value) {
          placements.add(
            _MindPlacement(
              id: event.id,
              parentId: groupId,
              rect: Rect.fromLTWH(childX, nextY, childWidth, 68),
              title: event.title,
              subtitle: event.storyDate.isEmpty ? '时间未定' : event.storyDate,
              color: groupColor,
              event: event,
            ),
          );
          nextY += 80;
        }
        placements.add(
          _MindPlacement(
            id: 'add-$groupIndex',
            parentId: groupId,
            rect: Rect.fromLTWH(childX, nextY, childWidth, 46),
            title: '+ 新增子节点',
            subtitle: entry.key,
            color: groupColor,
            isAdd: true,
          ),
        );
        nextY += 62;
      }
      nextY += 18;
      groupIndex++;
    }
    final canvasHeight = nextY < 300 ? 300.0 : nextY;
    placements.insert(
      0,
      _MindPlacement(
        id: 'root',
        rect: Rect.fromLTWH(28, (canvasHeight - 82) / 2, rootWidth, 82),
        title: book.title,
        subtitle: '全书构思',
        color: scheme.primary,
        isRoot: true,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .45),
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InteractiveViewer(
          constrained: false,
          transformationController: controller,
          minScale: .5,
          maxScale: 2.2,
          boundaryMargin: const EdgeInsets.all(80),
          child: SizedBox(
            width: canvasWidth,
            height: canvasHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MindConnectionPainter(placements),
                  ),
                ),
                ...placements.map(
                  (placement) => Positioned.fromRect(
                    rect: placement.rect,
                    child: _MindNode(
                      placement: placement,
                      onTap: () {
                        if (placement.event != null) {
                          onEventTap(placement.event!);
                        } else if (placement.isGroup) {
                          onToggleGroup(placement.title);
                        } else if (placement.isAdd) {
                          onAddChild(placement.subtitle);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MindPlacement {
  const _MindPlacement({
    required this.id,
    required this.rect,
    required this.title,
    required this.subtitle,
    required this.color,
    this.parentId,
    this.event,
    this.isAdd = false,
    this.isGroup = false,
    this.isRoot = false,
    this.collapsed = false,
  });

  final String id;
  final String? parentId;
  final Rect rect;
  final String title;
  final String subtitle;
  final Color color;
  final StoryEvent? event;
  final bool isAdd;
  final bool isGroup;
  final bool isRoot;
  final bool collapsed;
}

class _MindNode extends StatelessWidget {
  const _MindNode({required this.placement, required this.onTap});

  final _MindPlacement placement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: placement.isRoot
          ? placement.color.withValues(alpha: .14)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(width: 5, color: placement.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      placement.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: placement.isAdd ? placement.color : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!placement.isAdd) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              placement.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (placement.isGroup)
                            Icon(
                              placement.collapsed
                                  ? Icons.chevron_right_rounded
                                  : Icons.expand_more_rounded,
                              size: 20,
                              color: placement.color,
                            ),
                        ],
                      ),
                    ],
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

class _MindConnectionPainter extends CustomPainter {
  _MindConnectionPainter(this.placements);

  final List<_MindPlacement> placements;

  @override
  void paint(Canvas canvas, Size size) {
    final root = placements.where((item) => item.isRoot).firstOrNull;
    if (root == null) return;
    final groups = placements.where((item) => item.isGroup).toList();
    const rootTrunkX = 172.0;
    for (final group in groups) {
      final path = Path()
        ..moveTo(root.rect.right, root.rect.center.dy)
        ..lineTo(rootTrunkX, root.rect.center.dy)
        ..lineTo(rootTrunkX, group.rect.center.dy)
        ..lineTo(group.rect.left, group.rect.center.dy);
      canvas.drawPath(path, _mindLinePaint(group.color));

      final children = placements
          .where((item) => item.parentId == group.id)
          .toList();
      if (children.isEmpty) continue;
      final childTrunkX = group.rect.left + 16;
      final trunkBottom = children.last.rect.center.dy;
      final branchPath = Path()
        ..moveTo(childTrunkX, group.rect.bottom)
        ..lineTo(childTrunkX, trunkBottom);
      canvas.drawPath(branchPath, _mindLinePaint(group.color));
      for (final child in children) {
        canvas.drawLine(
          Offset(childTrunkX, child.rect.center.dy),
          Offset(child.rect.left, child.rect.center.dy),
          _mindLinePaint(group.color),
        );
      }
    }
  }

  Paint _mindLinePaint(Color color) => Paint()
    ..color = color.withValues(alpha: .72)
    ..strokeWidth = 1.8
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  bool shouldRepaint(covariant _MindConnectionPainter oldDelegate) => true;
}

class _MobileFlowCanvas extends StatelessWidget {
  const _MobileFlowCanvas({
    required this.book,
    required this.events,
    required this.controller,
    required this.onEventTap,
  });

  final Book book;
  final List<StoryEvent> events;
  final TransformationController controller;
  final ValueChanged<StoryEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const Center(child: Text('还没有可显示的事件'));
    const nodeWidth = 212.0;
    const nodeHeight = 78.0;
    const columnGap = 42.0;
    const rowGap = 156.0;
    const horizontalPadding = 42.0;
    const topPadding = 34.0;

    final ids = events.map((event) => event.id).toSet();
    final links = book.storyLinks
        .where(
          (link) =>
              ids.contains(link.fromEventId) &&
              ids.contains(link.toEventId) &&
              link.fromEventId != link.toEventId,
        )
        .toList();
    final levelsById = {
      for (final event in events)
        event.id: event.flowLevel < 0 ? 0 : event.flowLevel,
    };
    final incoming = {for (final event in events) event.id: 0};
    final outgoing = <String, List<StoryLink>>{};
    for (final link in links) {
      incoming[link.toEventId] = (incoming[link.toEventId] ?? 0) + 1;
      outgoing.putIfAbsent(link.fromEventId, () => []).add(link);
    }
    final queue = events
        .where((event) => incoming[event.id] == 0)
        .map((event) => event.id)
        .toList();
    final remainingIncoming = Map<String, int>.from(incoming);
    for (var index = 0; index < queue.length; index++) {
      final fromId = queue[index];
      for (final link in outgoing[fromId] ?? const <StoryLink>[]) {
        final nextLevel = (levelsById[fromId] ?? 0) + 1;
        if (nextLevel > (levelsById[link.toEventId] ?? 0)) {
          levelsById[link.toEventId] = nextLevel;
        }
        final nextIncoming = (remainingIncoming[link.toEventId] ?? 1) - 1;
        remainingIncoming[link.toEventId] = nextIncoming;
        if (nextIncoming == 0) queue.add(link.toEventId);
      }
    }

    final levels = <int, List<StoryEvent>>{};
    for (final event in events) {
      levels.putIfAbsent(levelsById[event.id] ?? 0, () => []).add(event);
    }
    final ordered = levels.keys.toList()..sort();
    for (final items in levels.values) {
      items.sort((a, b) => a.order.compareTo(b.order));
    }
    final maxColumns = levels.values.fold<int>(
      1,
      (value, items) => items.length > value ? items.length : value,
    );
    final contentWidth =
        horizontalPadding * 2 +
        maxColumns * nodeWidth +
        (maxColumns - 1) * columnGap;
    final canvasWidth = contentWidth < 620 ? 620.0 : contentWidth;
    final placements = <String, Rect>{};
    for (var row = 0; row < ordered.length; row++) {
      final items = levels[ordered[row]]!;
      if (row > 0) {
        items.sort((a, b) {
          double parentCenter(StoryEvent event) {
            final parents = links
                .where((link) => link.toEventId == event.id)
                .map((link) => placements[link.fromEventId]?.center.dx)
                .whereType<double>()
                .toList();
            if (parents.isEmpty) return event.order * 100;
            return parents.reduce((x, y) => x + y) / parents.length;
          }

          final byParent = parentCenter(a).compareTo(parentCenter(b));
          return byParent == 0 ? a.order.compareTo(b.order) : byParent;
        });
      }
      final rowWidth =
          items.length * nodeWidth + (items.length - 1) * columnGap;
      final rowStart = (canvasWidth - rowWidth) / 2;
      for (var index = 0; index < items.length; index++) {
        placements[items[index].id] = Rect.fromLTWH(
          rowStart + index * (nodeWidth + columnGap),
          topPadding + row * rowGap,
          nodeWidth,
          nodeHeight,
        );
      }
    }
    final height = topPadding * 2 + nodeHeight + (ordered.length - 1) * rowGap;
    final scheme = Theme.of(context).colorScheme;
    final branchColors = [scheme.primary, scheme.tertiary, scheme.secondary];
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .45),
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InteractiveViewer(
          constrained: false,
          transformationController: controller,
          minScale: .5,
          maxScale: 2.2,
          boundaryMargin: const EdgeInsets.all(80),
          child: SizedBox(
            width: canvasWidth,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FlowConnectionPainter(
                      placements: placements,
                      links: links,
                      color: scheme.primary,
                      labelColor: scheme.onSurfaceVariant,
                      labelBackground: scheme.surface,
                    ),
                  ),
                ),
                ...events.indexed
                    .where((entry) => placements.containsKey(entry.$2.id))
                    .map(
                      (entry) => Positioned.fromRect(
                        rect: placements[entry.$2.id]!,
                        child: _TimelineEventNode(
                          event: entry.$2,
                          color: branchColors[entry.$1 % branchColors.length],
                          onTap: () => onEventTap(entry.$2),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowConnectionPainter extends CustomPainter {
  _FlowConnectionPainter({
    required this.placements,
    required this.links,
    required this.color,
    required this.labelColor,
    required this.labelBackground,
  });

  final Map<String, Rect> placements;
  final List<StoryLink> links;
  final Color color;
  final Color labelColor;
  final Color labelBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .74)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linksBySource = <String, List<StoryLink>>{};
    for (final link in links) {
      linksBySource.putIfAbsent(link.fromEventId, () => []).add(link);
    }
    for (final entry in linksBySource.entries) {
      final from = placements[entry.key];
      if (from == null) continue;
      final targetLinks =
          entry.value
              .where((link) => placements.containsKey(link.toEventId))
              .toList()
            ..sort(
              (a, b) => placements[a.toEventId]!.center.dx.compareTo(
                placements[b.toEventId]!.center.dx,
              ),
            );
      if (targetLinks.isEmpty) continue;
      final start = Offset(from.center.dx, from.bottom);
      final targets = targetLinks
          .map((link) => placements[link.toEventId]!)
          .toList();
      final nearestTop = targets
          .map((rect) => rect.top)
          .reduce((a, b) => a < b ? a : b);
      final busY = start.dy + (nearestTop - start.dy) * .46;
      final left = targets.first.center.dx < start.dx
          ? targets.first.center.dx
          : start.dx;
      final right = targets.last.center.dx > start.dx
          ? targets.last.center.dx
          : start.dx;

      canvas.drawLine(start, Offset(start.dx, busY), paint);
      canvas.drawLine(Offset(left, busY), Offset(right, busY), paint);
      if (targetLinks.length > 1) {
        canvas.drawCircle(
          Offset(start.dx, busY),
          4,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
      }

      for (var index = 0; index < targetLinks.length; index++) {
        final link = targetLinks[index];
        final target = targets[index];
        final end = Offset(target.center.dx, target.top);
        canvas.drawLine(Offset(end.dx, busY), end, paint);
        _drawArrow(canvas, end);
        if (link.label.trim().isNotEmpty) {
          _drawLabel(
            canvas,
            link.label.trim(),
            Offset(
              targetLinks.length == 1 ? (start.dx + end.dx) / 2 : end.dx,
              busY + (end.dy - busY) * .48,
            ),
          );
        }
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset end) {
    final arrow = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - 5.5, end.dy - 8)
      ..lineTo(end.dx + 5.5, end.dy - 8)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void _drawLabel(Canvas canvas, String label, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: labelColor, fontSize: 10.5, height: 1),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 96);
    final rect = Rect.fromCenter(
      center: center,
      width: painter.width + 12,
      height: painter.height + 7,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()..color = labelBackground.withValues(alpha: .94),
    );
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _FlowConnectionPainter oldDelegate) => true;
}

class _AxisView extends StatelessWidget {
  const _AxisView({required this.book, required this.events});

  final Book book;
  final List<StoryEvent> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: events.indexed.map((entry) {
        final (index, event) = entry;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (index < events.length - 1)
                      Expanded(
                        child: Container(
                          width: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _EventCard(book: book, event: event),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MindView extends StatelessWidget {
  const _MindView({required this.book, required this.events});

  final Book book;
  final List<StoryEvent> events;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<StoryEvent>>{};
    for (final event in events) {
      groups.putIfAbsent(event.group, () => []).add(event);
    }
    return _ResponsiveGrid(
      children: groups.entries
          .map(
            (entry) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.hub_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...entry.value.map(
                      (event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(event.title),
                        subtitle: Text(event.storyDate),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FlowView extends StatelessWidget {
  const _FlowView({required this.book, required this.events});

  final Book book;
  final List<StoryEvent> events;

  @override
  Widget build(BuildContext context) {
    final ids = events.map((event) => event.id).toSet();
    final links = book.storyLinks
        .where(
          (link) =>
              ids.contains(link.fromEventId) && ids.contains(link.toEventId),
        )
        .toList();
    final levels = <int, List<StoryEvent>>{};
    for (final event in events) {
      levels.putIfAbsent(event.flowLevel, () => []).add(event);
    }
    final orderedLevels = levels.keys.toList()..sort();
    String titleOf(String id) =>
        book.events
            .where((event) => event.id == id)
            .map((event) => event.title)
            .firstOrNull ??
        '未知事件';
    return Column(
      children: [
        ...orderedLevels.indexed.map((entry) {
          final (index, level) = entry;
          return Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: levels[level]!
                    .map(
                      (event) => SizedBox(
                        width: 230,
                        child: Card(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: .55),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(
                                  event.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  event.group,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              if (index < orderedLevels.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          );
        }),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '作者定义的关系',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          ...links.map(
            (link) => ListTile(
              leading: const Icon(Icons.link_rounded),
              title: Text(
                '${titleOf(link.fromEventId)} → ${titleOf(link.toEventId)}',
              ),
              subtitle: Text(link.label),
            ),
          ),
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.book, required this.event});

  final Book book;
  final StoryEvent event;

  @override
  Widget build(BuildContext context) {
    final chapter = book.chapters
        .where((item) => item.id == event.chapterId)
        .firstOrNull;
    final tracks = book.tracks
        .where((track) => event.trackIds.contains(track.id))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.storyDate,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(event.title, style: Theme.of(context).textTheme.titleLarge),
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(event.description),
            ],
            if (event.persons.isNotEmpty || chapter != null) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (event.persons.isNotEmpty) '参与 · ${event.persons}',
                  if (chapter != null) '章节 · ${chapter.title}',
                ].join('   '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (tracks.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tracks
                    .map((track) => Chip(label: Text(track.name)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FixedPageHeader extends StatelessWidget {
  const _FixedPageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      width: double.infinity,
      height: compact ? 94 : 104,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 28,
        compact ? 12 : 16,
        compact ? 12 : 28,
        compact ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _SettingsTypeTabs extends StatelessWidget {
  const _SettingsTypeTabs({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => _ChoiceStrip(
    labels: const ['角色卡', '世界观'],
    selectedIndex: value,
    onSelected: onChanged,
  );
}

class _ChoiceStrip extends StatelessWidget {
  const _ChoiceStrip({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.icons,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected ? scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: selected
                        ? Border.all(color: Theme.of(context).dividerColor)
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icons != null) ...[
                        Icon(icons![index], size: 17),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          labels[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TemplateBanner extends StatelessWidget {
  const _TemplateBanner({
    required this.count,
    required this.summary,
    required this.onManage,
  });

  final int count;
  final String summary;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: .52),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onManage,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count 项共用基础字段',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(summary, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              TextButton(onPressed: onManage, child: const Text('管理模板')),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageScroller extends StatelessWidget {
  const _PageScroller({
    required this.child,
    this.maxWidth = 1040,
    this.topPadding,
  });

  final Widget child;
  final double maxWidth;
  final double? topPadding;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 28,
        topPadding ?? (compact ? 16 : 28),
        compact ? 16 : 28,
        compact ? 92 + bottomInset : 36,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (count - 1) * 14) / count;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(),
        );
      },
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Row(
          children: [
            Icon(
              Icons.inbox_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

Color _trackColor(String name) => switch (name) {
  'blue' => const Color(0xFF5B7FA3),
  'sage' => const Color(0xFF718D78),
  'amber' => const Color(0xFFB48245),
  _ => const Color(0xFF756186),
};
