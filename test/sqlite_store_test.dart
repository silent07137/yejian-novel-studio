import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yejian_native/data/sqlite_store.dart';
import 'package:yejian_native/models/library_data.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  SqliteStore memoryStore() => SqliteStore(
    databasePath: inMemoryDatabasePath,
    factory: databaseFactoryFfi,
    legacyJsonPath: '${Directory.systemTemp.path}/missing-yejian-library.json',
  );

  test('SQLite 事务保存并完整还原项目关系', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final volume = Volume(id: 'volume-1', title: '第一卷');
    final data = LibraryData(
      profile: WriterProfile(authorName: '未命名', setupComplete: true),
      settings: AppSettings(appearanceMode: 'dark'),
      activeBookId: 'book-1',
      books: [
        Book(
          id: 'book-1',
          title: '离线测试',
          volumes: [volume],
          chapters: [
            Chapter(
              id: 'chapter-1',
              title: '第一章',
              volumeId: volume.id,
              body: '正文不会只存在内存里。',
              markers: [
                ChapterMarker(
                  id: 'marker-1',
                  kind: 'revision',
                  start: 0,
                  end: 2,
                  quote: '正文',
                  note: '这里待改',
                ),
              ],
            ),
          ],
          roles: [
            RoleCard(
              id: 'role-1',
              name: '林照',
              customValues: {'role-field-camp': '书馆'},
              relations: [
                RoleRelation(
                  id: 'relation-1',
                  targetRoleId: 'role-2',
                  name: '搭档',
                ),
              ],
            ),
            RoleCard(id: 'role-2', name: '江迟'),
          ],
          roleFields: [
            CustomFieldDefinition(
              id: 'role-field-camp',
              name: '阵营',
              type: 'singleChoice',
              scope: 'book',
              options: ['书馆', '灯塔'],
            ),
          ],
          roleBaseFields: defaultRoleBaseFields()
            ..firstWhere((field) => field.id == 'alias').enabled = false,
          worlds: [
            WorldCard(
              id: 'world-1',
              title: '灯塔书馆',
              customValues: {'world-field-secret': '仅作者可见'},
            ),
          ],
          worldFields: [
            CustomFieldDefinition(
              id: 'world-field-secret',
              name: '保密等级',
              scope: 'book',
            ),
          ],
          tracks: [StoryTrack(id: 'track-1', name: '主线')],
          events: [
            StoryEvent(
              id: 'event-1',
              title: '相遇',
              storyDate: '秋一日',
              roleIds: ['role-1', 'role-2'],
            ),
          ],
        ),
      ],
    );

    await store.save(data);
    final restored = await store.load();

    expect(restored.books.single.title, '离线测试');
    expect(restored.books.single.chapters.single.markers.single.note, '这里待改');
    expect(restored.books.single.volumes.single.id, 'volume-1');
    expect(restored.books.single.chapters.single.body, '正文不会只存在内存里。');
    expect(restored.books.single.roles.first.name, '林照');
    expect(
      restored.books.single.roles.first.relations.single.targetRoleId,
      'role-2',
    );
    expect(restored.books.single.worlds.single.title, '灯塔书馆');
    expect(restored.books.single.roleFields.single.name, '阵营');
    expect(restored.settings.appearanceMode, 'dark');
    expect(
      restored.books.single.roleBaseFields
          .firstWhere((field) => field.id == 'alias')
          .enabled,
      isFalse,
    );
    expect(
      restored.books.single.roles.first.customValues['role-field-camp'],
      '书馆',
    );
    expect(restored.books.single.worldFields.single.name, '保密等级');
    expect(restored.books.single.events.single.roleIds, ['role-1', 'role-2']);

    data.books.single.title = '离线测试（修订）';
    data.books.single.chapters.single.body = '第二次事务保存。';
    await store.save(data);
    final revised = await store.load();
    expect(revised.books.single.title, '离线测试（修订）');
    expect(revised.books.single.chapters.single.body, '第二次事务保存。');

    data.books.single.roles.addAll([
      RoleCard(id: 'role-3', name: '苏晚'),
      RoleCard(id: 'role-4', name: '顾舟'),
    ]);
    await store.save(data);
    data.books.single.roles[2].description = '填写完整的角色简介';
    await store.save(data);
    final rolesAfterEdit = (await store.load()).books.single.roles;
    expect(rolesAfterEdit.map((role) => role.id).toList(), [
      'role-1',
      'role-2',
      'role-3',
      'role-4',
    ]);
    expect(rolesAfterEdit[2].description, '填写完整的角色简介');
  });

  test('章节修订号阻止旧版本覆盖新正文', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final data = LibraryData.seeded(profileSetupComplete: true);
    await store.save(data);
    final chapterId = data.books.first.chapters.first.id;
    final initialRevision = await store.chapterRevision(chapterId);

    final nextRevision = await store.updateChapterBody(
      chapterId: chapterId,
      body: '新正文',
      expectedRevision: initialRevision!,
    );

    expect(nextRevision, initialRevision + 1);
    await expectLater(
      store.updateChapterBody(
        chapterId: chapterId,
        body: '过期正文',
        expectedRevision: initialRevision,
      ),
      throwsA(isA<RevisionConflict>()),
    );
    expect((await store.load()).books.first.chapters.first.body, '新正文');
    expect((await store.revisions('chapter', chapterId)).length, 2);
  });

  test('保存失败时整个事务回滚', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final volume = Volume(id: 'volume-good', title: '第一卷');
    final invalid = LibraryData(
      profile: WriterProfile(setupComplete: true),
      settings: AppSettings(),
      books: [
        Book(
          id: 'book-invalid',
          title: '不能半保存',
          volumes: [volume],
          chapters: [
            Chapter(
              id: 'chapter-invalid',
              title: '无效章节',
              volumeId: 'volume-does-not-exist',
            ),
          ],
        ),
      ],
    );

    await expectLater(store.save(invalid), throwsA(anything));
    final db = await store.database;
    expect((await db.query('projects')), isEmpty);
    expect((await db.query('app_profile')), isEmpty);
  });

  test('作品删除进入软删除记录并可完整恢复', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final data = LibraryData.seeded(profileSetupComplete: true);
    final projectId = data.books.single.id;
    await store.save(data);

    data.books.clear();
    data.activeBookId = null;
    await store.save(data);
    expect((await store.load()).books, isEmpty);
    expect((await store.deletedItems('projects')).single['id'], projectId);

    await store.restoreProject(projectId);
    final restored = await store.load();
    expect(restored.books.single.id, projectId);
    expect(restored.books.single.chapters, isNotEmpty);
  });

  test('旧 library.json 只迁移一次且保留源文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yejian-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final legacy = File('${directory.path}/library.json');
    await legacy.writeAsString(
      jsonEncode(LibraryData.seeded(profileSetupComplete: true).toJson()),
    );
    final store = SqliteStore(
      databasePath: '${directory.path}/yejian.db',
      factory: databaseFactoryFfi,
      legacyJsonPath: legacy.path,
    );
    addTearDown(store.close);

    expect((await store.load()).books.length, 1);
    expect(await legacy.exists(), isTrue);
    expect((await store.load()).books.length, 1);
    final db = await store.database;
    expect((await db.query('migration_log')).length, 1);
  });
}
