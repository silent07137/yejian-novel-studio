import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AiTextAction { polish, continueWriting, rewrite, custom }

String defaultAiPrompt(AiTextAction action) => switch (action) {
  AiTextAction.polish =>
    '你是中文小说编辑。润色给定正文，保留原有剧情事实、人物称呼、叙事视角和 Markdown 标记。只输出润色后的正文，不要解释。',
  AiTextAction.continueWriting =>
    '你是中文小说写作助手。根据给定正文续写一小段，保持原有叙事视角与文风。只输出新写的正文，不要重复原文或解释。',
  AiTextAction.rewrite =>
    '你是中文小说编辑。改写给定正文，保留剧情事实、人物关系、叙事视角和 Markdown 标记。只输出改写后的正文，不要解释。',
  AiTextAction.custom =>
    '你是中文小说创作助手。根据本次指令处理给定正文，尊重作品参考资料，不擅自改变已知设定。只输出处理结果，不要解释。',
};

class AiConfiguration {
  const AiConfiguration({
    this.baseUrl = 'https://api.openai.com/v1',
    this.model = '',
    this.apiKey = '',
    this.polishPrompt = '',
    this.continueWritingPrompt = '',
    this.rewritePrompt = '',
    this.customPrompt = '',
  });

  final String baseUrl;
  final String model;
  final String apiKey;

  /// Empty means the built-in prompt, so future default improvements still apply.
  final String polishPrompt;
  final String continueWritingPrompt;
  final String rewritePrompt;
  final String customPrompt;

  String promptFor(AiTextAction action) {
    final custom = switch (action) {
      AiTextAction.polish => polishPrompt,
      AiTextAction.continueWriting => continueWritingPrompt,
      AiTextAction.rewrite => rewritePrompt,
      AiTextAction.custom => customPrompt,
    };
    return custom.trim().isEmpty ? defaultAiPrompt(action) : custom.trim();
  }

  AiConfiguration copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
    String? polishPrompt,
    String? continueWritingPrompt,
    String? rewritePrompt,
    String? customPrompt,
  }) => AiConfiguration(
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    polishPrompt: polishPrompt ?? this.polishPrompt,
    continueWritingPrompt: continueWritingPrompt ?? this.continueWritingPrompt,
    rewritePrompt: rewritePrompt ?? this.rewritePrompt,
    customPrompt: customPrompt ?? this.customPrompt,
  );

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;
}

abstract interface class AiSettingsStore {
  Future<AiConfiguration> load();
  Future<void> save(AiConfiguration value);
}

/// AI credentials are deliberately kept outside the book database and archives.
class SecureAiSettingsStore implements AiSettingsStore {
  const SecureAiSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _baseUrlKey = 'ai.base_url';
  static const _modelKey = 'ai.model';
  static const _apiKeyKey = 'ai.api_key';
  static const _polishPromptKey = 'ai.prompt.polish';
  static const _continueWritingPromptKey = 'ai.prompt.continue_writing';
  static const _rewritePromptKey = 'ai.prompt.rewrite';
  static const _customPromptKey = 'ai.prompt.custom';

  @override
  Future<AiConfiguration> load() async => AiConfiguration(
    baseUrl:
        await _storage.read(key: _baseUrlKey) ?? 'https://api.openai.com/v1',
    model: await _storage.read(key: _modelKey) ?? '',
    apiKey: await _storage.read(key: _apiKeyKey) ?? '',
    polishPrompt: await _storage.read(key: _polishPromptKey) ?? '',
    continueWritingPrompt:
        await _storage.read(key: _continueWritingPromptKey) ?? '',
    rewritePrompt: await _storage.read(key: _rewritePromptKey) ?? '',
    customPrompt: await _storage.read(key: _customPromptKey) ?? '',
  );

  @override
  Future<void> save(AiConfiguration value) async {
    await _storage.write(key: _baseUrlKey, value: value.baseUrl.trim());
    await _storage.write(key: _modelKey, value: value.model.trim());
    await _storage.write(key: _apiKeyKey, value: value.apiKey.trim());
    await _storage.write(
      key: _polishPromptKey,
      value: value.polishPrompt.trim(),
    );
    await _storage.write(
      key: _continueWritingPromptKey,
      value: value.continueWritingPrompt.trim(),
    );
    await _storage.write(
      key: _rewritePromptKey,
      value: value.rewritePrompt.trim(),
    );
    await _storage.write(
      key: _customPromptKey,
      value: value.customPrompt.trim(),
    );
  }
}

class AiRequestException implements Exception {
  const AiRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AiTransport {
  Future<Map<String, dynamic>> post(
    Uri uri, {
    required String apiKey,
    required Map<String, dynamic> body,
  });
}

class HttpAiTransport implements AiTransport {
  const HttpAiTransport();

