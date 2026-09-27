import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/ai/ai_service.dart';
import 'package:yejian_native/ai/ai_history.dart';
import 'package:yejian_native/data/local_store.dart';
import 'package:yejian_native/main.dart';
import 'package:yejian_native/models/library_data.dart';
import 'package:yejian_native/state/app_controller.dart';
import 'package:yejian_native/ui/card_pages.dart';
import 'package:yejian_native/ui/workspace_shell.dart';

class MemoryStore implements DataStore {
  MemoryStore(this.data);

  LibraryData data;

  @override
  Future<LibraryData> load() async => data;

  @override
  Future<void> save(LibraryData data) async {
    this.data = data;
  }
}

class MemoryAiSettingsStore implements AiSettingsStore {
  MemoryAiSettingsStore(this.value) {
    if (value.model.isNotEmpty || value.apiKey.isNotEmpty) {
      catalog = AiProviderCatalog(
        profiles: [
          AiProviderProfile(
            id: 'initial',
            name: '原有配置',
            baseUrl: value.baseUrl,
            model: value.model,
            apiKey: value.apiKey,
          ),
        ],
        activeId: 'initial',
      );
    }
    if ([
      value.polishPrompt,
      value.continueWritingPrompt,
      value.rewritePrompt,
      value.customPrompt,
    ].any((prompt) => prompt.isNotEmpty)) {
      promptCatalog = AiPromptCatalog(
        customTemplates: [
          AiPromptTemplate(
            id: 'legacy-prompt',
            name: '原有提示词',
            polishPrompt: value.polishPrompt,
            continueWritingPrompt: value.continueWritingPrompt,
            rewritePrompt: value.rewritePrompt,
            customPrompt: value.customPrompt,
          ),
        ],
        defaultTemplateId: 'legacy-prompt',
      );
    }
  }

  AiConfiguration value;
  AiProviderCatalog catalog = const AiProviderCatalog();
  AiPromptCatalog promptCatalog = const AiPromptCatalog();
  AiOperationPromptCatalog? operationCatalog;

  @override
  Future<AiConfiguration> load() async => value;

  @override
  Future<void> save(AiConfiguration value) async {
    final current = promptCatalog.defaultTemplate;
    final id = current.isBuiltin ? 'custom-default' : current.id;
    await savePromptCatalog(
      AiPromptCatalog(
        customTemplates: [
          for (final template in promptCatalog.customTemplates)
            if (template.id == id)
              AiPromptTemplate(
                id: id,
                name: current.name,
                polishPrompt: value.polishPrompt,
                continueWritingPrompt: value.continueWritingPrompt,
                rewritePrompt: value.rewritePrompt,
                customPrompt: value.customPrompt,
              )
            else
              template,
          if (current.isBuiltin)
            AiPromptTemplate(
              id: id,
              name: '自定义提示词',
              polishPrompt: value.polishPrompt,
              continueWritingPrompt: value.continueWritingPrompt,
              rewritePrompt: value.rewritePrompt,
              customPrompt: value.customPrompt,
            ),
        ],
        defaultTemplateId: id,
      ),
    );
  }

  @override
  Future<AiProviderCatalog> loadProviders() async => catalog;

  @override
  Future<void> saveProviders(AiProviderCatalog catalog) async {
    this.catalog = catalog;
    final active = catalog.activeProfile;
    value = value.copyWith(
      baseUrl: active?.baseUrl ?? const AiConfiguration().baseUrl,
      model: active?.model ?? '',
      apiKey: active?.apiKey ?? '',
    );
  }

  @override
  Future<AiPromptCatalog> loadPromptCatalog() async => promptCatalog;

  @override
  Future<void> savePromptCatalog(AiPromptCatalog catalog) async {
    promptCatalog = catalog;
    final template = catalog.defaultTemplate;
    value = value.copyWith(
      polishPrompt: template.isBuiltin && template.id == 'builtin-default'
          ? ''
          : template.promptFor(AiTextAction.polish),
      continueWritingPrompt:
          template.isBuiltin && template.id == 'builtin-default'
          ? ''
          : template.promptFor(AiTextAction.continueWriting),
      rewritePrompt: template.isBuiltin && template.id == 'builtin-default'
          ? ''
          : template.promptFor(AiTextAction.rewrite),
      customPrompt: template.isBuiltin && template.id == 'builtin-default'
          ? ''
          : template.promptFor(AiTextAction.custom),
    );
  }

  @override
  Future<AiOperationPromptCatalog> loadOperationPromptCatalog() async {
    if (operationCatalog != null) return operationCatalog!;
    final migrated = <AiOperationPrompt>[];
    final defaults = <String, String>{};
    for (final template in promptCatalog.templates) {
      for (final action in AiTextAction.values) {
        final content = switch (action) {
          AiTextAction.polish => template.polishPrompt,
          AiTextAction.continueWriting => template.continueWritingPrompt,
          AiTextAction.rewrite => template.rewritePrompt,
          AiTextAction.custom => template.customPrompt,
        };
        if (content.isEmpty) continue;
        final id = 'migrated-${template.id}-${action.name}';
        migrated.add(
          AiOperationPrompt(
            id: id,
            name: '${template.name} · ${aiActionLabel(action)}',
            action: action,
            content: content,
          ),
        );
        if (template.id == promptCatalog.defaultTemplateId) {
          defaults[action.name] = id;
        }
      }
    }
    return AiOperationPromptCatalog(
      customPrompts: migrated,
      defaultIds: defaults,
    );
  }

