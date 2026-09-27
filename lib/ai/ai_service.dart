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

class AiProviderProfile {
  const AiProviderProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;

  AiProviderProfile copyWith({
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) => AiProviderProfile(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
  );

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
  };

  factory AiProviderProfile.fromJson(Map<String, dynamic> json) {
    String field(String key) {
      final value = json[key];
      if (value is! String) throw const FormatException('AI 配置格式错误');
      return value;
    }

    return AiProviderProfile(
      id: field('id'),
      name: field('name'),
      baseUrl: field('baseUrl'),
      model: field('model'),
      apiKey: field('apiKey'),
    );
  }
}

class AiProviderCatalog {
  const AiProviderCatalog({this.profiles = const [], this.activeId});

  final List<AiProviderProfile> profiles;
  final String? activeId;

  AiProviderProfile? get activeProfile {
    for (final profile in profiles) {
      if (profile.id == activeId) return profile;
    }
    return null;
  }

  String encode() => jsonEncode({
    'version': 1,
    'activeId': activeId,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
  });

  factory AiProviderCatalog.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['profiles'] is! List) {
      throw const FormatException('AI 配置格式错误');
    }
    final profiles = (decoded['profiles'] as List).map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('AI 配置格式错误');
      }
      return AiProviderProfile.fromJson(item);
    }).toList();
    final activeId = decoded['activeId'];
    if (activeId != null && activeId is! String) {
      throw const FormatException('AI 配置格式错误');
    }
    if (profiles.map((profile) => profile.id).toSet().length !=
        profiles.length) {
      throw const FormatException('AI 配置存在重复标识');
    }
    if (activeId != null &&
        !profiles.any((profile) => profile.id == activeId)) {
      throw const FormatException('选中的 API 配置不存在');
    }
    return AiProviderCatalog(profiles: profiles, activeId: activeId as String?);
  }
}

class AiPromptTemplate {
  const AiPromptTemplate({
    required this.id,
    required this.name,
    this.styleInstruction = '',
    this.polishPrompt = '',
    this.continueWritingPrompt = '',
    this.rewritePrompt = '',
    this.customPrompt = '',
  });

  final String id;
  final String name;
  final String styleInstruction;
  final String polishPrompt;
  final String continueWritingPrompt;
  final String rewritePrompt;
  final String customPrompt;

  bool get isBuiltin => id.startsWith('builtin-');

  String promptFor(AiTextAction action) {
    final override = switch (action) {
      AiTextAction.polish => polishPrompt,
      AiTextAction.continueWriting => continueWritingPrompt,
      AiTextAction.rewrite => rewritePrompt,
      AiTextAction.custom => customPrompt,
    };
    final base = override.trim().isEmpty
        ? defaultAiPrompt(action)
        : override.trim();
    final style = styleInstruction.trim();
    return style.isEmpty ? base : '$base\n文风要求：$style';
  }

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'styleInstruction': styleInstruction,
    'polishPrompt': polishPrompt,
    'continueWritingPrompt': continueWritingPrompt,
    'rewritePrompt': rewritePrompt,
    'customPrompt': customPrompt,
  };

  factory AiPromptTemplate.fromJson(Map<String, dynamic> json) {
    String field(String key) {
      final value = json[key];
      if (value is! String) throw const FormatException('文风模板格式错误');
      return value;
    }

    return AiPromptTemplate(
      id: field('id'),
      name: field('name'),
      styleInstruction: field('styleInstruction'),
      polishPrompt: field('polishPrompt'),
      continueWritingPrompt: field('continueWritingPrompt'),
      rewritePrompt: field('rewritePrompt'),
      customPrompt: field('customPrompt'),
    );
  }
}

