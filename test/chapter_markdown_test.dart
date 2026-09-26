import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/domain/chapter_markdown.dart';
import 'package:yejian_native/models/library_data.dart';

void main() {
  final image = ChapterImage(
    id: 'image-123',
    path: '/local/cover.png',
    alt: '旧书馆',
  );

  test('正文图片作为独立段落插入，光标停在图片之后', () {
    final result = insertChapterImageReference('上文。下文。', 3, image);
    expect(result.body, '上文。\n\n![旧书馆](yejian-image:image-123)\n\n下文。');
    expect(result.caretOffset, result.body.indexOf('下文。'));
    expect(referencedChapterImageIds(result.body), {'image-123'});

    final atStart = insertChapterImageReference('正文', 0, image);
    expect(atStart.body, '![旧书馆](yejian-image:image-123)\n\n正文');
    final atEnd = insertChapterImageReference('正文', 2, image);
    expect(atEnd.body, '正文\n\n![旧书馆](yejian-image:image-123)');
  });

  test('Markdown 与纯文本导出不暴露设备路径或内部图片标识', () {
    final body = '# 标题\n\n**重点**\n\n![旧书馆](yejian-image:image-123)';
    expect(
      markdownForExternalExport(body, {'image-123': 'assets/image-123.png'}),
      contains('![旧书馆](assets/image-123.png)'),
    );
    final plain = plainTextFromMarkdown(body);
    expect(plain, contains('标题\n\n重点'));
    expect(plain, contains('〔图片：旧书馆〕'));
    expect(plain, isNot(contains('yejian-image:')));
  });
}
