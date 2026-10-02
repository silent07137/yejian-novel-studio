import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/library_data.dart';

/// A bounded, independently scrollable preview. Markdown uses a ListView so
/// offscreen paragraphs do not all participate in layout on every scroll.
class ChapterMarkdownPreview extends StatelessWidget {
  const ChapterMarkdownPreview({
    super.key,
    required this.chapter,
    required this.body,
    required this.scrollController,
    required this.fontSize,
    required this.lineHeight,
    required this.onImageTap,
  });

  final Chapter chapter;
  final String body;
  final ScrollController scrollController;
  final double fontSize;
  final double lineHeight;
  final ValueChanged<ChapterImage> onImageTap;

  @override
  Widget build(BuildContext context) {
    final images = {for (final image in chapter.images) image.id: image};
    return Scrollbar(
      controller: scrollController,
      child: Markdown(
        // Markdown caches image widgets when prose is unchanged. Width-only
        // edits must invalidate those widgets too, without changing the prose.
        key: ValueKey(
          Object.hashAll(
            chapter.images.map(
              (image) => Object.hash(
                image.id,
                image.path,
                image.alt,
                image.widthFactor,
              ),
            ),
          ),
        ),
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        shrinkWrap: false,
        padding: EdgeInsets.zero,
        data: body,
        selectable: true,
        softLineBreak: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: TextStyle(fontSize: fontSize, height: lineHeight),
        ),
        imageBuilder: (uri, title, alt) {
          if (uri.scheme != 'yejian-image') {
            return Text('外部图片暂不预览：${alt ?? uri}');
          }
          final image = images[uri.path];
          if (image == null || image.path.isEmpty) {
            return const Text('〔图片文件未找到〕');
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth * image.widthFactor;
              final cacheWidth =
                  (width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
                    1,
                    2048,
                  );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: width,
                    child: Tooltip(
                      message: '点击调整图片大小和说明',
                      child: InkWell(
                        onTap: () => onImageTap(image),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Image.file(
                              File(image.path),
                              key: ValueKey('preview-image-${image.id}'),
                              cacheWidth: cacheWidth,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Text('〔图片无法读取〕'),
                            ),
                            if ((alt ?? image.alt).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  alt ?? image.alt,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