const builtinAiPromptTemplates = <AiPromptTemplate>[
  AiPromptTemplate(id: 'builtin-default', name: '默认'),
  AiPromptTemplate(
    id: 'builtin-delicate',
    name: '细腻抒情',
    styleInstruction: '以具体感官和人物细微反应承载情绪，语言自然，不堆砌辞藻。',
  ),
  AiPromptTemplate(
    id: 'builtin-concise',
    name: '简洁克制',
    styleInstruction: '句子凝练、信息清楚，少用形容词和解释性心理描写，保留必要留白。',
  ),
  AiPromptTemplate(
    id: 'builtin-suspense',
    name: '悬疑紧凑',
    styleInstruction: '保持清晰的因果和紧凑节奏，利用具体线索制造悬念，不提前揭示答案。',
  ),
];

class AiPromptCatalog {
  const AiPromptCatalog({
    this.customTemplates = const [],
    this.builtinOverrides = const [],
    this.hiddenBuiltinIds = const [],
    this.defaultTemplateId = 'builtin-default',
  });

  final List<AiPromptTemplate> customTemplates;
  final List<AiPromptTemplate> builtinOverrides;
  final List<String> hiddenBuiltinIds;
  final String defaultTemplateId;

  List<AiPromptTemplate> get templates => [
    for (final builtin in builtinAiPromptTemplates)
      if (!hiddenBuiltinIds.contains(builtin.id))
        builtinOverrides.where((item) => item.id == builtin.id).firstOrNull ??
            builtin,
    ...customTemplates,
  ];

  AiPromptTemplate? templateById(String? id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  AiPromptTemplate get defaultTemplate =>
      templateById(defaultTemplateId) ?? builtinAiPromptTemplates.first;

  String encode() => jsonEncode({
    'version': 1,
    'defaultTemplateId': defaultTemplateId,
    'customTemplates': customTemplates.map((item) => item.toJson()).toList(),
    'builtinOverrides': builtinOverrides.map((item) => item.toJson()).toList(),
    'hiddenBuiltinIds': hiddenBuiltinIds,
  });

  factory AiPromptCatalog.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['defaultTemplateId'] is! String ||
        decoded['customTemplates'] is! List) {
      throw const FormatException('文风模板格式错误');
    }
    final customTemplates = (decoded['customTemplates'] as List).map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('文风模板格式错误');
      }
      return AiPromptTemplate.fromJson(item);
    }).toList();
    final overridesRaw = decoded['builtinOverrides'] ?? <dynamic>[];
    final hiddenRaw = decoded['hiddenBuiltinIds'] ?? <dynamic>[];
    if (overridesRaw is! List || hiddenRaw is! List) {
      throw const FormatException('文风模板格式错误');
    }
    final builtinOverrides = overridesRaw.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('文风模板格式错误');
      }
      return AiPromptTemplate.fromJson(item);
    }).toList();
    if (hiddenRaw.any((item) => item is! String)) {
      throw const FormatException('文风模板格式错误');
    }
    final hiddenBuiltinIds = hiddenRaw.cast<String>();
    final catalog = AiPromptCatalog(
      customTemplates: customTemplates,
      builtinOverrides: builtinOverrides,
      hiddenBuiltinIds: hiddenBuiltinIds,
      defaultTemplateId: decoded['defaultTemplateId'] as String,
    );
    if (customTemplates.any(
          (template) =>
              template.id.isEmpty ||
              template.name.trim().isEmpty ||
              template.isBuiltin,
        ) ||
        builtinOverrides.any(
          (template) => !builtinAiPromptTemplates.any(
            (builtin) => builtin.id == template.id,
          ),
        ) ||
        hiddenBuiltinIds.any(
          (id) => !builtinAiPromptTemplates.any((builtin) => builtin.id == id),
        ) ||
        builtinOverrides.map((item) => item.id).toSet().length !=
            builtinOverrides.length ||
        hiddenBuiltinIds.toSet().length != hiddenBuiltinIds.length ||
        catalog.templates.map((template) => template.id).toSet().length !=
            catalog.templates.length ||
        catalog.templates.isEmpty ||
        catalog.templateById(catalog.defaultTemplateId) == null) {
      throw const FormatException('文风模板格式错误');
    }
    return catalog;
  }
}

String aiActionLabel(AiTextAction action) => switch (action) {
  AiTextAction.polish => '润色',
  AiTextAction.continueWriting => '续写',
  AiTextAction.rewrite => '改写',
  AiTextAction.custom => '自定义',
};

