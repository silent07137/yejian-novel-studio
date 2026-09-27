import 'package:flutter/material.dart';

import '../ai/ai_service.dart';
import '../domain/entity_id.dart';

Future<void> showAiSettingsDialog(
  BuildContext context,
  AiSettingsStore store, {
  AiProviderProfile? profile,
}) => showDialog<void>(
  context: context,
  builder: (context) => _AiSettingsDialog(store: store, profile: profile),
);

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog({required this.store, this.profile});

  final AiSettingsStore store;
  final AiProviderProfile? profile;

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  bool _saving = false;
  bool _showKey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name.text = profile?.name ?? '';
    _baseUrl.text = profile?.baseUrl ?? const AiConfiguration().baseUrl;
    _model.text = profile?.model ?? '';
    _apiKey.text = profile?.apiKey ?? '';
  }

  Future<void> _save() async {
    try {
      final baseUrl = _baseUrl.text.trim();
      final model = _model.text.trim();
      final apiKey = _apiKey.text.trim();
      AiTextService.endpointFor(baseUrl);
      if (model.isEmpty || apiKey.isEmpty) {
        throw const AiRequestException('请填写服务地址、模型与 API Key');
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      final catalog = await widget.store.loadProviders();
      final existing = widget.profile;
      if (existing != null &&
          !catalog.profiles.any((item) => item.id == existing.id)) {
        throw const AiRequestException('该 API 配置已不存在，请重新打开');
      }
      final profile = AiProviderProfile(
        id: existing?.id ?? newEntityId('ai'),
        name: _name.text.trim().isEmpty ? model : _name.text.trim(),
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
      );
      await widget.store.saveProviders(
        AiProviderCatalog(
          profiles: [
            for (final item in catalog.profiles)
              if (item.id == profile.id) profile else item,
            if (existing == null) profile,
          ],
          activeId: existing == null
              ? profile.id
              : catalog.activeId ?? profile.id,
        ),
      );
      if (mounted) Navigator.pop(context);
    } on AiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = '配置保存失败，请检查设备安全存储');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.profile == null ? '添加 API' : '编辑 API'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('ai-provider-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: '名称（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('ai-base-url'),
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'API 地址',
                hintText: 'https://api.example.com/v1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('ai-model'),
              controller: _model,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '模型 ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('ai-api-key'),
              controller: _apiKey,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                suffixIcon: IconButton(
                  tooltip: _showKey ? '隐藏 Key' : '显示 Key',
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(
                    _showKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '仅支持 HTTPS Chat Completions 接口。Key 保存在本机安全存储中，不进入工程文件。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('save-ai-settings'),
        onPressed: _saving ? null : _save,
        child: const Text('保存'),
      ),
    ],
  );
}

Future<void> showAiPromptSettingsDialog(
  BuildContext context,
  AiSettingsStore store,
) => showDialog<void>(
  context: context,
  builder: (context) => _AiPromptSettingsDialog(store: store),
);

class _AiPromptSettingsDialog extends StatefulWidget {
  const _AiPromptSettingsDialog({required this.store});

  final AiSettingsStore store;

  @override
  State<_AiPromptSettingsDialog> createState() =>
      _AiPromptSettingsDialogState();
}

class _AiPromptSettingsDialogState extends State<_AiPromptSettingsDialog> {
  final _polish = TextEditingController();
  final _continueWriting = TextEditingController();
  final _rewrite = TextEditingController();
  final _custom = TextEditingController();
  AiConfiguration _loadedConfiguration = const AiConfiguration();
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.store.load();
      if (!mounted) return;
      _loadedConfiguration = value;
      _polish.text = value.promptFor(AiTextAction.polish);
      _continueWriting.text = value.promptFor(AiTextAction.continueWriting);
      _rewrite.text = value.promptFor(AiTextAction.rewrite);
      _custom.text = value.promptFor(AiTextAction.custom);
    } on Object {
      if (mounted) {
        _loadFailed = true;
        _error = '无法读取提示词，请检查设备安全存储';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _overrideOrDefault(String text, AiTextAction action) {
    final prompt = text.trim();
    return prompt.isEmpty || prompt == defaultAiPrompt(action) ? '' : prompt;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(
        _loadedConfiguration.copyWith(
          polishPrompt: _overrideOrDefault(_polish.text, AiTextAction.polish),
          continueWritingPrompt: _overrideOrDefault(
            _continueWriting.text,
            AiTextAction.continueWriting,
          ),
          rewritePrompt: _overrideOrDefault(
            _rewrite.text,
            AiTextAction.rewrite,
          ),
          customPrompt: _overrideOrDefault(_custom.text, AiTextAction.custom),
        ),
      );
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) setState(() => _error = '提示词保存失败，请检查设备安全存储');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _polish.dispose();
    _continueWriting.dispose();
    _rewrite.dispose();
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('AI 提示词'),
    content: SizedBox(
      width: 440,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _promptField(
                    label: '润色',
                    controller: _polish,
                    action: AiTextAction.polish,
                    fieldKey: 'ai-polish-prompt',
                    resetKey: 'reset-ai-polish-prompt',
                  ),
                  const SizedBox(height: 16),
                  _promptField(
                    label: '续写',
                    controller: _continueWriting,
                    action: AiTextAction.continueWriting,
                    fieldKey: 'ai-continue-prompt',
                    resetKey: 'reset-ai-continue-prompt',
                  ),
                  const SizedBox(height: 16),
                  _promptField(
                    label: '改写',
                    controller: _rewrite,
                    action: AiTextAction.rewrite,
                    fieldKey: 'ai-rewrite-prompt',
                    resetKey: 'reset-ai-rewrite-prompt',
                  ),
                  const SizedBox(height: 16),
                  _promptField(
                    label: '自定义指令',
                    controller: _custom,
                    action: AiTextAction.custom,
                    fieldKey: 'ai-custom-prompt',
                    resetKey: 'reset-ai-custom-prompt',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
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
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('save-ai-prompts'),
        onPressed: _loading || _saving || _loadFailed ? null : _save,
        child: const Text('保存'),
      ),
    ],
  );

  Widget _promptField({
    required String label,
    required TextEditingController controller,
    required AiTextAction action,
    required String fieldKey,
    required String resetKey,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text('$label提示词')),
          TextButton(
            key: ValueKey(resetKey),
            onPressed: _saving
                ? null
                : () => controller.text = defaultAiPrompt(action),
            child: const Text('恢复默认'),
          ),
        ],
      ),
      TextField(
        key: ValueKey(fieldKey),
        controller: controller,
        minLines: 3,
        maxLines: 5,
        maxLength: 4000,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: '留空使用内置提示词',
        ),
      ),
    ],
  );
}
