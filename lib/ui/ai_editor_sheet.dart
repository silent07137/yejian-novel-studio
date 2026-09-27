import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai_context.dart';
import '../ai/ai_history.dart';
import '../ai/ai_service.dart';
import '../ai/ai_target.dart';
import '../models/library_data.dart';
import '../state/app_controller.dart';
import 'ai_settings_dialog.dart';

class AiEditorDecision {
  const AiEditorDecision(this.action, this.target, this.generated);

  final AiTextAction action;
  final AiTextTarget target;
  final String generated;
}

class AiEditorSheet extends StatefulWidget {
  const AiEditorSheet({
    super.key,
    required this.controller,
    required this.book,
    required this.chapter,
    required this.sourceBody,
    required this.selectionStart,
    required this.selectionEnd,
  });

  final AppController controller;
  final Book book;
  final Chapter chapter;
  final String sourceBody;
  final int selectionStart;
  final int selectionEnd;

  @override
  State<AiEditorSheet> createState() => _AiEditorSheetState();
}

class _AiEditorSheetState extends State<AiEditorSheet> {
  AiTextAction _action = AiTextAction.polish;
  late AiTextScope _scope;
  bool _includeContext = true;
  bool _busy = false;
  AiProviderCatalog? _providers;
  AiPromptCatalog? _templates;
  AiOperationPromptCatalog? _operationPrompts;
  String? _providerId;
  String? _templateId;
  String? _operationPromptId;
  String? _generated;
  String? _error;
  final _instruction = TextEditingController();

  bool get _hasSelection => widget.selectionEnd > widget.selectionStart;

  @override
  void initState() {
    super.initState();
    _scope = _hasSelection ? AiTextScope.selection : AiTextScope.paragraph;
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    try {
      final providers = await widget.controller.aiSettingsStore.loadProviders();
      final templates = await widget.controller.aiSettingsStore
          .loadPromptCatalog();
      final operations = await widget.controller.aiSettingsStore
          .loadOperationPromptCatalog();
      if (mounted) {
        setState(() {
          _providers = providers;
          _templates = templates;
          _operationPrompts = operations;
          _providerId = providers.profiles.any((item) => item.id == _providerId)
              ? _providerId
              : providers.activeId;
          _templateId = templates.templateById(_templateId) != null
              ? _templateId
              : templates.defaultTemplateId;
          _operationPromptId =
              operations
                  .forAction(_action)
                  .any((item) => item.id == _operationPromptId)
              ? _operationPromptId
              : operations.defaultFor(_action).id;
        });
      }
    } on Object {
      if (mounted) setState(() => _error = '读取 AI 配置失败');
    }
  }

  AiConfiguration? get _selectedConfiguration {
    final profile = _providers?.profiles
        .where((item) => item.id == _providerId)
        .firstOrNull;
    final template = _templates?.templateById(_templateId);
    final prompt = _operationPrompts
        ?.forAction(_action)
        .where((item) => item.id == _operationPromptId)
        .firstOrNull;
    if (profile == null || template == null || prompt == null) return null;
    final style = template.styleInstruction.trim();
    final instruction = style.isEmpty
        ? prompt.content
        : '${prompt.content}\n文风要求：$style';
    return AiConfiguration(
      baseUrl: profile.baseUrl,
      model: profile.model,
      apiKey: profile.apiKey,
      polishPrompt: _action == AiTextAction.polish ? instruction : '',
      continueWritingPrompt: _action == AiTextAction.continueWriting
          ? instruction
          : '',
      rewritePrompt: _action == AiTextAction.rewrite ? instruction : '',
      customPrompt: _action == AiTextAction.custom ? instruction : '',
    );
  }

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  AiTextTarget? _target() {
    try {
      return AiTextTarget.resolve(
        body: widget.sourceBody,
        selectionStart: widget.selectionStart,
        selectionEnd: widget.selectionEnd,
        scope: _scope,
      );
    } on AiRequestException {
      return null;
    }
  }

