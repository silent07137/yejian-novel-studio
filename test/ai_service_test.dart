import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/ai/ai_service.dart';

class _FakeTransport implements AiTransport {
  Uri? endpoint;
  String? key;
  Map<String, dynamic>? body;
  Map<String, dynamic> response = {
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': '润色后的文字'},
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> post(
    Uri uri, {
    required String apiKey,
    required Map<String, dynamic> body,
  }) async {
    endpoint = uri;
    key = apiKey;
    this.body = body;
    return response;
  }
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage(this.values);

  final Map<String, String> values;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

void main() {
  const configuration = AiConfiguration(
    baseUrl: 'https://example.com/v1/',
    model: 'test-model',
    apiKey: 'user-owned-key',
  );

  test('旧版单 API 配置自动显示为可切换配置，提示词保持共用', () async {
    final storage = _MemorySecureStorage({
      'ai.base_url': 'https://legacy.example/v1',
      'ai.model': 'legacy-model',
      'ai.api_key': 'legacy-key',
      'ai.prompt.polish': '原有提示词',
    });
    final store = SecureAiSettingsStore(storage: storage);
    final legacy = await store.loadProviders();
    expect(legacy.profiles.single.name, '原有配置');
    expect((await store.load()).apiKey, 'legacy-key');

    await store.saveProviders(
      AiProviderCatalog(
        profiles: [
          ...legacy.profiles,
          const AiProviderProfile(
            id: 'second',
            name: '备用服务',
            baseUrl: 'https://second.example/v1',
            model: 'second-model',
            apiKey: 'second-key',
          ),
        ],
        activeId: 'second',
      ),
    );
    final selected = await store.load();
    expect(selected.apiKey, 'second-key');
    expect(selected.polishPrompt, '原有提示词');
    expect((await store.loadProviders()).profiles.length, 2);
    expect(storage.values.containsKey('ai.api_key'), isFalse);
    await store.save(selected.copyWith(polishPrompt: '新提示词'));
    expect((await store.loadProviders()).activeId, 'second');
    expect((await store.load()).apiKey, 'second-key');
    expect((await store.load()).polishPrompt, '新提示词');
  });

  test('多组 API 序列化保留当前选择，损坏数据不会静默清空', () {
    const catalog = AiProviderCatalog(
      profiles: [
        AiProviderProfile(
          id: 'one',
          name: '主服务',
          baseUrl: 'https://example.com/v1',
          model: 'novel-model',
          apiKey: 'private-key',
        ),
      ],
      activeId: 'one',
    );
    final decoded = AiProviderCatalog.decode(catalog.encode());
    expect(decoded.activeProfile?.apiKey, 'private-key');
    expect(
      () => AiProviderCatalog.decode(
        '{"version":1,"activeId":"missing","profiles":[]}',
      ),
      throwsFormatException,
    );
  });

  test('旧提示词迁移成独立模板，内置模板可修改、隐藏及恢复', () async {
    final storage = _MemorySecureStorage({'ai.prompt.polish': '旧润色要求'});
    final store = SecureAiSettingsStore(storage: storage);
    final migrated = await store.loadPromptCatalog();
    expect(migrated.defaultTemplate.name, '原有提示词');
    expect(migrated.defaultTemplate.promptFor(AiTextAction.polish), '旧润色要求');
    await store.savePromptCatalog(
      AiPromptCatalog(
        customTemplates: migrated.customTemplates,
        builtinOverrides: const [
          AiPromptTemplate(
            id: 'builtin-concise',
            name: '精简版',
            styleInstruction: '减少赘述',
          ),
        ],
        hiddenBuiltinIds: const ['builtin-delicate'],
        defaultTemplateId: 'builtin-concise',
      ),
    );
    final loaded = await store.loadPromptCatalog();
    expect(loaded.defaultTemplate.name, '精简版');
    expect(
      loaded.defaultTemplate.promptFor(AiTextAction.rewrite),
      contains('减少赘述'),
    );
    expect(loaded.templateById('builtin-delicate'), isNull);
    expect(storage.values.containsKey('ai.prompt.polish'), isFalse);
    expect(
      () => AiPromptCatalog.decode(
        '{"version":1,"defaultTemplateId":"missing","customTemplates":[]}',
      ),
      throwsFormatException,
    );
  });

  test('四种默认操作提示词独立于文风，并迁移旧版自定义提示词', () async {
    final storage = _MemorySecureStorage({'ai.prompt.polish': '旧润色词'});
    final store = SecureAiSettingsStore(storage: storage);
    final migrated = await store.loadOperationPromptCatalog();
    expect(migrated.defaultFor(AiTextAction.polish).content, '旧润色词');
    await store.savePromptCatalog(const AiPromptCatalog());
    expect(
      (await store.loadOperationPromptCatalog())
          .defaultFor(AiTextAction.polish)
          .content,
      '旧润色词',
    );
    expect(
      migrated.defaultFor(AiTextAction.rewrite).content,
      defaultAiPrompt(AiTextAction.rewrite),
    );
    expect(builtinAiOperationPrompts.length, 4);
    await store.saveOperationPromptCatalog(
      AiOperationPromptCatalog(
        customPrompts: migrated.customPrompts,
        builtinOverrides: const [
          AiOperationPrompt(
            id: 'builtin-operation-rewrite',
            name: '重写事实',
            action: AiTextAction.rewrite,
            content: '保留事实，只改句式',
          ),
        ],
        defaultIds: migrated.defaultIds,
      ),
    );
    final loaded = await store.loadOperationPromptCatalog();
    expect(loaded.defaultFor(AiTextAction.rewrite).content, '保留事实，只改句式');
    expect(loaded.defaultFor(AiTextAction.polish).content, '旧润色词');
    expect(
      () => AiOperationPromptCatalog.decode(
        '{"version":1,"customPrompts":[],"builtinOverrides":[],"hiddenBuiltinIds":["builtin-operation-polish"],"defaultIds":{}}',
      ),
      throwsFormatException,
    );
  });

  test('仅发送选区至 Chat Completions 兼容接口', () async {
    final transport = _FakeTransport();
    final service = AiTextService(transport: transport);
    final result = await service.generate(
      configuration: configuration,
      action: AiTextAction.polish,
      selectedText: '只发送这句',
    );

    expect(result, '润色后的文字');
    expect(
      transport.endpoint.toString(),
      'https://example.com/v1/chat/completions',
    );
    expect(transport.key, 'user-owned-key');
    expect(transport.body?['model'], 'test-model');
    final messages = transport.body?['messages'] as List;
    expect((messages.last as Map)['content'], '只发送这句');
    expect(
      (messages.first as Map)['content'],
      defaultAiPrompt(AiTextAction.polish),
    );
  });

  test('自定义提示词只覆盖对应操作，空白回退内置提示词', () async {
    final transport = _FakeTransport();
    final service = AiTextService(transport: transport);
    final custom = configuration.copyWith(
      polishPrompt: '请用简洁文风润色，只输出正文。',
      continueWritingPrompt: '  ',
    );
    await service.generate(
      configuration: custom,
      action: AiTextAction.polish,
      selectedText: '原句',
    );
    var messages = transport.body?['messages'] as List;
    expect((messages.first as Map)['content'], '请用简洁文风润色，只输出正文。');
    expect((messages.last as Map)['content'], '原句');

    await service.generate(
      configuration: custom,
      action: AiTextAction.continueWriting,
      selectedText: '原句',
    );
    messages = transport.body?['messages'] as List;
    expect(
      (messages.first as Map)['content'],
      defaultAiPrompt(AiTextAction.continueWriting),
    );
  });

  test('改写使用独立提示词；自定义指令和作品资料只在明确传入时发送', () async {
    final transport = _FakeTransport();
    final service = AiTextService(transport: transport);
    await service.generate(
      configuration: configuration.copyWith(rewritePrompt: '保持事实，改写文风。'),
      action: AiTextAction.rewrite,
      selectedText: '原句',
      contextText: '【当前章节】旧馆',
    );
    var messages = transport.body?['messages'] as List;
    expect((messages.first as Map)['content'], '保持事实，改写文风。');
    expect((messages.last as Map)['content'], contains('【当前章节】旧馆'));
    expect((messages.last as Map)['content'], contains('【处理正文】\n原句'));

    await service.generate(
      configuration: configuration,
      action: AiTextAction.custom,
      selectedText: '原句',
      customInstruction: '改成第一人称',
    );
    messages = transport.body?['messages'] as List;
    expect(
      (messages.first as Map)['content'],
      defaultAiPrompt(AiTextAction.custom),
    );
    expect((messages.last as Map)['content'], contains('【本次指令】\n改成第一人称'));
    expect((messages.last as Map)['content'], isNot(contains('旧馆')));
  });

  test('自定义操作必须填写本次指令，参考资料必须限长', () async {
    final service = AiTextService(transport: _FakeTransport());
    expect(
      service.generate(
        configuration: configuration,
        action: AiTextAction.custom,
        selectedText: '正文',
      ),
      throwsA(isA<AiRequestException>()),
    );
    expect(
      service.generate(
        configuration: configuration,
        action: AiTextAction.rewrite,
        selectedText: '正文',
        contextText: List.filled(5001, 'x').join(),
      ),
      throwsA(isA<AiRequestException>()),
    );
  });

  test('拒绝非 HTTPS 地址、图片标记与不完整配置', () async {
    expect(
      () => AiTextService.endpointFor('http://example.com/v1'),
      throwsA(isA<AiRequestException>()),
    );
    final service = AiTextService(transport: _FakeTransport());
    expect(
      service.generate(
        configuration: const AiConfiguration(),
        action: AiTextAction.polish,
        selectedText: '正文',
      ),
      throwsA(isA<AiRequestException>()),
    );
    expect(
      service.generate(
        configuration: configuration,
        action: AiTextAction.polish,
        selectedText: '![图](yejian-image:123)',
      ),
      throwsA(isA<AiRequestException>()),
    );
  });

  test('润色只替换原选区；续写插入新段落', () {
    final polished = applyAiText(
      body: '开头旧文结尾',
      expectedBody: '开头旧文结尾',
      start: 2,
      end: 4,
      expectedText: '旧文',
      generatedText: '新文',
      action: AiTextAction.polish,
    );
    expect(polished.body, '开头新文结尾');
    expect(polished.caretOffset, 4);

    final continued = applyAiText(
      body: '开头旧文',
      expectedBody: '开头旧文',
      start: 2,
      end: 4,
      expectedText: '旧文',
      generatedText: '下一段',
      action: AiTextAction.continueWriting,
    );
    expect(continued.body, '开头旧文\n\n下一段');

    final rewritten = applyAiText(
      body: '开头旧文',
      expectedBody: '开头旧文',
      start: 2,
      end: 4,
      expectedText: '旧文',
      generatedText: '新文',
      action: AiTextAction.rewrite,
    );
    expect(rewritten.body, '开头新文');
  });

  test('正文变化后不应用过期 AI 结果', () {
    expect(
      () => applyAiText(
        body: '已修改',
        expectedBody: '旧文结尾',
        start: 0,
        end: 2,
        expectedText: '旧文',
        generatedText: '新文',
        action: AiTextAction.polish,
      ),
      throwsA(isA<AiRequestException>()),
    );
  });
}
