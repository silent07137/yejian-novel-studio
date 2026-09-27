import 'package:flutter/material.dart';

import '../ai/ai_service.dart';

Future<void> showAiSettingsDialog(
  BuildContext context,
  AiSettingsStore store,
) => showDialog<void>(
  context: context,
  builder: (context) => _AiSettingsDialog(store: store),
);

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog({required this.store});

  final AiSettingsStore store;

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  AiConfiguration _loadedConfiguration = const AiConfiguration();
  bool _loading = true;
  bool _saving = false;
  bool _showKey = false;
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
      _baseUrl.text = value.baseUrl;
      _model.text = value.model;
      _apiKey.text = value.apiKey;
    } on Object {
      if (mounted) _error = '无法读取 AI 配置，请检查设备安全存储';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final value = _loadedConfiguration.copyWith(
      baseUrl: _baseUrl.text,
      model: _model.text,
      apiKey: _apiKey.text,
    );
    try {
      AiTextService.endpointFor(value.baseUrl);
      if (!value.isComplete) {
        throw const AiRequestException('请填写服务地址、模型与 API Key');
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      await widget.store.save(value);
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
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('AI 服务'),
    content: SizedBox(
      width: 440,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('目前支持 Chat Completions 兼容接口。费用由你填写的服务商账户承担。'),
                  const SizedBox(height: 16),
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
                    'Key 保存在设备安全存储中，不进入书籍工程文件。仅主动执行 AI 操作时发送所选文字。',
                    style: Theme.of(context).textTheme.bodySmall,
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
        key: const ValueKey('save-ai-settings'),
        onPressed: _loading || _saving ? null : _save,
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
                  const Text('默认使用内置提示词。选中的正文会作为单独消息发送；修改提示词不会改变所选内容。'),
                  const SizedBox(height: 16),
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
          helperText: '留空或恢复默认后，不保存自定义内容',
        ),
      ),
    ],
  );
}
