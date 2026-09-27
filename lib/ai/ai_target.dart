import 'ai_service.dart';

enum AiTextScope { selection, paragraph, cursor, chapter }

class AiTextTarget {
  const AiTextTarget(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  static AiTextTarget resolve({
    required String body,
    required int selectionStart,
    required int selectionEnd,
    required AiTextScope scope,
  }) {
    if (selectionStart < 0 ||
        selectionEnd < selectionStart ||
        selectionEnd > body.length) {
      throw const AiRequestException('光标位置已变化，请重新打开 AI 助手');
    }
    late final int start;
    late final int end;
    switch (scope) {
      case AiTextScope.selection:
        start = selectionStart;
        end = selectionEnd;
      case AiTextScope.paragraph:
        final before = selectionStart == 0
            ? -1
            : body.lastIndexOf('\n', selectionStart - 1);
        start = before + 1;
        final after = body.indexOf('\n', selectionStart);
        end = after < 0 ? body.length : after;
      case AiTextScope.cursor:
        end = selectionEnd;
        start = (end - 800).clamp(0, end);
      case AiTextScope.chapter:
        start = 0;
        end = body.length;
    }
    final text = body.substring(start, end);
    if (text.trim().isEmpty) {
      throw AiRequestException(
        scope == AiTextScope.cursor ? '光标前还没有正文，请先写一段再续写' : '此范围没有可处理的正文',
      );
    }
    if (text.length > 8000) {
      throw const AiRequestException('一次最多处理 8000 字符，请缩小范围');
    }
    if (text.contains('yejian-image:')) {
      throw const AiRequestException('范围包含图片，请缩小到纯文字');
    }
    return AiTextTarget(start, end, text);
  }
}