  @override
  Future<Map<String, dynamic>> post(
    Uri uri, {
    required String apiKey,
    required Map<String, dynamic> body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      if (response.contentLength > 1024 * 1024) {
        throw const AiRequestException('AI 返回内容过大');
      }
      final responseBytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 90))) {
        responseBytes.addAll(chunk);
        if (responseBytes.length > 1024 * 1024) {
          throw const AiRequestException('AI 返回内容过大');
        }
      }
      if (response.statusCode != HttpStatus.ok) {
        throw AiRequestException('AI 请求失败（HTTP ${response.statusCode}）');
      }
      final dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(responseBytes));
      } on FormatException {
        throw const AiRequestException('AI 返回格式不正确');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const AiRequestException('AI 返回格式不正确');
      }
      return decoded;
    } on AiRequestException {
      rethrow;
    } on Object {
      throw const AiRequestException('无法连接 AI 服务，请检查网络与服务地址');
    } finally {
      client.close(force: true);
    }
  }
}

class AiTextService {
  const AiTextService({AiTransport? transport})
    : _transport = transport ?? const HttpAiTransport();

  final AiTransport _transport;

  static Uri endpointFor(String baseUrl) {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const AiRequestException(
        'API 地址必须是 HTTPS 地址（例如 https://api.example.com/v1）',
      );
    }
    final path = base.path.replaceFirst(RegExp(r'/+$'), '');
    return base.replace(path: '$path/chat/completions');
  }

  Future<String> generate({
    required AiConfiguration configuration,
    required AiTextAction action,
    required String selectedText,
    String contextText = '',
    String customInstruction = '',
  }) async {
    if (!configuration.isComplete) {
      throw const AiRequestException('请先在应用设置中填写 AI 服务地址、模型与 API Key');
    }
    if (selectedText.trim().isEmpty) {
      throw const AiRequestException('请先选择要处理的正文范围');
    }
    if (selectedText.length > 8000) {
      throw const AiRequestException('一次最多处理 8000 字符，请缩小选区');
    }
    if (selectedText.contains('yejian-image:')) {
      throw const AiRequestException('选区包含图片标记，请只选择正文文字');
    }
    if (contextText.length > 5000) {
      throw const AiRequestException('作品参考资料过长，请缩小发送范围');
    }
    if (action == AiTextAction.custom && customInstruction.trim().isEmpty) {
      throw const AiRequestException('请填写本次 AI 指令');
    }
    if (customInstruction.length > 1000) {
      throw const AiRequestException('本次 AI 指令不能超过 1000 字符');
    }
    final instruction = configuration.promptFor(action);
    final userContent =
        contextText.trim().isEmpty && action != AiTextAction.custom
        ? selectedText
        : [
            if (contextText.trim().isNotEmpty)
              '【作品参考资料】\n${contextText.trim()}',
            '【处理正文】\n$selectedText',
            if (action == AiTextAction.custom)
              '【本次指令】\n${customInstruction.trim()}',
          ].join('\n\n');
    final result = await _transport.post(
      endpointFor(configuration.baseUrl),
      apiKey: configuration.apiKey.trim(),
      body: {
        'model': configuration.model.trim(),
        'messages': [
          {'role': 'system', 'content': instruction},
          {'role': 'user', 'content': userContent},
        ],
      },
    );
    final choices = result['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiRequestException('AI 没有返回正文');
    }
    final choice = choices.first as Map;
    if (choice['finish_reason'] == 'length') {
      throw const AiRequestException('AI 回复被截断，请缩小选区后重试');
    }
    final message = choice['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const AiRequestException('AI 没有返回可用正文');
    }
    return content.trim();
  }
}

class AiTextChange {
  const AiTextChange(this.body, this.caretOffset);

  final String body;
  final int caretOffset;
}

AiTextChange applyAiText({
  required String body,
  required String expectedBody,
  required int start,
  required int end,
  required String expectedText,
  required String generatedText,
  required AiTextAction action,
}) {
  if (body != expectedBody ||
      start < 0 ||
      end > body.length ||
      start >= end ||
      body.substring(start, end) != expectedText) {
    throw const AiRequestException('正文或选区已变化，请重新选择后重试');
  }
  final generated = generatedText.trim();
  if (generated.isEmpty) {
    throw const AiRequestException('AI 没有返回可用正文');
  }
  if (action != AiTextAction.continueWriting) {
    return AiTextChange(
      body.replaceRange(start, end, generated),
      start + generated.length,
    );
  }
  final before = body.substring(0, end);
  final after = body.substring(end);
  final leading = before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final trailing = after.isEmpty || after.startsWith('\n\n')
      ? ''
      : after.startsWith('\n')
      ? '\n'
      : '\n\n';
  return AiTextChange(
    '$before$leading$generated$trailing$after',
    end + leading.length + generated.length,
  );
}
