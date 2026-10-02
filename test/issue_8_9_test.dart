import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/data/local_store.dart';
import 'package:yejian_native/main.dart';
import 'package:yejian_native/models/library_data.dart';
import 'package:yejian_native/state/app_controller.dart';
import 'package:yejian_native/ui/card_pages.dart';
import 'package:yejian_native/ui/chapter_markdown_preview.dart';

class _Store implements DataStore {
  _Store(this.data);
  LibraryData data;
  @override
  Future<LibraryData> load() async => data;
  @override
  Future<void> save(LibraryData data) async => this.data = data;
}

Future<AppController> _openWriting(
  WidgetTester tester, {
  bool desktop = false,
}) async {
  tester.view.physicalSize = desktop
      ? const Size(1600, 1000)
      : const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final data = LibraryData.seeded(profileSetupComplete: true);
  final controller = AppController(store: _Store(data), data: data);
  addTearDown(controller.dispose);
  controller.openBook(data.books.first.id);
  controller.navigateBook(WorkspacePage.writing);
  await tester.pumpWidget(YejianApp(controller: controller));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.tap(find.byTooltip('在本书中搜索'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, query);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, query).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('目录外部改名即时同步编辑标题，光标移动不反复保存', (tester) async {
    final controller = await _openWriting(tester, desktop: true);
    final chapter = controller.activeChapter!;
    final body = chapter.body;
    controller.renameChapter(chapter.id, '第一章 酒馆');
    await tester.pumpAndSettle();
    final title = tester
        .widget<TextField>(find.byKey(const ValueKey('chapter-title-field')))
        .controller!;
    expect(title.text, '第一章 酒馆');
    title.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(chapter.body, body);
    await tester.enterText(
      find.byKey(const ValueKey('chapter-title-field')),
      '第一章 修订',
    );
    await tester.pumpAndSettle();
    expect(chapter.title, '第一章 修订');
    expect(find.text('第一章 修订'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('桌面本章笔记可编辑并与章节大纲共用字段，角色可打开详情', (tester) async {
    final controller = await _openWriting(tester, desktop: true);
    await tester.tap(find.byKey(const ValueKey('edit-chapter-summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chapter-summary-field')),
      '新大纲：到达酒馆',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(controller.activeChapter!.summary, '新大纲：到达酒馆');
    expect(find.text('新大纲：到达酒馆'), findsOneWidget);
    final roleId = controller.activeBook!.roles.first.id;
    await tester.tap(find.byKey(ValueKey('reference-role-$roleId')));
    await tester.pumpAndSettle();
    expect(find.byType(RoleDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('搜索角色世界观和事件均打开命中条目而不是仅切换模块', (tester) async {
    final controller = await _openWriting(tester);
    final book = controller.activeBook!;
    final role = book.roles.last;
    await _search(tester, role.name);
    expect(
      tester.widget<RoleDetailPage>(find.byType(RoleDetailPage)).initialRole.id,
      role.id,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final world = book.worlds.first;
    await _search(tester, world.title);
    expect(
      tester
          .widget<WorldDetailPage>(find.byType(WorldDetailPage))
          .initialWorld
          .id,
      world.id,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final event = book.events.first;
    event.description = List.generate(100, (i) => '事件详情第 $i 段。').join('\n');
    await _search(tester, event.title);
    expect(controller.page, WorkspacePage.timeline);
    final preview = find.byKey(ValueKey('event-preview-scroll-${event.id}'));
    expect(preview, findsOneWidget);
    final scrollable = find
        .descendant(of: preview, matching: find.byType(Scrollable))
        .first;
    final state = tester.state<ScrollableState>(scrollable);
    expect(state.position.maxScrollExtent, greaterThan(0));
    await tester.drag(preview, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
    expect(find.text('编辑事件'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('长 Markdown 预览独立滚动，不受标题焦点影响', (tester) async {
    final controller = await _openWriting(tester);
    controller.updateChapterBody(
      List.generate(100, (i) => '第 $i 段正文。').join('\n\n'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chapter-title-field')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('markdown-preview-toggle')));
    await tester.pumpAndSettle();
    final preview = tester.widget<ChapterMarkdownPreview>(
      find.byType(ChapterMarkdownPreview),
    );
    expect(preview.scrollController.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey('markdown-preview')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(preview.scrollController.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('正文预览图片可调整宽度与说明并保持上下文', (tester) async {
    final folder = Directory.systemTemp.createTempSync('yejian-image-size-');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('assets/branding/launcher_icon_1024.png')
        .copySync('${folder.path}/image.png');
    final controller = await _openWriting(tester);
    final image = ChapterImage(id: 'resizable', path: file.path, alt: '旧说明');
    controller.activeChapter!.images.add(image);
    controller.updateChapterBody(
      '图片上文\n\n![旧说明](yejian-image:resizable)\n\n图片下文',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('markdown-preview-toggle')));
    await tester.pumpAndSettle();
    final rendered = find.byKey(const ValueKey('preview-image-resizable'));
    final fullWidth = tester.getSize(rendered).width;
    await tester.tap(
      find.ancestor(of: rendered, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    tester
        .widget<Slider>(find.byKey(const ValueKey('chapter-image-width')))
        .onChanged!(.5);
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(image.widthFactor, .5);
    expect(image.alt, '旧说明');
    expect(controller.activeChapter!.body, contains('![旧说明]'));
    expect(tester.getSize(rendered).width, closeTo(fullWidth / 2, 1));
    await tester.tap(
      find.ancestor(of: rendered, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '图片说明'), '新说明');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(image.alt, '新说明');
    expect(controller.activeChapter!.body, contains('![新说明]'));
    expect(find.text('图片上文'), findsOneWidget);
    expect(find.text('图片下文'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });
}
