import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/ai/ai_context.dart';
import 'package:yejian_native/models/library_data.dart';

void main() {
  test('只整理当前作品中与附近正文匹配的资料，并移除图片标记', () {
    final chapter = Chapter(id: 'chapter-1', title: '灯塔来信', summary: '第一封信');
    final book = Book(
      id: 'book-1',
      title: '雾灯来信',
      chapters: [chapter],
      roles: [
        RoleCard(id: 'role-1', name: '林昭', personality: '谨慎'),
        RoleCard(id: 'role-2', name: '顾远', personality: '冲动'),
      ],
      worlds: [
        WorldCard(id: 'world-1', title: '灯塔书馆', rule: '夜间闭馆'),
        WorldCard(id: 'world-2', title: '山谷城', rule: '禁止外出'),
      ],
      events: [
        StoryEvent(
          id: 'event-1',
          title: '第七封信出现',
          storyDate: '秋一日',
          roleIds: ['role-1'],
        ),
      ],
    );
    const body = '林昭走进灯塔书馆。![封面](yejian-image:image-1)她看见一封信。';
    final context = const AiContextBuilder().build(
      book: book,
      chapter: chapter,
      currentBody: body,
      selectionStart: 0,
      selectionEnd: 8,
    );

    expect(context, contains('【当前作品】雾灯来信'));
    expect(context, contains('【当前章节】灯塔来信'));
    expect(context, contains('林昭'));
    expect(context, contains('灯塔书馆'));
    expect(context, contains('第七封信出现'));
    expect(context, isNot(contains('顾远')));
    expect(context, isNot(contains('山谷城')));
    expect(context, isNot(contains('yejian-image:')));
    expect(context.length, lessThanOrEqualTo(4801));
  });

  test('长章节只截取选区附近，不把远处正文送入上下文', () {
    final chapter = Chapter(id: 'chapter-1', title: '长章');
    final body =
        '${List.filled(300, '远处秘密').join()}林昭走进书馆。'
        '${List.filled(300, '尾声').join()}';
    final start = body.indexOf('林昭');
    final context = const AiContextBuilder().build(
      book: Book(id: 'book-1', title: '测试', chapters: [chapter]),
      chapter: chapter,
      currentBody: body,
      selectionStart: start,
      selectionEnd: start + 2,
    );

    expect(context, contains('林昭走进书馆'));
    expect(context.length, lessThan(body.length));
    expect(context.length, lessThanOrEqualTo(4801));
  });
}