class AiOperationPrompt {
  const AiOperationPrompt({
    required this.id,
    required this.name,
    required this.action,
    required this.content,
  });

  final String id;
  final String name;
  final AiTextAction action;
  final String content;

  bool get isBuiltin => id.startsWith('builtin-operation-');

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'action': action.name,
    'content': content,
  };

  factory AiOperationPrompt.fromJson(Map<String, dynamic> json) {
    String field(String key) {
      final value = json[key];
      if (value is! String) throw const FormatException('操作提示词格式错误');
      return value;
    }

    final actionName = field('action');
    final action = AiTextAction.values
        .where((item) => item.name == actionName)
        .firstOrNull;
    if (action == null) throw const FormatException('操作提示词格式错误');
    return AiOperationPrompt(
      id: field('id'),
      name: field('name'),
      action: action,
      content: field('content'),
    );
  }
}

final builtinAiOperationPrompts = [
  for (final action in AiTextAction.values)
    AiOperationPrompt(
      id: 'builtin-operation-${action.name}',
      name: aiActionLabel(action),
      action: action,
      content: defaultAiPrompt(action),
    ),
];

class AiOperationPromptCatalog {
  const AiOperationPromptCatalog({
    this.customPrompts = const [],
    this.builtinOverrides = const [],
    this.hiddenBuiltinIds = const [],
    this.defaultIds = const {},
  });

  final List<AiOperationPrompt> customPrompts;
  final List<AiOperationPrompt> builtinOverrides;
  final List<String> hiddenBuiltinIds;
  final Map<String, String> defaultIds;

  List<AiOperationPrompt> get prompts => [
    for (final builtin in builtinAiOperationPrompts)
      if (!hiddenBuiltinIds.contains(builtin.id))
        builtinOverrides.where((item) => item.id == builtin.id).firstOrNull ??
            builtin,
    ...customPrompts,
  ];

  List<AiOperationPrompt> forAction(AiTextAction action) =>
      prompts.where((item) => item.action == action).toList();

  AiOperationPrompt? promptById(String? id) =>
      prompts.where((item) => item.id == id).firstOrNull;

  AiOperationPrompt defaultFor(AiTextAction action) =>
      forAction(action)
          .where((item) => item.id == defaultIds[action.name])
          .firstOrNull ??
      forAction(action).first;

  String encode() => jsonEncode({
    'version': 1,
    'customPrompts': customPrompts.map((item) => item.toJson()).toList(),
    'builtinOverrides': builtinOverrides.map((item) => item.toJson()).toList(),
    'hiddenBuiltinIds': hiddenBuiltinIds,
    'defaultIds': defaultIds,
  });

  factory AiOperationPromptCatalog.decode(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['customPrompts'] is! List ||
        data['builtinOverrides'] is! List ||
        data['hiddenBuiltinIds'] is! List ||
        data['defaultIds'] is! Map<String, dynamic>) {
      throw const FormatException('操作提示词格式错误');
    }
    List<AiOperationPrompt> parse(List raw) => raw.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('操作提示词格式错误');
      }
      return AiOperationPrompt.fromJson(item);
    }).toList();
    final hidden = data['hiddenBuiltinIds'] as List;
    final defaults = data['defaultIds'] as Map<String, dynamic>;
    if (hidden.any((item) => item is! String) ||
        defaults.values.any((item) => item is! String)) {
      throw const FormatException('操作提示词格式错误');
    }
    final catalog = AiOperationPromptCatalog(
      customPrompts: parse(data['customPrompts'] as List),
      builtinOverrides: parse(data['builtinOverrides'] as List),
      hiddenBuiltinIds: hidden.cast<String>(),
      defaultIds: defaults.cast<String, String>(),
    );
    final ids = catalog.prompts.map((item) => item.id).toList();
    if (ids.toSet().length != ids.length ||
        catalog.builtinOverrides.map((item) => item.id).toSet().length !=
            catalog.builtinOverrides.length ||
        catalog.hiddenBuiltinIds.toSet().length !=
            catalog.hiddenBuiltinIds.length ||
        catalog.defaultIds.keys.any(
          (name) => !AiTextAction.values.any((action) => action.name == name),
        ) ||
        catalog.customPrompts.any(
          (item) =>
              item.id.isEmpty ||
              item.isBuiltin ||
              item.name.trim().isEmpty ||
              item.content.trim().isEmpty,
        ) ||
        catalog.builtinOverrides.any(
          (item) =>
              item.name.trim().isEmpty ||
              item.content.trim().isEmpty ||
              !builtinAiOperationPrompts.any(
                (builtin) =>
                    builtin.id == item.id && builtin.action == item.action,
              ),
        ) ||
        catalog.hiddenBuiltinIds.any(
          (id) => !builtinAiOperationPrompts.any((item) => item.id == id),
        ) ||
        AiTextAction.values.any(
          (action) =>
              catalog.forAction(action).isEmpty ||
              (catalog.defaultIds[action.name] != null &&
                  !catalog
                      .forAction(action)
                      .any(
                        (item) => item.id == catalog.defaultIds[action.name],
                      )),
        )) {
      throw const FormatException('操作提示词格式错误');
    }
    return catalog;
  }
}

