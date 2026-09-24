import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/data/local_store.dart';
import 'package:yejian_native/main.dart';
import 'package:yejian_native/models/library_data.dart';
import 'package:yejian_native/state/app_controller.dart';
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
    expect(find.text('项目'), findsNothing);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
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
    expect(find.text('共用基础模板，写下各自的不同。'), findsOneWidget);
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
    expect(find.text('一套事件，三种看故事的方式。'), findsOneWidget);
    expect(find.text('结构'), findsOneWidget);
    expect(find.text('大纲'), findsOneWidget);
    expect(find.text('伏笔'), findsOneWidget);
    expect(find.text('灵感'), findsOneWidget);
    expect(find.text('时间轴'), findsOneWidget);
    expect(find.text('思维导图'), findsOneWidget);
    expect(find.text('流程图'), findsOneWidget);
    expect(find.text('管理时间线 · 2 条'), findsOneWidget);
    expect(find.text('事件排序'), findsOneWidget);
    expect(find.text('故事时间'), findsOneWidget);

    final storyTitle = find.text('雾灯来信 · 情节');
    final storyTitleCenter = tester.getCenter(storyTitle);
    expect(storyTitleCenter.dx, closeTo(206, 2));
    expect(storyTitleCenter.dy, closeTo(settingsTitleCenter.dy, 1));

    await tester.tap(find.text('大纲'));
    await tester.pumpAndSettle();
    expect(find.text('消失的第七封信'), findsOneWidget);
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
      find.text('${version.group(1)} (${version.group(2)})'),
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
}