  String? _targetError() {
    try {
      AiTextTarget.resolve(
        body: widget.sourceBody,
        selectionStart: widget.selectionStart,
        selectionEnd: widget.selectionEnd,
        scope: _scope,
      );
      return null;
    } on AiRequestException catch (error) {
      return error.message;
    }
  }

  Future<void> _send(AiTextTarget target, String contextText) async {
    final configuration = _selectedConfiguration;
    final profile = _providers?.profiles
        .where((item) => item.id == _providerId)
        .firstOrNull;
    final template = _templates?.templateById(_templateId);
    if (configuration == null || !configuration.isComplete) {
      setState(() => _error = '请先配置 AI 服务地址、模型和 API Key');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final generated = await widget.controller.aiTextService.generate(
        configuration: configuration,
        action: _action,
        selectedText: target.text,
        contextText: _includeContext ? contextText : '',
        customInstruction: _instruction.text.trim(),
      );
      if (mounted) setState(() => _generated = generated);
      try {
        final now = DateTime.now();
        await widget.controller.aiHistoryStore.append(
          AiGenerationRecord(
            id: now.microsecondsSinceEpoch.toString(),
            createdAt: now,
            bookTitle: widget.book.title,
            chapterTitle: widget.chapter.title,
            action: _action,
            providerName: profile?.name ?? '',
            model: configuration.model,
            templateName: template?.name ?? '',
            result: generated,
          ),
        );
      } on Object {
        if (mounted) setState(() => _error = '结果已生成，但保存历史失败');
      }
    } on AiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = 'AI 操作失败，请检查服务配置');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final target = _target();
    final targetError = target == null ? _targetError() : null;
    final contextText = target == null
        ? ''
        : const AiContextBuilder().build(
            book: widget.book,
            chapter: widget.chapter,
            currentBody: widget.sourceBody,
            selectionStart: target.start,
            selectionEnd: target.end,
          );
    final configuration = _selectedConfiguration;
    final endpoint = configuration == null
        ? null
        : Uri.tryParse(configuration.baseUrl)?.host;
    final generated = _generated;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: (media.size.height - media.viewInsets.bottom) * .76,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'AI 助手',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('ai-editor-content'),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    if (generated == null) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '模型配置',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: const ValueKey('ai-model-select'),
                                value: _providerId,
                                isExpanded: true,
                                hint: const Text('先添加 API'),
                                items: [
                                  for (final profile
                                      in _providers?.profiles ??
                                          <AiProviderProfile>[])
                                    DropdownMenuItem(
                                      value: profile.id,
                                      child: Text(
                                        '${profile.name} · ${profile.model}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (id) => setState(() => _providerId = id),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '文风模板',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: const ValueKey('ai-template-select'),
                                value: _templateId,
                                isExpanded: true,
                                items: [
                                  for (final template
                                      in _templates?.templates ??
                                          <AiPromptTemplate>[])
                                    DropdownMenuItem(
                                      value: template.id,
                                      child: Text(
                                        template.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (id) => setState(() => _templateId = id),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '操作提示词',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: const ValueKey('ai-operation-select'),
                                value: _operationPromptId,
                                isExpanded: true,
                                items: [
                                  for (final prompt
                                      in _operationPrompts?.forAction(
                                            _action,
                                          ) ??
                                          <AiOperationPrompt>[])
                                    DropdownMenuItem(
                                      value: prompt.id,
                                      child: Text(
                                        prompt.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (id) => setState(
                                        () => _operationPromptId = id,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (action, label) in [
                            (AiTextAction.polish, '润色'),
                            (AiTextAction.continueWriting, '续写'),
                            (AiTextAction.rewrite, '改写'),
                            (AiTextAction.custom, '自定义'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _action == action,
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(() {
                                      _action = action;
                                      _operationPromptId = _operationPrompts
                                          ?.defaultFor(action)
                                          .id;
                                      _scope = _hasSelection
                                          ? AiTextScope.selection
                                          : action ==
                                                AiTextAction.continueWriting
                                          ? AiTextScope.cursor
                                          : AiTextScope.paragraph;
                                      _error = null;
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '处理范围',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (scope, label) in [
                            if (_hasSelection) (AiTextScope.selection, '选中内容'),
                            (AiTextScope.paragraph, '当前段落'),
                            if (_action == AiTextAction.continueWriting)
                              (AiTextScope.cursor, '光标前文'),
                            (AiTextScope.chapter, '整章'),
                          ])
                            ChoiceChip(
                              key: ValueKey('ai-scope-${scope.name}'),
                              label: Text(label),
                              selected: _scope == scope,
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(() {
                                      _scope = scope;
                                      _error = null;
                                    }),
                            ),
                        ],
                      ),
                      if (_action == AiTextAction.custom) ...[
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('ai-custom-instruction'),
                          controller: _instruction,
                          onChanged: (_) => setState(() {}),
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: '本次 AI 指令',
                            hintText: '例如：改成第一人称，保留剧情事实',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (targetError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          targetError,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (target != null) ...[
                        const SizedBox(height: 12),
                        Text('将发送的正文 · ${target.text.length} 字符'),
                        const SizedBox(height: 6),
                        _PreviewBox(target.text),
                      ],
                      if (configuration != null) ...[
                        const SizedBox(height: 12),
                        const Text('本次提示词'),
                        const SizedBox(height: 6),
                        _PreviewBox(configuration.promptFor(_action)),
                      ],
                      SwitchListTile(
                        key: const ValueKey('ai-include-context'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('附带本书相关资料'),
                        subtitle: const Text('当前章节片段及匹配的角色、设定、事件'),
                        value: _includeContext,
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _includeContext = value),
                      ),
                      if (_includeContext && target != null) ...[
                        const Text('将附带的资料'),
                        const SizedBox(height: 6),
                        _PreviewBox(contextText),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '发送至 ${endpoint?.isNotEmpty == true ? endpoint : '待配置的 AI 服务'}。服务商可能收取费用。',
                      ),
                      if (configuration == null || !configuration.isComplete)
                        TextButton.icon(
                          onPressed: () async {
                            await showAiSettingsDialog(
                              context,
                              widget.controller.aiSettingsStore,
                            );
                            if (mounted) await _loadConfiguration();
                          },
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('配置 AI 服务'),
                        ),
                    ] else ...[
                      Text('原文', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      _PreviewBox(target?.text ?? ''),
                      const SizedBox(height: 16),
                      Text(
                        'AI 结果',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      _PreviewBox(generated),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: generated == null
                      ? [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const ValueKey('ai-send'),
                            onPressed:
                                _busy ||
                                    target == null ||
                                    configuration?.isComplete != true ||
                                    (_action == AiTextAction.custom &&
                                        _instruction.text.trim().isEmpty)
                                ? null
                                : () => _send(target, contextText),
                            child: Text(_busy ? '生成中…' : '确认发送'),
                          ),
                        ]
                      : [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('放弃'),
                          ),
                          TextButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: generated),
                              );
                              if (context.mounted) Navigator.pop(context);
                            },
                            child: const Text('复制结果'),
                          ),
                          FilledButton(
                            key: const ValueKey('apply-ai-result'),
                            onPressed: target == null
                                ? null
                                : () => Navigator.pop(
                                    context,
                                    AiEditorDecision(
                                      _action,
                                      target,
                                      generated,
                                    ),
                                  ),
                            child: Text(
                              _action == AiTextAction.continueWriting
                                  ? '插入续写'
                                  : '替换正文',
                            ),
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxHeight: 160),
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: SingleChildScrollView(child: SelectableText(text)),
  );
}