abstract interface class AiSettingsStore {
  Future<AiConfiguration> load();

  /// Saves shared prompts only; API profiles are changed through saveProviders.
  Future<void> save(AiConfiguration value);
  Future<AiProviderCatalog> loadProviders();
  Future<void> saveProviders(AiProviderCatalog value);
  Future<AiPromptCatalog> loadPromptCatalog();
  Future<void> savePromptCatalog(AiPromptCatalog value);
  Future<AiOperationPromptCatalog> loadOperationPromptCatalog();
  Future<void> saveOperationPromptCatalog(AiOperationPromptCatalog value);
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
  static const _providersKey = 'ai.providers.v1';
  static const _promptCatalogKey = 'ai.prompt_templates.v1';
  static const _operationPromptsKey = 'ai.operation_prompts.v1';

  @override
  Future<AiProviderCatalog> loadProviders() async {
    final stored = await _storage.read(key: _providersKey);
    if (stored != null) return AiProviderCatalog.decode(stored);
    final baseUrl =
        await _storage.read(key: _baseUrlKey) ?? 'https://api.openai.com/v1';
    final model = await _storage.read(key: _modelKey) ?? '';
    final apiKey = await _storage.read(key: _apiKeyKey) ?? '';
    if (model.isEmpty && apiKey.isEmpty) return const AiProviderCatalog();
    return AiProviderCatalog(
      profiles: [
        AiProviderProfile(
          id: 'legacy',
          name: '原有配置',
          baseUrl: baseUrl,
          model: model,
          apiKey: apiKey,
        ),
      ],
      activeId: 'legacy',
    );
  }

  @override
  Future<void> saveProviders(AiProviderCatalog value) async {
    if (value.activeId != null && value.activeProfile == null) {
      throw const AiRequestException('选中的 API 配置不存在');
    }
    if (value.profiles.map((profile) => profile.id).toSet().length !=
        value.profiles.length) {
      throw const AiRequestException('API 配置存在重复标识');
    }
    await _storage.write(key: _providersKey, value: value.encode());
    await _storage.write(key: _baseUrlKey, value: null);
    await _storage.write(key: _modelKey, value: null);
    await _storage.write(key: _apiKeyKey, value: null);
  }

  @override
  Future<AiPromptCatalog> loadPromptCatalog() async {
    final stored = await _storage.read(key: _promptCatalogKey);
    if (stored != null) return AiPromptCatalog.decode(stored);
    final polish = await _storage.read(key: _polishPromptKey) ?? '';
    final continuation =
        await _storage.read(key: _continueWritingPromptKey) ?? '';
    final rewrite = await _storage.read(key: _rewritePromptKey) ?? '';
    final custom = await _storage.read(key: _customPromptKey) ?? '';
    if ([polish, continuation, rewrite, custom].every((item) => item.isEmpty)) {
      return const AiPromptCatalog();
    }
    return AiPromptCatalog(
      customTemplates: [
        AiPromptTemplate(
          id: 'legacy-prompt',
          name: '原有提示词',
          polishPrompt: polish,
          continueWritingPrompt: continuation,
          rewritePrompt: rewrite,
          customPrompt: custom,
        ),
      ],
      defaultTemplateId: 'legacy-prompt',
    );
  }

