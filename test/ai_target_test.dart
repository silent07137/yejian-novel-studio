import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/ai/ai_service.dart';
import 'package:yejian_native/ai/ai_target.dart';

void main() {
  const body = '第一段文字。\n第二段内容。\n第三段。';

  test('无选区时只提取光标所在段落', () {
    final target = AiTextTarget.resolve(
      body: body,
      selectionStart: 9,
      selectionEnd: 9,
      scope: AiTextScope.paragraph,
    );
    expect(target.text, '第二段内容。');
    expect(body.substring(target.start, target.end), target.text);
  });

  test('续写光标前文截止于光标，不取其后的文字', () {
    final cursor = body.indexOf('第三段');
    final target = AiTextTarget.resolve(
      body: body,
      selectionStart: cursor,
      selectionEnd: cursor,
      scope: AiTextScope.cursor,
    );
    expect(target.end, cursor);
    expect(target.text, isNot(contains('第三段')));
    final change = applyAiText(
      body: body,
      expectedBody: body,
      start: target.start,
      end: target.end,
      expectedText: target.text,
      generatedText: '新的桥段。',
      action: AiTextAction.continueWriting,
    );
    expect(change.body, contains('新的桥段。\n\n第三段。'));
  });

  test('选区与整章范围可明确切换', () {
    final selected = AiTextTarget.resolve(
      body: body,
      selectionStart: 0,
      selectionEnd: 5,
      scope: AiTextScope.selection,
    );
    final chapter = AiTextTarget.resolve(
      body: body,
      selectionStart: 0,
      selectionEnd: 5,
      scope: AiTextScope.chapter,
    );
    expect(selected.text, body.substring(0, 5));
    expect(chapter.text, body);
  });

  test('图片和空段落不会发送', () {
    expect(
      () => AiTextTarget.resolve(
        body: '![图](yejian-image:abc)',
        selectionStart: 0,
        selectionEnd: 0,
        scope: AiTextScope.paragraph,
      ),
      throwsA(isA<AiRequestException>()),
    );
    expect(
      () => AiTextTarget.resolve(
        body: body,
        selectionStart: 0,
        selectionEnd: 0,
        scope: AiTextScope.cursor,
      ),
      throwsA(isA<AiRequestException>()),
    );
  });
}
