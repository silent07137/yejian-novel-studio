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
