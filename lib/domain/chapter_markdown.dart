import '../models/library_data.dart';

final RegExp chapterImagePattern = RegExp(
  r'!\[([^\]\n]*)\]\(yejian-image:([A-Za-z0-9-]+)\)',
);

class ImageInsertion {
  const ImageInsertion(this.body, this.caretOffset);

  final String body;
  final int caretOffset;
}

String chapterImageReference(ChapterImage image) {
  final alt = image.alt.replaceAll(RegExp(r'[\]\r\n]'), ' ');
  return '![$alt](yejian-image:${image.id})';
}

ImageInsertion insertChapterImageReference(
  String body,
  int offset,
  ChapterImage image,
) {
  final point = offset.clamp(0, body.length);
  final before = body.substring(0, point);
  final after = body.substring(point);
  final leading = before.isEmpty
      ? ''
      : before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final trailing = after.isEmpty || after.startsWith('\n\n')
      ? ''
      : after.startsWith('\n')
      ? '\n'
      : '\n\n';
  final inserted = '$leading${chapterImageReference(image)}$trailing';
  return ImageInsertion(
    '$before$inserted$after',
    before.length + inserted.length,
  );
}

Set<String> referencedChapterImageIds(String body) => {
  for (final match in chapterImagePattern.allMatches(body)) match.group(2)!,
};

String markdownForExternalExport(
  String body,
  Map<String, String> relativeImagePaths,
) => body.replaceAllMapped(chapterImagePattern, (match) {
  final path = relativeImagePaths[match.group(2)];
  if (path == null) return '〔图片缺失：${match.group(1)}〕';
  return '![${match.group(1)}]($path)';
});

String plainTextFromMarkdown(String body) {
  final withImages = body.replaceAllMapped(
    chapterImagePattern,
    (match) => '〔图片：${match.group(1)!.isEmpty ? '未命名' : match.group(1)}〕',
  );
  return withImages
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'),
        (match) => match.group(1)!,
      )
      .replaceAll(RegExp(r'^ {0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^ {0,3}>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*(?:[-*+]|\d+\.)\s+', multiLine: true), '')
      .replaceAll(RegExp(r'(?<!\\)(?:\*\*|__|~~|`|\*|_)'), '');
}
