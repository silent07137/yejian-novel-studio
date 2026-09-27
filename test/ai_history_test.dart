import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/ai/ai_history.dart';
import 'package:yejian_native/ai/ai_service.dart';

AiGenerationRecord record(int number) => AiGenerationRecord(
  id: '$number',
  createdAt: DateTime.utc(2026, 9, 27, 12, number % 60),
  bookTitle: '测试作品',
  chapterTitle: '第一章',
  action: AiTextAction.polish,
  providerName: '服务',
  model: 'novel-model',
  templateName: '简洁',
  result: '生成结果 $number',
);

void main() {
  test('累计生成次数独立于保留结果条数，缩减上限会裁剪旧结果', () {
    var history = const AiGenerationHistory(retentionLimit: 20);
    for (var i = 0; i < 25; i++) {
      history = history.withRecord(record(i));
    }
    expect(history.totalCount, 25);
    expect(history.records.length, 20);
    expect(history.records.first.result, '生成结果 24');
    expect(history.records.last.result, '生成结果 5');
    history = history.withRetention(50);
    expect(history.totalCount, 25);
    expect(history.records.length, 20);
    expect(AiGenerationHistory.decode(history.encode()).records.length, 20);
  });

  test('结果历史保存在工程之外，文件不含 API Key 或源正文', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yejian-ai-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}history.json');
    final store = FileAiHistoryStore(file: file);
    expect((await store.load()).totalCount, 0);
    final saved = await store.append(record(1));
    expect(saved.totalCount, 1);
    expect((await store.load()).records.single.result, '生成结果 1');
    final raw = await file.readAsString();
    expect(raw, isNot(contains('private-key')));
    expect(raw, isNot(contains('原始正文')));
  });

  test('损坏的历史数据不被当作空历史覆盖', () {
    expect(
      () => AiGenerationHistory.decode('{"version":1}'),
      throwsFormatException,
    );
    expect(
      () => AiGenerationHistory.decode(
        const AiGenerationHistory()
            .withRecord(record(1))
            .encode()
            .replaceFirst('"totalCount":1', '"totalCount":0'),
      ),
      throwsFormatException,
    );
  });
}