  @override
  Future<void> saveOperationPromptCatalog(
    AiOperationPromptCatalog catalog,
  ) async {
    operationCatalog = catalog;
  }
}

class FakeAiTransport implements AiTransport {
  int calls = 0;
  String? sentText;
  String? sentModel;
  String? sentPrompt;

  @override
  Future<Map<String, dynamic>> post(
    Uri uri, {
    required String apiKey,
    required Map<String, dynamic> body,
  }) async {
    calls++;
    sentText = ((body['messages'] as List).last as Map)['content'] as String;
    sentModel = body['model'] as String?;
    sentPrompt =
        ((body['messages'] as List).first as Map)['content'] as String?;
    return {
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {'content': '润色后的句子'},
        },
      ],
    };
  }
}

class MemoryAiHistoryStore extends AiHistoryStore {
  AiGenerationHistory value = const AiGenerationHistory();

  @override
  Future<AiGenerationHistory> load() async => value;

  @override
  Future<void> save(AiGenerationHistory value) async {
    this.value = value;
  }
}

void main() {
  test('中英文混排字数统计', () {
    expect(countWords('雨落在 old city 7。'), 6);
  });

  testWidgets('首次进入以创建作品为主操作且不要求昵称', (tester) async {
    final data = LibraryData.empty();
    final controller = AppController(store: MemoryStore(data), data: data);

    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('从一部作品开始'), findsOneWidget);
    expect(find.text('创建作品'), findsOneWidget);
    expect(find.text('打开示例作品'), findsOneWidget);
    expect(find.textContaining('作者名'), findsNothing);
    expect(data.profile.authorName, '未命名');
  });

  testWidgets('从书架打开作品保留页面切换动画', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('雾灯来信').last);
    await tester.pump();
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.text('章节目录'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('我的书架'), findsNothing);
    expect(find.text('章节目录'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('伏笔与灵感可确认删除，取消不删除', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.timeline);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final clueId = controller.activeBook!.clues.first.id;
    final noteId = controller.activeBook!.notes.first.id;
    await tester.tap(find.text('伏笔').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('delete-clue-$clueId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(
      controller.activeBook!.clues.any((item) => item.id == clueId),
      isTrue,
    );
    await tester.tap(find.byKey(ValueKey('delete-clue-$clueId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(
      controller.activeBook!.clues.any((item) => item.id == clueId),
      isFalse,
    );

    await tester.tap(find.text('灵感').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('delete-note-$noteId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(
      controller.activeBook!.notes.any((item) => item.id == noteId),
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('正文选区可创建标注并从列表定位', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final body = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!;
    body.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    final editorFinder = find.byType(EditableText).last;
    final bodyField = tester.widget<TextField>(find.byType(TextField).last);
    final selectionToolbar = bodyField.contextMenuBuilder!(
      tester.element(editorFinder),
      tester.state<EditableTextState>(editorFinder),
    ) as AdaptiveTextSelectionToolbar;
    expect(
      selectionToolbar.buttonItems!.any((item) => item.label == '添加标注'),
      isTrue,
    );
    expect(
      MaterialLocalizations.of(tester.element(editorFinder)).copyButtonLabel,
      '复制',
    );
    await tester.tap(find.byKey(const ValueKey('add-chapter-marker')));
    await tester.pumpAndSettle();
    expect(find.text('添加正文标注'), findsOneWidget);
    await tester.tap(find.text('保存标注'));
    await tester.pumpAndSettle();
    expect(controller.activeChapter!.markers, hasLength(1));
    expect(controller.activeChapter!.markers.single.quote, '入秋后的');

    await tester.tapAt(tester.getTopLeft(editorFinder) + const Offset(8, 12));
    await tester.pumpAndSettle();
    expect(find.text('正文标注 · 待修改'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-chapter-markers')));
    await tester.pumpAndSettle();
    expect(find.textContaining('待修改 · 入秋后的'), findsOneWidget);
    await tester.tap(find.textContaining('待修改 · 入秋后的'));
    await tester.pumpAndSettle();
    expect(body.selection, const TextSelection(baseOffset: 0, extentOffset: 4));
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('正文可以应用 Markdown 格式并切换预览', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final body = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!;
    body.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.tap(find.byKey(const ValueKey('markdown-format-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加粗'));
    await tester.pumpAndSettle();
    expect(controller.activeChapter!.body, startsWith('**入秋后的**'));

    await tester.tap(find.byKey(const ValueKey('markdown-preview-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('markdown-preview')), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('markdown-preview-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('Markdown 预览把图片放在上下正文之间', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temporary = Directory.systemTemp.createTempSync('yejian-preview-');
    addTearDown(() => temporary.delete(recursive: true));
    final image = File('${temporary.path}${Platform.pathSeparator}scene.png');
    image.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
      ),
    );
    final data = LibraryData.seeded(profileSetupComplete: true);
    final chapter = data.books.first.chapters.first;
    chapter.body = '上文\n\n![场景](yejian-image:image-1)\n\n下文';
    chapter.images.add(
      ChapterImage(id: 'image-1', path: image.path, alt: '场景'),
    );
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('markdown-preview-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('上文'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('下文'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('段落菜单可切换首行缩进与行距', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final body = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!;
    body.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(find.byTooltip('段落设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换首行缩进 · 长按选择段落'));
    await tester.pumpAndSettle();
    expect(body.text, startsWith('　　入秋后'));

    await tester.tap(find.byTooltip('段落设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示段落标记'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paragraph-number-1')), findsOneWidget);

    await tester.tap(find.byTooltip('段落设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('行距 · 1.4 倍'));
    await tester.pumpAndSettle();
    expect(find.text('行距'), findsOneWidget);
    await tester.tap(find.text('1.6 倍'));
    await tester.pumpAndSettle();
    expect(controller.data.settings.lineHeight, 1.6);

    await tester.tap(find.byTooltip('段落设置'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('切换首行缩进 · 长按选择段落'));
    await tester.pumpAndSettle();
    expect(find.text('选择缩进段落'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('段落标记不挤压正文，换行和缩进后仍跟随段首', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final editor = find.byType(TextField).last;
    final body = tester.widget<TextField>(editor).controller!;
    body.text = '第一段\n第二段\n第三段';
    await tester.pumpAndSettle();
    final before = tester.getRect(editor);

    await tester.tap(find.byTooltip('段落设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示段落标记'));
    await tester.pumpAndSettle();
    expect(tester.getRect(editor), before);
    final number1 = find.byKey(const ValueKey('paragraph-number-1'));
    final number2 = find.byKey(const ValueKey('paragraph-number-2'));
    final number3 = find.byKey(const ValueKey('paragraph-number-3'));
    expect(number1, findsOneWidget);
    expect(number2, findsOneWidget);
    expect(number3, findsOneWidget);
    expect(
      tester.getTopLeft(number2).dy,
      greaterThan(tester.getTopLeft(number1).dy),
    );
    expect(
      tester.getTopLeft(number3).dy,
      greaterThan(tester.getTopLeft(number2).dy),
    );

    body.text = '　　第一段\n　　第二段\n　　第三段';
    await tester.pumpAndSettle();
    expect(tester.getRect(editor), before);
    expect(
      tester.getTopLeft(number2).dy,
      greaterThan(tester.getTopLeft(number1).dy),
    );
    expect(
      tester.getTopLeft(number3).dy,
      greaterThan(tester.getTopLeft(number2).dy),
    );
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('移动端全局书架使用书架与设置双项导航', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);

    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsWidgets);
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.byKey(const ValueKey('floating-app-navigation')),
      findsOneWidget,
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
      isNull,
    );
    expect(find.byKey(const ValueKey('app-nav-bookshelf')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-nav-settings')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('app-nav-capsule'))).width,
      lessThanOrEqualTo(196),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app-nav-capsule'))).height,
      60,
    );
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('app-nav-capsule'))).dy,
      lessThanOrEqualTo(915 - 24),
    );
    final bookshelfItem = find.byKey(const ValueKey('app-nav-bookshelf'));
    expect(
      tester
          .getCenter(
            find.descendant(
              of: bookshelfItem,
              matching: find.byIcon(Icons.auto_stories_rounded),
            ),
          )
          .dy,
      lessThan(
        tester
            .getCenter(
              find.descendant(of: bookshelfItem, matching: find.text('书架')),
            )
            .dy,
      ),
    );
    expect(find.text('雾灯来信'), findsWidgets);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

    await tester.tap(find.byKey(const ValueKey('app-nav-settings')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedAlign>(
            find.byKey(const ValueKey('app-nav-indicator')),
          )
          .alignment,
      Alignment.centerRight,
    );
    expect(controller.page, WorkspacePage.settings);
    expect(find.text('个人信息'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-author-card')), findsOneWidget);
    expect(find.text('作者资料'), findsNothing);
    expect(find.textContaining('累计字数'), findsNothing);
    expect(find.text('应用设置'), findsOneWidget);
    expect(find.text('关于应用'), findsOneWidget);
    expect(find.text('显示模式、配色、字号与字体'), findsNothing);
    expect(find.text('版本、许可与数据说明'), findsNothing);
    expect(find.text('项目'), findsNothing);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('工程文件入口区分单书 .sns 与多书 .snss', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-nav-settings')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('export-library-project')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('import-project-archive')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('app-nav-bookshelf')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出').last);
    await tester.pumpAndSettle();
    expect(find.text('单书工程 .sns'), findsOneWidget);
    expect(find.text('保存 .sns'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('悬浮底栏上滑收起并在下滑时显示', (tester) async {
    tester.view.physicalSize = const Size(412, 360);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 20);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-nav-settings')));
    await tester.pumpAndSettle();

    final motion = find.byKey(const ValueKey('floating-app-navigation-motion'));
    expect(tester.widget<AnimatedSlide>(motion).offset, Offset.zero);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(motion).offset, const Offset(0, 1.45));

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(motion).offset, Offset.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('作品首页可直接新建分卷', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建分卷'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('新建分卷')),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      '第三卷',
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('创建')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));

    expect(controller.activeBook!.volumes.last.title, '第三卷');
    expect(find.text('第三卷'), findsOneWidget);
  });

  testWidgets('移动端写作页可以切换章节', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    expect(find.text('章节目录'), findsOneWidget);
    expect(find.text('消失的第七封信'), findsOneWidget);

    await tester.tap(find.text('继续写作'));
    await tester.pumpAndSettle();
    expect(find.text('目录'), findsOneWidget);

    await tester.tap(find.text('目录'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('章节目录'), findsOneWidget);
    expect(find.text('不肯熄灭的灯'), findsOneWidget);
    await tester.tap(find.text('不肯熄灭的灯'));
    await tester.pumpAndSettle();
    expect(controller.activeChapter?.title, '不肯熄灭的灯');
    expect(tester.takeException(), isNull);
  });

  testWidgets('书内导航包含写作设定情节导出并支持系统返回', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    expect(find.text('章节目录'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.text('写作').last);
    await tester.pumpAndSettle();
    final capsule = find.byKey(const ValueKey('book-nav-capsule'));
    expect(capsule, findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
      isNull,
    );
    expect(tester.getSize(capsule).width, lessThanOrEqualTo(280));
    expect(tester.getSize(capsule).height, 60);
    expect(tester.getBottomLeft(capsule).dy, lessThanOrEqualTo(915 - 24));
    for (final key in [
      'book-nav-writing',
      'book-nav-settings',
      'book-nav-story',
      'book-nav-export',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    await tester.tap(find.text('设定').last);
    await tester.pumpAndSettle();
    expect(controller.page, WorkspacePage.characters);
    final indicator = tester.widget<AnimatedPositioned>(
      find.byKey(const ValueKey('book-nav-indicator')),
    );
    expect(indicator.left, greaterThan(0));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.page, WorkspacePage.bookOverview);
    expect(find.text('章节目录'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.page, WorkspacePage.home);
    expect(find.text('我的书架'), findsOneWidget);
  });

  testWidgets('从正文右上角进入设置，返回后保留章节与滚动位置', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final chapter = data.books.first.chapters.first;
    chapter.body = List.generate(
      90,
      (index) => '第 $index 段：这是用于验证返回位置的正文。',
    ).join('\n');
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.openChapter(chapter.id);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final body = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.scrollController != null,
    );
    final scroll = tester.widget<TextField>(body).scrollController!;
    expect(scroll.hasClients, isTrue);
    scroll.jumpTo(360);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(300));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(controller.page, WorkspacePage.settings);
    expect(controller.canGoBack, isTrue);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(controller.page, WorkspacePage.writing);
    expect(controller.activeChapter?.id, chapter.id);
    expect(
      tester.widget<TextField>(body).scrollController!.offset,
      greaterThan(300),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('设定页打开设置再返回仍停留在世界观标签', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.characters);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界观').first);
    await tester.pumpAndSettle();
    expect(find.text('新建世界观条目'), findsOneWidget);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(controller.page, WorkspacePage.characters);
    expect(find.text('新建世界观条目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书内胶囊随纵向滚动收起和出现', (tester) async {
    tester.view.physicalSize = const Size(412, 500);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 20);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    controller.navigateBook(WorkspacePage.characters);
    await tester.pumpAndSettle();

    final motion = find.byKey(
      const ValueKey('floating-book-navigation-motion'),
    );
    expect(tester.widget<AnimatedSlide>(motion).offset, Offset.zero);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(motion).offset, const Offset(0, 1.45));

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(motion).offset, Offset.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('角色世界观和情节工具限定在当前作品内', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('设定').last);
    await tester.pumpAndSettle();
    expect(find.text('人物与世界'), findsOneWidget);
    expect(find.text('共用基础模板，写下各自的不同。'), findsNothing);
    expect(find.text('角色卡'), findsOneWidget);
    expect(find.text('世界观'), findsOneWidget);
    expect(find.text('12 项共用基础字段'), findsOneWidget);
    expect(find.text('管理模板'), findsOneWidget);

    final settingsTitle = find.text('雾灯来信 · 设定');
    final settingsTitleCenter = tester.getCenter(settingsTitle);
    expect(settingsTitleCenter.dx, closeTo(206, 2));

    await tester.tap(find.text('情节').last);
    await tester.pumpAndSettle();
    expect(find.text('故事结构'), findsOneWidget);
    expect(find.text('一套事件，三种看故事的方式。'), findsNothing);
    expect(find.text('结构'), findsOneWidget);
    expect(find.text('大纲'), findsOneWidget);
    expect(find.text('伏笔'), findsOneWidget);
    expect(find.text('灵感'), findsOneWidget);
    expect(find.text('时间轴'), findsOneWidget);
    expect(find.text('思维导图'), findsOneWidget);
    expect(find.text('流程图'), findsOneWidget);
    expect(find.text('管理时间线 · 2 条'), findsOneWidget);
    expect(find.text('按总时间层级 ↑，同层按同时间排序 ↑'), findsOneWidget);

    final storyTitle = find.text('雾灯来信 · 情节');
    final storyTitleCenter = tester.getCenter(storyTitle);
    expect(storyTitleCenter.dx, closeTo(206, 2));
    expect(storyTitleCenter.dy, closeTo(settingsTitleCenter.dy, 1));

    await tester.tap(find.text('大纲'));
    await tester.pumpAndSettle();
    expect(find.text('消失的第七封信'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏长角色名与事件表单不越界', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    data.books.first.roles.first.name = '江边旧城档案馆特别调查组的记录员';
    data.books.first.tracks.first.name = '很长很长的故事主时间线名称';
    final controller = AppController(store: MemoryStore(data), data: data);
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.timeline);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建事件').first);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(tester.getRect(dialog).right, lessThanOrEqualTo(320));
    final chip = find.byKey(const ValueKey('event-role-role-1'));
    await tester.ensureVisible(chip);
    expect(
      tester.getRect(chip).right,
      lessThanOrEqualTo(tester.getRect(dialog).right - 8),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('新增事件直接列出已创建角色并保存稳定引用', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('情节').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建事件').first);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('event-role-role-1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('event-role-role-2')),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).first,
      '角色引用测试',
    );
    await tester.enterText(
      find.byKey(const ValueKey('event-story-date')),
      '秋十日',
    );
    await tester.enterText(
      find.byKey(const ValueKey('event-time-level')),
      '10',
    );
    await tester.enterText(
      find.byKey(const ValueKey('event-same-time-order')),
      '2',
    );
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('event-role-role-1')),
      ),
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('保存')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));

    expect(controller.activeBook!.events.last.roleIds, ['role-1']);
    expect(controller.activeBook!.events.last.persons, '林照');
    expect(controller.activeBook!.events.last.storyDate, '秋十日');
    expect(controller.activeBook!.events.last.timeLevel, 10);
    expect(controller.activeBook!.events.last.sameTimeOrder, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('角色卡可点击进入详情并保存完整编辑', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设定').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('林照').first);
    await tester.pumpAndSettle();
    expect(find.text('概览'), findsOneWidget);
    expect(find.byTooltip('编辑角色'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑角色'));
    await tester.pumpAndSettle();
    expect(find.text('编辑角色'), findsOneWidget);
    final age = find.byKey(const ValueKey('field-年龄'));
    await tester.enterText(age, '23');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('23'), findsOneWidget);
    expect(controller.activeBook!.roles.first.age, '23');
    expect(tester.takeException(), isNull);
  });

  testWidgets('角色详情可查看结构化人物关系图并打开关联角色', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    data.books.first.roles.first.relations.add(
      RoleRelation(
        id: 'test-relation',
        targetRoleId: 'role-2',
        name: '旧友',
        direction: '双向',
      ),
    );
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设定').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('林照').first);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-role-relationship-map')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('open-role-relationship-map')));
    await tester.pumpAndSettle();
    expect(find.text('林照 · 人物关系'), findsOneWidget);
    final relatedNode = find.byKey(
      const ValueKey('relationship-node-test-relation'),
    );
    expect(relatedNode, findsOneWidget);
    expect(tester.getRect(relatedNode).right, lessThan(412));
    expect(find.text('旧友'), findsOneWidget);
    await tester.tap(relatedNode);
    await tester.pumpAndSettle();
    expect(find.text('江迟'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关系较多时当前角色仍位于关系图可视区域', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    for (var index = 0; index < 30; index++) {
      data.books.first.roles.first.relations.add(
        RoleRelation(
          id: 'relation-$index',
          targetRoleId: 'role-2',
          name: '关系 $index',
        ),
      );
    }
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设定').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('林照').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-role-relationship-map')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('open-role-relationship-map')));
    await tester.pumpAndSettle();
    final root = tester.getRect(
      find.byKey(const ValueKey('relationship-root-node')),
    );
    expect(root.center.dy, greaterThan(100));
    expect(root.center.dy, lessThan(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('角色编辑可新增关系并安全关闭输入对话框', (tester) async {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final roles = data.books.first.roles;
    await tester.pumpWidget(
      MaterialApp(
        home: RoleEditPage(
          role: roles.first,
          allRoles: roles,
          baseFields: data.books.first.roleBaseFields,
          sharedFields: data.books.first.roleFields,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('能力、弱点与人物关系'));
    await tester.tap(find.text('能力、弱点与人物关系'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('新增').first,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('新增').first);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).first,
      '朋友',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dialog, matching: find.text('添加')));
    await tester.pumpAndSettle();
    expect(find.textContaining('朋友 · 江迟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('世界观自定义长文本可输入换行', (tester) async {
    final field = CustomFieldDefinition(
      id: 'world-longtext-test',
      name: '历史沿革',
      type: 'longText',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorldEditPage(
          world: WorldCard(
            id: 'world-test',
            title: '测试地点',
            customFields: [field],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('world-longtext-test')),
      matching: find.byType(TextFormField),
    );
    await tester.scrollUntilVisible(
      input,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final textField = tester.widget<TextField>(
      find.descendant(of: input, matching: find.byType(TextField)),
    );
    expect(textField.keyboardType, TextInputType.multiline);
    expect(textField.textInputAction, TextInputAction.newline);
    await tester.enterText(input, '第一年\n第二年');
    expect(textField.maxLines, greaterThan(1));
    expect(find.text('第一年\n第二年'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建角色可打开空白表单并保存', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设定').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建角色卡'));
    await tester.pumpAndSettle();
    expect(find.text('新建角色'), findsOneWidget);
    expect(find.text('未命名角色'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const ValueKey('field-姓名 *')), '苏晚');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('苏晚'), findsOneWidget);
    expect(
      controller.activeBook!.roles.any((role) => role.name == '苏晚'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('多张角色卡时新建入口始终可见，连续创建不覆盖已有角色', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    final originalIds = controller.activeBook!.roles
        .map((role) => role.id)
        .toSet();
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设定').last);
    await tester.pumpAndSettle();

    for (final name in ['苏晚', '顾舟']) {
      final create = find.byKey(const ValueKey('create-setting-entry'));
      expect(create.hitTestable(), findsOneWidget);
      await tester.tap(create);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-姓名 *')), name);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        originalIds.difference(
          controller.activeBook!.roles.map((role) => role.id).toSet(),
        ),
        isEmpty,
      );
    }

    expect(controller.activeBook!.roles.length, 4);
    expect(
      find.byKey(const ValueKey('create-setting-entry')).hitTestable(),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机作品目录支持长按多选管理', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();

    final chapter = find.text('消失的第七封信');
    await tester.scrollUntilVisible(chapter, 300);
    await tester.longPress(chapter);
    await tester.pumpAndSettle();

    expect(find.textContaining('已选 0 卷、1 章'), findsOneWidget);
    expect(find.text('删除所选'), findsOneWidget);
    expect(find.text('取消多选'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设定模板可停用基础字段并直接新增自定义字段', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设定').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理模板'));
    await tester.pumpAndSettle();

    final aliasTile = find.ancestor(
      of: find.text('别名'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: aliasTile, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(
      controller.activeBook!.roleBaseFields
          .firstWhere((field) => field.id == 'alias')
          .enabled,
      isFalse,
    );

    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增字段'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '阵营立场');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      controller.activeBook!.roleFields.any((field) => field.name == '阵营立场'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('显示模式与配色独立，可切换夜间模式', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-app-settings')));
    await tester.pumpAndSettle();

    expect(find.text('显示模式'), findsOneWidget);
    expect(find.text('配色'), findsOneWidget);
    await tester.tap(find.text('夜间'));
    await tester.pumpAndSettle();
    expect(controller.data.settings.appearanceMode, 'dark');
    expect(tester.takeException(), isNull);
  });

  testWidgets('关于应用显示版本许可与数据说明入口', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('app-nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-about-app')));
    await tester.pumpAndSettle();

    expect(controller.page, WorkspacePage.about);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(.+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(
      find.text(
        '${version.group(1)!.replaceFirst('-ai-dev.', '.ai-dev.')} (${version.group(2)})',
      ),
      findsOneWidget,
    );
    expect(find.text('GPL-2.0-only'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('问题反馈'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-github-issues')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-microsoft-forms')), findsOneWidget);
    expect(
      find.text('https://github.com/silent07137/yejian-novel-studio'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('open-project-repository')),
      findsOneWidget,
    );
    expect(find.text('数据与隐私'), findsOneWidget);
    expect(find.text('第三方开源许可'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-nav-settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('问题反馈分别打开 GitHub Issues 和 Microsoft Forms', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AboutPage(
            openLink: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final issues = find.byKey(const ValueKey('open-github-issues'));
    await tester.ensureVisible(issues);
    await tester.pumpAndSettle();
    await tester.tap(issues);
    await tester.pumpAndSettle();

    final forms = find.byKey(const ValueKey('open-microsoft-forms'));
    await tester.ensureVisible(forms);
    await tester.pumpAndSettle();
    await tester.tap(forms);
    await tester.pumpAndSettle();

    expect(opened.map((uri) => uri.toString()), [
      'https://github.com/silent07137/yejian-novel-studio/issues',
      'https://forms.cloud.microsoft/r/JJdHgxPRdS',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('思维导图按主题分支排布并支持折叠', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('情节').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('思维导图'));
    await tester.pumpAndSettle();

    expect(find.text('全书构思'), findsOneWidget);
    expect(find.text('来信之谜'), findsOneWidget);
    expect(find.text('第七封信出现'), findsOneWidget);
    expect(find.text('适配'), findsOneWidget);

    await tester.tap(find.text('来信之谜'));
    await tester.pumpAndSettle();
    expect(find.text('第七封信出现'), findsNothing);
    expect(find.text('林照的选择'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('流程图显示完整的合流与分支关系', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: MemoryStore(data), data: data);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雾灯来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('情节').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('流程图'));
    await tester.pumpAndSettle();

    final branchA = find.text('决定寻找收信人');
    final branchB = find.text('带着信离开旧城');
    expect(branchA, findsOneWidget);
    expect(branchB, findsOneWidget);
    expect(
      tester.getCenter(branchA).dy,
      closeTo(tester.getCenter(branchB).dy, 1),
    );
    expect(
      (tester.getCenter(branchA).dx - tester.getCenter(branchB).dx).abs(),
      greaterThan(80),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 设置仅保存到独立配置存储', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final aiSettings = MemoryAiSettingsStore(
      const AiConfiguration(polishPrompt: '保留的润色提示词'),
    );
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: aiSettings,
      aiHistoryStore: MemoryAiHistoryStore(),
    )..navigate(WorkspacePage.appSettings);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('open-ai-settings'));
    expect(find.byKey(const ValueKey('open-ai-prompts')), findsNothing);
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('API 配置'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-ai-provider')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-provider-name')),
      '测试服务',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-model')),
      'test-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-api-key')),
      'private-key',
    );
    await tester.tap(find.byKey(const ValueKey('save-ai-settings')));
    await tester.pumpAndSettle();

    expect(aiSettings.value.model, 'test-model');
    expect(aiSettings.value.apiKey, 'private-key');
    expect(aiSettings.value.polishPrompt, '保留的润色提示词');
    expect(aiSettings.catalog.profiles.single.name, '测试服务');
    expect(data.toJson().toString(), isNot(contains('private-key')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 文风模板可自定义，内置模板可编辑与删除', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final aiSettings = MemoryAiSettingsStore(
      const AiConfiguration(model: 'test-model', apiKey: 'private-key'),
    );
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: aiSettings,
      aiHistoryStore: MemoryAiHistoryStore(),
    )..navigate(WorkspacePage.appSettings);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('open-ai-settings'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final addTemplate = find.byKey(const ValueKey('add-ai-template'));
    await tester.ensureVisible(addTemplate);
    await tester.tap(addTemplate);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-template-name')),
      '冷静叙事',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-template-style')),
      '保持冷静，减少形容。',
    );
    await tester.tap(find.byKey(const ValueKey('save-ai-template')));
    await tester.pumpAndSettle();
    expect(aiSettings.promptCatalog.customTemplates.single.name, '冷静叙事');
    expect(
      aiSettings.promptCatalog.defaultTemplate.promptFor(AiTextAction.polish),
      contains('保持冷静，减少形容。'),
    );
    expect(aiSettings.value.model, 'test-model');
    expect(aiSettings.value.apiKey, 'private-key');
    expect(data.toJson().toString(), isNot(contains('保持冷静')));

    final builtin = find.byKey(const ValueKey('ai-template-builtin-delicate'));
    await tester.ensureVisible(builtin);
    await tester.tap(
      find.descendant(
        of: builtin,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-template-style')),
      '编辑后的内置文风',
    );
    await tester.tap(find.byKey(const ValueKey('save-ai-template')));
    await tester.pumpAndSettle();
    expect(
      aiSettings.promptCatalog.builtinOverrides.single.styleInstruction,
      '编辑后的内置文风',
    );

    await tester.ensureVisible(builtin);
    await tester.tap(
      find.descendant(
        of: builtin,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(
      aiSettings.promptCatalog.hiddenBuiltinIds,
      contains('builtin-delicate'),
    );
    expect(
      aiSettings.promptCatalog.templates.map((item) => item.id),
      isNot(contains('builtin-delicate')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('操作提示词可独立新增与编辑内置内容', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final settings = MemoryAiSettingsStore(const AiConfiguration());
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: settings,
      aiHistoryStore: MemoryAiHistoryStore(),
    )..navigate(WorkspacePage.aiSettings);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai-operation-builtin-operation-polish')),
      findsOneWidget,
    );
    final add = find.byKey(const ValueKey('add-ai-operation'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-operation-name')),
      '简洁润色',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-operation-content')),
      '只润色句式，不改变事实。',
    );
    await tester.tap(find.byKey(const ValueKey('save-ai-operation')));
    await tester.pumpAndSettle();
    expect(settings.operationCatalog!.customPrompts.single.name, '简洁润色');
    expect(
      settings.operationCatalog!.defaultFor(AiTextAction.polish).content,
      '只润色句式，不改变事实。',
    );

    final builtin = find.byKey(
      const ValueKey('ai-operation-builtin-operation-polish'),
    );
    await tester.ensureVisible(builtin);
    await tester.tap(
      find.descendant(
        of: builtin,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-operation-content')),
      '修改后的内置润色词',
    );
    await tester.tap(find.byKey(const ValueKey('save-ai-operation')));
    await tester.pumpAndSettle();
    expect(
      settings.operationCatalog!.builtinOverrides.single.content,
      '修改后的内置润色词',
    );
    expect(data.toJson().toString(), isNot(contains('修改后的内置润色词')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 设置显示累计次数、历史结果与保留条数', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final history = MemoryAiHistoryStore();
    await history.append(
      AiGenerationRecord(
        id: 'one',
        createdAt: DateTime.utc(2026, 9, 27),
        bookTitle: '测试书',
        chapterTitle: '第一章',
        action: AiTextAction.polish,
        providerName: '主服务',
        model: 'test-model',
        templateName: '默认',
        result: '这是一条生成结果',
      ),
    );
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: MemoryAiSettingsStore(const AiConfiguration()),
      aiHistoryStore: history,
    )..navigate(WorkspacePage.aiSettings);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('累计生成次数'), findsNothing);
    final entry = find.byKey(const ValueKey('open-ai-history'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(controller.page, WorkspacePage.aiHistory);
    final retention = find.byKey(const ValueKey('ai-history-retention'));
    await tester.ensureVisible(retention);
    expect(find.text('累计生成次数'), findsOneWidget);
    expect(find.text('1 次'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-history-one')));
    await tester.pumpAndSettle();
    expect(find.text('这是一条生成结果'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(retention);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 条').last);
    await tester.pumpAndSettle();
    expect(history.value.retentionLimit, 20);
    expect(history.value.totalCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 助手可保存多组 API，切换和删除后使用正确配置', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final aiSettings = MemoryAiSettingsStore(
      const AiConfiguration(
        baseUrl: 'https://first.example/v1',
        model: 'first-model',
        apiKey: 'first-key',
        polishPrompt: '共同使用的提示词',
      ),
    );
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: aiSettings,
      aiHistoryStore: MemoryAiHistoryStore(),
    )..navigate(WorkspacePage.aiSettings);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-provider-initial')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-ai-provider')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-provider-name')),
      '备用服务',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-base-url')),
      'https://second.example/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-model')),
      'second-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-api-key')),
      'second-key',
    );
    await tester.tap(find.byKey(const ValueKey('save-ai-settings')));
    await tester.pumpAndSettle();

    expect(aiSettings.catalog.profiles.length, 2);
    expect((await aiSettings.load()).apiKey, 'second-key');
    expect((await aiSettings.load()).polishPrompt, '共同使用的提示词');
    expect(data.toJson().toString(), isNot(contains('second-key')));

    await tester.tap(find.byKey(const ValueKey('ai-provider-initial')));
    await tester.pumpAndSettle();
    expect((await aiSettings.load()).apiKey, 'first-key');
    expect((await aiSettings.load()).model, 'first-model');
    expect((await aiSettings.load()).polishPrompt, '共同使用的提示词');

    final secondId = aiSettings.catalog.profiles.last.id;
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('ai-provider-$secondId')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(aiSettings.catalog.profiles.length, 1);
    expect((await aiSettings.load()).apiKey, 'first-key');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 润色取消不发送，确认后预览再替换选区', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final aiSettings = MemoryAiSettingsStore(
      const AiConfiguration(
        baseUrl: 'https://example.com/v1',
        model: 'test-model',
        apiKey: 'private-key',
      ),
    );
    final transport = FakeAiTransport();
    final historyStore = MemoryAiHistoryStore();
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: aiSettings,
      aiHistoryStore: historyStore,
      aiTextService: AiTextService(transport: transport),
    );
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final body = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!;
    final original = body.text;
    body.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    final editor = find.byType(EditableText).last;
    final field = tester.widget<TextField>(find.byType(TextField).last);
    final toolbar = field.contextMenuBuilder!(
      tester.element(editor),
      tester.state<EditableTextState>(editor),
    ) as AdaptiveTextSelectionToolbar;
    expect(toolbar.buttonItems!.map((item) => item.label), contains('添加标注'));
    expect(
      toolbar.buttonItems!.map((item) => item.label),
      isNot(contains('AI 润色')),
    );
    await tester.tap(find.byKey(const ValueKey('ai-editor-menu')));
    await tester.pumpAndSettle();
    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-scope-selection')), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(transport.calls, 0);
    expect(historyStore.value.totalCount, 0);
    expect(body.text, original);

    body.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.tap(find.byKey(const ValueKey('ai-editor-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认发送'));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    expect(transport.sentText, contains('【作品参考资料】'));
    expect(transport.sentText, contains(original.substring(0, 4)));
    expect(find.text('AI 结果'), findsOneWidget);
    expect(historyStore.value.totalCount, 1);
    expect(historyStore.value.records.single.result, '润色后的句子');
    expect(body.text, original);
    await tester.tap(find.byKey(const ValueKey('apply-ai-result')));
    await tester.pumpAndSettle();
    expect(body.text, startsWith('润色后的句子'));
    expect(field.undoController!.value.canUndo, isTrue);
    field.undoController!.undo();
    await tester.pumpAndSettle();
    expect(body.text, original);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('正文 AI 请求可单次切换模型、文风与提示词，结果记入历史', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final settings = MemoryAiSettingsStore(
      const AiConfiguration(model: 'first-model', apiKey: 'first-key'),
    );
    await settings.saveProviders(
      AiProviderCatalog(
        profiles: [
          ...settings.catalog.profiles,
          const AiProviderProfile(
            id: 'second',
            name: '备用服务',
            baseUrl: 'https://second.example/v1',
            model: 'second-model',
            apiKey: 'second-key',
          ),
        ],
        activeId: 'initial',
      ),
    );
    await settings.saveOperationPromptCatalog(
      const AiOperationPromptCatalog(
        customPrompts: [
          AiOperationPrompt(
            id: 'custom-polish',
            name: '测试润色词',
            action: AiTextAction.polish,
            content: '按测试要求润色',
          ),
        ],
      ),
    );
    final history = MemoryAiHistoryStore();
    final transport = FakeAiTransport();
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: settings,
      aiHistoryStore: history,
      aiTextService: AiTextService(transport: transport),
    );
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-editor-menu')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-model-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用服务 · second-model').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-template-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简洁克制').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-operation-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试润色词').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await tester.pumpAndSettle();

    expect(transport.sentModel, 'second-model');
    expect(transport.sentPrompt, contains('句子凝练'));
    expect(transport.sentPrompt, contains('按测试要求润色'));
    expect(history.value.totalCount, 1);
    expect(history.value.records.single.model, 'second-model');
    expect(history.value.records.single.templateName, '简洁克制');
    expect(settings.catalog.activeId, 'initial');
    expect(settings.promptCatalog.defaultTemplateId, 'builtin-default');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 自定义指令可关闭作品上下文，放弃结果不修改正文', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final transport = FakeAiTransport();
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: MemoryAiSettingsStore(
        const AiConfiguration(model: 'test-model', apiKey: 'private-key'),
      ),
      aiHistoryStore: MemoryAiHistoryStore(),
      aiTextService: AiTextService(transport: transport),
    );
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    final body = field.controller!;
    final original = body.text;
    body.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.tap(find.byKey(const ValueKey('ai-editor-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-custom-instruction')),
      '改成第一人称',
    );
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(find.text('AI 操作失败，请检查服务配置'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-include-context')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('ai-editor-content')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('ai-include-context'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(find.text('附带本书相关资料'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-include-context')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认发送'));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    expect(transport.sentText, contains('【本次指令】\n改成第一人称'));
    expect(transport.sentText, isNot(contains('【作品参考资料】')));
    expect(body.text, original);
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(body.text, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无需框选可从光标续写，并只在确认后插入', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final transport = FakeAiTransport();
    final controller = AppController(
      store: MemoryStore(data),
      data: data,
      aiSettingsStore: MemoryAiSettingsStore(
        const AiConfiguration(model: 'test-model', apiKey: 'private-key'),
      ),
      aiHistoryStore: MemoryAiHistoryStore(),
      aiTextService: AiTextService(transport: transport),
    );
    controller.openBook(data.books.first.id);
    controller.navigateBook(WorkspacePage.writing);
    await tester.pumpWidget(YejianApp(controller: controller));
    await tester.pumpAndSettle();

    final body = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!;
    final original = body.text;
    body.selection = TextSelection.collapsed(offset: original.length);
    await tester.tap(find.byKey(const ValueKey('ai-editor-menu')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('ai-scope-paragraph')))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '续写'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('ai-scope-cursor')))
          .selected,
      isTrue,
    );
    expect(body.text, original);
    expect(transport.calls, 0);
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    expect(body.text, original);
    await tester.tap(find.byKey(const ValueKey('apply-ai-result')));
    await tester.pumpAndSettle();
    expect(body.text, startsWith(original));
    expect(body.text, contains('润色后的句子'));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 900));
  });
}
