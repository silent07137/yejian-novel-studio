import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'ai_service.dart';

class AiGenerationRecord {
  const AiGenerationRecord({
    required this.id,
    required this.createdAt,
    required this.bookTitle,
    required this.chapterTitle,
    required this.action,
    required this.providerName,
    required this.model,
    required this.templateName,
    required this.result,
  });

  final String id;
  final DateTime createdAt;
  final String bookTitle;
  final String chapterTitle;
  final AiTextAction action;
  final String providerName;
  final String model;
  final String templateName;
  final String result;

  String get actionLabel => switch (action) {
    AiTextAction.polish => '润色',
    AiTextAction.continueWriting => '续写',
    AiTextAction.rewrite => '改写',
    AiTextAction.custom => '自定义',
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'bookTitle': bookTitle,
    'chapterTitle': chapterTitle,
    'action': action.name,
    'providerName': providerName,
    'model': model,
    'templateName': templateName,
    'result': result,
  };

  factory AiGenerationRecord.fromJson(Map<String, dynamic> json) {
    String field(String key) {
      final value = json[key];
      if (value is! String) throw const FormatException('AI 历史记录格式错误');
      return value;
    }

    final time = DateTime.tryParse(field('createdAt'));
    final actionName = field('action');
    final action = AiTextAction.values
        .where((item) => item.name == actionName)
        .firstOrNull;
    if (time == null || action == null) {
      throw const FormatException('AI 历史记录格式错误');
    }
    return AiGenerationRecord(
      id: field('id'),
      createdAt: time,
      bookTitle: field('bookTitle'),
      chapterTitle: field('chapterTitle'),
      action: action,
      providerName: field('providerName'),
      model: field('model'),
      templateName: field('templateName'),
      result: field('result'),
    );
  }
}

class AiGenerationHistory {
  const AiGenerationHistory({
    this.totalCount = 0,
    this.retentionLimit = 50,
    this.records = const [],
  });

  final int totalCount;
  final int retentionLimit;
  final List<AiGenerationRecord> records;

  static const retentionOptions = [20, 50, 100, 200];

  AiGenerationHistory withRecord(AiGenerationRecord record) =>
      AiGenerationHistory(
        totalCount: totalCount + 1,
        retentionLimit: retentionLimit,
        records: [record, ...records].take(retentionLimit).toList(),
      );

  AiGenerationHistory withRetention(int limit) {
    if (!retentionOptions.contains(limit)) {
      throw ArgumentError('不支持的历史保留条数');
    }
    return AiGenerationHistory(
      totalCount: totalCount,
      retentionLimit: limit,
      records: records.take(limit).toList(),
    );
  }

  String encode() => jsonEncode({
    'version': 1,
    'totalCount': totalCount,
    'retentionLimit': retentionLimit,
    'records': records.map((item) => item.toJson()).toList(),
  });

  factory AiGenerationHistory.decode(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['totalCount'] is! int ||
        data['retentionLimit'] is! int ||
        data['records'] is! List) {
      throw const FormatException('AI 历史记录格式错误');
    }
    final records = (data['records'] as List).map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('AI 历史记录格式错误');
      }
      return AiGenerationRecord.fromJson(item);
    }).toList();
    final totalCount = data['totalCount'] as int;
    final limit = data['retentionLimit'] as int;
    if (totalCount < records.length ||
        !retentionOptions.contains(limit) ||
        records.length > limit ||
        records.map((item) => item.id).toSet().length != records.length) {
      throw const FormatException('AI 历史记录格式错误');
    }
    return AiGenerationHistory(
      totalCount: totalCount,
      retentionLimit: limit,
      records: records,
    );
  }
}

abstract class AiHistoryStore {
  Future<AiGenerationHistory> load();
  Future<void> save(AiGenerationHistory value);

  Future<AiGenerationHistory> append(AiGenerationRecord record) async {
    final updated = (await load()).withRecord(record);
    await save(updated);
    return updated;
  }
}

/// Separate from book projects; generated text is local and never exported.
class FileAiHistoryStore extends AiHistoryStore {
  FileAiHistoryStore({this.file});

  final File? file;

  Future<File> _file() async {
    if (file != null) return file!;
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}ai_generation_history.json',
    );
  }

  @override
  Future<AiGenerationHistory> load() async {
    final target = await _file();
    if (!await target.exists()) return const AiGenerationHistory();
    return AiGenerationHistory.decode(await target.readAsString());
  }

  @override
  Future<void> save(AiGenerationHistory value) async {
    final target = await _file();
    await target.parent.create(recursive: true);
    await target.writeAsString(value.encode(), flush: true);
  }
}
