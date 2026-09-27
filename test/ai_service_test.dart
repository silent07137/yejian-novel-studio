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

void main() {
  const configuration = AiConfiguration(
    baseUrl: 'https://example.com/v1/',
    model: 'test-model',
    apiKey: 'user-owned-key',
  );

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
