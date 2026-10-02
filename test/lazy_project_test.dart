import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yejian_native/data/sqlite_store.dart';
import 'package:yejian_native/domain/project_archive.dart';
import 'package:yejian_native/models/library_data.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('按需读取章节和模块，保存已加载内容不会擦除未加载正文与设定', () async {
    final folder = await Directory.systemTemp.createTemp('yejian-lazy-');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/library.db';
    final store = SqliteStore(
      databasePath: path,
      factory: databaseFactoryFfi,
      legacyJsonPath: '${folder.path}/missing.json',
      lazyLoad: true,
    );
    final original = LibraryData.seeded(profileSetupComplete: true);
    final book = original.books.first;
    book.chapters[1].markers.add(
      ChapterMarker(
        id: 'unopened-marker',
        kind: 'revision',
        start: 0,
        end: 2,
        quote: book.chapters[1].body.substring(0, 2),
      ),
    );
    book.chapters[1].images.add(
      ChapterImage(
        id: 'unopened-image',
        path: '/local/scene.png',
        alt: '场景',
        widthFactor: .5,
      ),
    );
    final untouchedBody = book.chapters[1].body;
    final count = book.wordCount;
    await store.save(original);
    final lazy = await store.load();
    final loaded = lazy.books.single;
    expect(loaded.chapters.every((chapter) => !chapter.bodyLoaded), isTrue);
    expect(loaded.roles, isEmpty);
    expect(loaded.worlds, isEmpty);
    expect(loaded.wordCount, count);
    await store.loadChapter(loaded, loaded.chapters.first);
    await store.loadSection(loaded, BookSection.roles);
    expect(loaded.chapters.first.body, book.chapters.first.body);
    expect(loaded.chapters[1].bodyLoaded, isFalse);
    expect(loaded.worlds, isEmpty);
    loaded.chapters.first.body += '\n新增内容';
    loaded.chapters[1].title = '未打开也可重命名';
    await store.save(lazy);
    await store.close();

    final eager = SqliteStore(
      databasePath: path,
      factory: databaseFactoryFfi,
      legacyJsonPath: '${folder.path}/missing.json',
    );
    addTearDown(eager.close);
    final restored = (await eager.load()).books.single;
    expect(restored.chapters.first.body, endsWith('新增内容'));
    expect(restored.chapters[1].title, '未打开也可重命名');
    expect(restored.chapters[1].body, untouchedBody);
    expect(restored.chapters[1].markers.single.id, 'unopened-marker');
    expect(restored.chapters[1].images.single.widthFactor, .5);
    expect(
      restored.worlds.map((item) => item.toJson()),
      book.worlds.map((item) => item.toJson()),
    );
    expect(
      restored.events.map((item) => item.toJson()),
      book.events.map((item) => item.toJson()),
    );
  });

  test('v2 数据库迁移为章节字数和附件分区，不改变正文', () async {
    final folder = await Directory.systemTemp.createTemp('yejian-migration-');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/old.db';
    final old = SqliteStore(
      databasePath: path,
      factory: databaseFactoryFfi,
      legacyJsonPath: '${folder.path}/missing.json',
    );
    final original = LibraryData.seeded(profileSetupComplete: true);
    original.books.single.chapters.first.images.add(
      ChapterImage(
        id: 'migration-image',
        path: '/local/image.png',
        widthFactor: .6,
      ),
    );
    original.books.single.chapters.first.markers.add(
      ChapterMarker(
        id: 'migration-marker',
        kind: 'revision',
        start: 0,
        end: 2,
        quote: original.books.single.chapters.first.body.substring(0, 2),
      ),
    );
    await old.save(original);
    final db = await old.database;
    await db.execute('DROP INDEX idx_structured_chapter');
    await db.execute('ALTER TABLE structured_entities DROP COLUMN chapter_id');
    await db.execute('ALTER TABLE chapters DROP COLUMN word_count');
    await db.setVersion(2);
    await old.close();
    final migrated = SqliteStore(
      databasePath: path,
      factory: databaseFactoryFfi,
      legacyJsonPath: '${folder.path}/missing.json',
      lazyLoad: true,
    );
    addTearDown(migrated.close);
    final data = await migrated.load();
    expect(data.books.single.wordCount, original.books.single.wordCount);
    await migrated.loadChapter(
      data.books.single,
      data.books.single.chapters.first,
    );
    expect(
      data.books.single.chapters.first.body,
      original.books.single.chapters.first.body,
    );
    expect(data.books.single.chapters.first.images.single.widthFactor, .6);
    expect(
      data.books.single.chapters.first.markers.single.id,
      'migration-marker',
    );
  });

  test('字数缓存随正文变化失效，图片说明不计入字数', () {
    final chapter = Chapter(id: 'c', title: '标题', body: '你好 hello');
    expect(chapter.wordCount, 3);
    chapter.body += '\n![长说明](yejian-image:image-1)';
    expect(chapter.wordCount, 3);
    chapter.body += '\n新增';
    expect(chapter.wordCount, 5);
  });

  const samplePath = String.fromEnvironment('YEJIAN_SAMPLE_SNS');
  test('本地 SNS 样本按需加载并转换分文件格式，正文逐章完整往返', () async {
    final project = ProjectArchive.decode(await File(samplePath).readAsBytes());
    final originalBodies = [
      for (final c in project.books.single.chapters) c.body,
    ];
    final folder = await Directory.systemTemp.createTemp('yejian-sample-');
    addTearDown(() => folder.delete(recursive: true));
    final store = SqliteStore(
      databasePath: '${folder.path}/sample.db',
      factory: databaseFactoryFfi,
      legacyJsonPath: '${folder.path}/missing.json',
      lazyLoad: true,
    );
    addTearDown(store.close);
    await store.save(
      LibraryData(
        profile: project.profile,
        settings: AppSettings(),
        books: project.books,
      ),
    );
    final book = (await store.load()).books.single;
    expect(book.chapters.every((chapter) => !chapter.bodyLoaded), isTrue);
    await store.loadChapter(book, book.chapters.first);
    expect(book.chapters.where((chapter) => chapter.bodyLoaded).length, 1);
    expect(book.chapters.first.body, originalBodies.first);
    for (final section in BookSection.values) {
      await store.loadSection(book, section);
    }
    for (final chapter in book.chapters) {
      await store.loadChapter(book, chapter);
    }
    final encoded = await ProjectArchive.encode(
      books: [book],
      profile: project.profile,
      isCollection: false,
    );
    final decoded = ProjectArchive.decode(encoded);
    expect(
      decoded.books.single.chapters.map((chapter) => chapter.body),
      originalBodies,
    );
    const devicePath = String.fromEnvironment('YEJIAN_DEVICE_EXPORTED_SNS');
    if (devicePath.isNotEmpty) {
      final deviceExport = ProjectArchive.decode(
        await File(devicePath).readAsBytes(),
      );
      expect(
        deviceExport.books.single.chapters.map((chapter) => chapter.body),
        originalBodies,
      );
      expect(
        deviceExport.books.single.chapters.map((chapter) => chapter.title),
        project.books.single.chapters.map((chapter) => chapter.title),
      );
    }
    final uncached = Stopwatch()..start();
    var total = 0;
    for (var i = 0; i < 100; i++) {
      total = book.chapters.fold(
        0,
        (sum, chapter) => sum + countWords(chapter.body),
      );
    }
    uncached.stop();
    final cached = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      expect(book.wordCount, total);
    }
    cached.stop();
    // Informational benchmark; correctness does not depend on machine speed.
    // ignore: avoid_print
    print(
      'SNS 样本 ${book.chapters.length} 章 / $total 字：100 次全量统计 ${uncached.elapsedMicroseconds}µs，缓存统计 ${cached.elapsedMicroseconds}µs',
    );
  }, skip: samplePath.isEmpty ? '仅在本地提供 SNS 样本时运行' : false);
}
