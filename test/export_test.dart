import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/models/library_data.dart';
import 'package:yejian_native/state/app_controller.dart';

void main() {
  test('TXT 与 Markdown 遵守目录顺序和导出开关', () {
    final visibleVolume = Volume(id: 'v1', title: '第一卷');
    final hiddenVolume = Volume(id: 'v2', title: '隐藏卷', exportEnabled: false);
    final book = Book(
      id: 'book',
      title: '测试书',
      volumes: [visibleVolume, hiddenVolume],
      chapters: [
        Chapter(
          id: 'c1',
          title: '开端',
          body: '第一段。',
          volumeId: visibleVolume.id,
        ),
        Chapter(id: 'c2', title: '不导出章', body: '不能出现', exportEnabled: false),
        Chapter(
          id: 'c3',
          title: '隐藏卷章节',
          body: '也不能出现',
          volumeId: hiddenVolume.id,
        ),
        Chapter(id: 'c4', title: '尾声', body: '结束。'),
      ],
    );

    final text = buildPlainText(book);
    final markdown = buildMarkdown(book);

    expect(text, contains('【第一卷】'));
    expect(text, contains('开端\n\n第一段。'));
    expect(text, contains('尾声\n\n结束。'));
    expect(text, isNot(contains('不能出现')));
    expect(text, isNot(contains('也不能出现')));
    expect(markdown, contains('# 测试书'));
    expect(markdown, contains('## 第一卷'));
    expect(markdown, contains('### 开端'));
    expect(markdown, contains('### 尾声'));
  });
}