  @override
  Future<void> savePromptCatalog(AiPromptCatalog value) async {
    AiPromptCatalog.decode(value.encode());
    await _storage.write(key: _promptCatalogKey, value: value.encode());
    await _storage.write(key: _polishPromptKey, value: null);
    await _storage.write(key: _continueWritingPromptKey, value: null);
    await _storage.write(key: _rewritePromptKey, value: null);
    await _storage.write(key: _customPromptKey, value: null);
  }

  @override
  Future<AiOperationPromptCatalog> loadOperationPromptCatalog() async {
    final stored = await _storage.read(key: _operationPromptsKey);
    if (stored != null) return AiOperationPromptCatalog.decode(stored);
    final styles = await loadPromptCatalog();
    final migrated = <AiOperationPrompt>[];
    final defaults = <String, String>{};
    for (final style in styles.templates) {
      for (final action in AiTextAction.values) {
        final content = switch (action) {
          AiTextAction.polish => style.polishPrompt,
          AiTextAction.continueWriting => style.continueWritingPrompt,
          AiTextAction.rewrite => style.rewritePrompt,
          AiTextAction.custom => style.customPrompt,
        };
        if (content.trim().isEmpty) continue;
        final id = 'migrated-${style.id}-${action.name}';
        migrated.add(
          AiOperationPrompt(
            id: id,
            name: '${style.name} · ${aiActionLabel(action)}',
            action: action,
            content: content.trim(),
          ),
        );
        if (style.id == styles.defaultTemplateId) defaults[action.name] = id;
      }
    }
    final catalog = AiOperationPromptCatalog(
      customPrompts: migrated,
      defaultIds: defaults,
    );
    await saveOperationPromptCatalog(catalog);
    return catalog;
  }

  @override
  Future<void> saveOperationPromptCatalog(
    AiOperationPromptCatalog value,
  ) async {
    AiOperationPromptCatalog.decode(value.encode());
    await _storage.write(key: _operationPromptsKey, value: value.encode());
  }

  @override
  Future<AiConfiguration> load() async {
    final active = (await loadProviders()).activeProfile;
    final template = (await loadPromptCatalog()).defaultTemplate;
    return AiConfiguration(
      baseUrl: active?.baseUrl ?? 'https://api.openai.com/v1',
      model: active?.model ?? '',
      apiKey: active?.apiKey ?? '',
      polishPrompt: template.promptFor(AiTextAction.polish),
      continueWritingPrompt: template.promptFor(AiTextAction.continueWriting),
      rewritePrompt: template.promptFor(AiTextAction.rewrite),
      customPrompt: template.promptFor(AiTextAction.custom),
    );
  }

  @override
  Future<void> save(AiConfiguration value) async {
    final catalog = await loadPromptCatalog();
    final current = catalog.defaultTemplate;
    final id = current.isBuiltin ? 'custom-default' : current.id;
    final replacement = AiPromptTemplate(
      id: id,
      name: current.isBuiltin ? '自定义提示词' : current.name,
      polishPrompt: value.polishPrompt,
      continueWritingPrompt: value.continueWritingPrompt,
      rewritePrompt: value.rewritePrompt,
      customPrompt: value.customPrompt,
    );
    await savePromptCatalog(
      AiPromptCatalog(
        customTemplates: [
          for (final template in catalog.customTemplates)
            if (template.id == id) replacement else template,
          if (!catalog.customTemplates.any((template) => template.id == id))
            replacement,
        ],
        builtinOverrides: catalog.builtinOverrides,
        hiddenBuiltinIds: catalog.hiddenBuiltinIds,
        defaultTemplateId: id,
      ),
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
