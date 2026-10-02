import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yejian_native/data/local_store.dart';
import 'package:yejian_native/data/sqlite_store.dart';
import 'package:yejian_native/domain/project_archive.dart';
import 'package:yejian_native/models/library_data.dart';
import 'package:yejian_native/platform/document_saver.dart';
import 'package:yejian_native/state/app_controller.dart';

class _MemoryStore implements DataStore {
  _MemoryStore(this.data);

  LibraryData data;
  int saves = 0;
  bool failImportSave = false;

  @override
  Future<LibraryData> load() async => data;

  @override
  Future<void> save(LibraryData value) async {
    saves++;
    if (failImportSave && saves >= 2) throw StateError('模拟事务失败');
    data = LibraryData.fromJson(value.toJson());
  }
}

class _MemorySaver implements DocumentSaver {
  Uint8List? bytes;
  String? name;

  @override
  Future<DocumentSaveResult> save({
    required Uint8List bytes,
    required String suggestedName,
    required String mimeType,
    required List<String> extensions,
  }) async {
    this.bytes = bytes;
    name = suggestedName;
    return DocumentSaveResult.saved(suggestedName);
  }
}

Uint8List _oldZip(LibraryData data, int version) {
  final content = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'profile': data.profile.toJson()..['avatarPath'] = null,
        'books': [
          for (final book in data.books) book.toJson()..['coverPath'] = null,
        ],
      }),
    ),
  );
  return ZipEncoder().encodeBytes(
    Archive()
      ..add(ArchiveFile.bytes('content.json', content))
      ..add(
        ArchiveFile.bytes(
          'manifest.json',
          utf8.encode(
            jsonEncode({
              'format': ProjectArchive.format,
              'formatVersion': version,
              'kind': data.books.length == 1 ? 'book' : 'collection',
              'contentSha256': sha256.convert(content).toString(),
              'assets': <String, dynamic>{},
            }),
          ),
        ),
      ),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('yejian-project-test-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('单书 .sns 含全部结构化数据与封面头像，不泄漏原设备路径', () async {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final cover = File('${temporary.path}${Platform.pathSeparator}cover.png');
    final avatar = File('${temporary.path}${Platform.pathSeparator}avatar.jpg');
    await cover.writeAsBytes([1, 2, 3, 4]);
    await avatar.writeAsBytes([5, 6, 7]);
    data.books.first.coverPath = cover.path;
    data.profile.avatarPath = avatar.path;

    final bytes = await ProjectArchive.encode(
      books: [data.books.first],
      profile: data.profile,
      isCollection: false,
    );
    final decoded = ProjectArchive.decode(bytes, fileName: 'sample.sns');
    final cached = ProjectArchive.decode(bytes, fileName: 'sample.bin');
    final expected = data.books.first.toJson()..['coverPath'] = null;
    expect(decoded.isCollection, isFalse);
    expect(cached.isCollection, isFalse);
    expect(cached.books.single.id, data.books.first.id);
    expect(decoded.books.single.toJson(), expected);
    expect(decoded.covers[data.books.first.id], [1, 2, 3, 4]);
    expect(decoded.avatar, [5, 6, 7]);
    expect(decoded.profile.authorName, data.profile.authorName);
    expect(
      utf8.decode(bytes, allowMalformed: true),
      isNot(contains(cover.path)),
    );
    expect(
      utf8.decode(bytes, allowMalformed: true),
      isNot(contains(avatar.path)),
    );
  });

  test('正文图片随 .sns 备份、恢复且不泄漏本机路径', () async {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final chapter = data.books.first.chapters.first;
    final image = File('${temporary.path}${Platform.pathSeparator}scene.png');
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
      'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
    );
    await image.writeAsBytes(imageBytes);
    chapter.images.add(
      ChapterImage(id: 'image-1', path: image.path, alt: '场景'),
    );
    chapter.body = '上文\n\n![场景](yejian-image:image-1)\n\n下文';

    final bytes = await ProjectArchive.encode(
      books: [data.books.first],
      profile: data.profile,
      isCollection: false,
    );
    final project = ProjectArchive.decode(bytes, fileName: 'with-image.sns');
    expect(project.chapterImages['image-1'], imageBytes);
    expect(project.books.single.chapters.first.images.single.path, isEmpty);
    expect(project.books.single.chapters.first.body, chapter.body);
    expect(
      utf8.decode(bytes, allowMalformed: true),
      isNot(contains(image.path)),
    );

    final store = _MemoryStore(LibraryData.empty());
    final controller = AppController(
      store: store,
      data: store.data,
      projectAssetDirectory: temporary,
    );
    await controller.importProjectArchive(project, replaceExisting: false);
    final restored = controller.data.books.single.chapters.first.images.single;
    expect(await File(restored.path).readAsBytes(), imageBytes);
    expect(restored.path, isNot(image.path));
    controller.dispose();
  });

  test('旧版 ZIP 工程仍可导入，正文图片资源缺失时拒绝导入', () async {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final bytes = await ProjectArchive.encode(
      books: [data.books.first],
      profile: data.profile,
      isCollection: false,
    );
    final paths = ZipDecoder()
        .decodeBytes(bytes)
        .map((file) => file.name)
        .toList();
    expect(paths, isNot(contains('content.json')));
    expect(
      paths,
      containsAll([
        'library.json',
        'profile.json',
        'books/0/book.json',
        'books/0/roles.json',
        'books/0/worlds.json',
        'books/0/story.json',
        'books/0/chapters/0.json',
      ]),
    );
    for (final version in [1, 2]) {
      expect(
        ProjectArchive.decode(_oldZip(data, version)).books.single.toJson(),
        data.books.first.toJson(),
      );
    }

    final image = File('${temporary.path}${Platform.pathSeparator}scene.png');
    await image.writeAsBytes([0x89, 0x50, 0x4e, 0x47]);
    data.books.first.chapters.first.images.add(
      ChapterImage(id: 'image-1', path: image.path),
    );
    final withImage = ZipDecoder().decodeBytes(
      await ProjectArchive.encode(
        books: [data.books.first],
        profile: data.profile,
        isCollection: false,
      ),
    );
    final missingImage = Archive();
    for (final file in withImage) {
      if (file.name.startsWith('assets/chapter-')) continue;
      missingImage.add(ArchiveFile.bytes(file.name, file.readBytes()!));
    }
    expect(
      () => ProjectArchive.decode(ZipEncoder().encodeBytes(missingImage)),
      throwsA(isA<ProjectArchiveException>()),
    );
  });

  test('多书工程按清单识别，Android 缓存后缀不影响导入', () async {
    final data = LibraryData.seeded(profileSetupComplete: true);
    data.books.add(Book(id: 'second-book', title: '第二本书'));
    final bytes = await ProjectArchive.encode(
      books: data.books,
      profile: data.profile,
      isCollection: true,
    );
    final decoded = ProjectArchive.decode(bytes, fileName: 'books.snss');
    expect(decoded.isCollection, isTrue);
    expect(decoded.books.map((book) => book.title), ['雾灯来信', '第二本书']);
    for (final name in ['books.sns', 'books.bin', 'books.zip']) {
      final reopened = ProjectArchive.decode(bytes, fileName: name);
      expect(reopened.isCollection, isTrue);
      expect(reopened.books.length, 2);
    }
  });

  test('内容摘要不匹配时拒绝导入，旧版 JSON 仍可迁移', () async {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final bytes = await ProjectArchive.encode(
      books: [data.books.first],
      profile: data.profile,
      isCollection: false,
    );
    final original = ZipDecoder().decodeBytes(bytes);
    final altered = Archive();
    for (final file in original) {
      altered.add(
        ArchiveFile.bytes(
          file.name,
          file.name == 'books/0/chapters/0.json'
              ? utf8.encode('{"profile":{},"books":[]}')
              : file.readBytes()!,
        ),
      );
    }
    expect(
      () => ProjectArchive.decode(
        ZipEncoder().encodeBytes(altered),
        fileName: 'broken.bin',
      ),
      throwsA(isA<ProjectArchiveException>()),
    );

    final legacyBook = data.books.first.toJson()
      ..['coverPath'] = 'old-device.png';
    final legacy = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'sns',
          'formatVersion': 1,
          'book': legacyBook,
          'profile': data.profile.toJson(),
        }),
      ),
    );
    final migrated = ProjectArchive.decode(legacy, fileName: 'old.json');
    expect(migrated.isLegacy, isTrue);
    expect(migrated.books.single.coverPath, isNull);
    expect(
      migrated.books.single.chapters.length,
      data.books.first.chapters.length,
    );
  });

  test('导入先拒绝重复 ID，明确替换后事务保存并恢复封面', () async {
    final source = LibraryData.seeded(profileSetupComplete: true);
    final cover = File('${temporary.path}${Platform.pathSeparator}cover.png');
    await cover.writeAsBytes([1, 2, 3]);
    source.books.first.coverPath = cover.path;
    final project = ProjectArchive.decode(
      await ProjectArchive.encode(
        books: [source.books.first],
        profile: source.profile,
        isCollection: false,
      ),
      fileName: 'one.sns',
    );
    final store = _MemoryStore(LibraryData.empty());
    final controller = AppController(
      store: store,
      data: store.data,
      projectAssetDirectory: temporary,
    );
    expect(
      await controller.importProjectArchive(project, replaceExisting: false),
      1,
    );
    final imported = controller.data.books.single;
    expect(await File(imported.coverPath!).readAsBytes(), [1, 2, 3]);
    expect(imported.chapters.length, source.books.first.chapters.length);
    expect(controller.data.profile.authorName, source.profile.authorName);
    await expectLater(
      controller.importProjectArchive(project, replaceExisting: false),
      throwsA(isA<ProjectArchiveException>()),
    );
    imported.chapters.first.body = '待恢复';
    await controller.importProjectArchive(project, replaceExisting: true);
    expect(controller.data.books.single.chapters.first.body, isNot('待恢复'));
    controller.dispose();
  });

  test('存储失败不会改动书架，并清理刚写入的图片', () async {
    final source = LibraryData.seeded(profileSetupComplete: true);
    final cover = File('${temporary.path}${Platform.pathSeparator}cover.png');
    await cover.writeAsBytes([4, 5, 6]);
    source.books.first.coverPath = cover.path;
    final project = ProjectArchive.decode(
      await ProjectArchive.encode(
        books: [source.books.first],
        profile: source.profile,
        isCollection: false,
      ),
      fileName: 'one.sns',
    );
    final store = _MemoryStore(LibraryData.empty())..failImportSave = true;
    final controller = AppController(
      store: store,
      data: store.data,
      projectAssetDirectory: temporary,
    );
    await expectLater(
      controller.importProjectArchive(project, replaceExisting: false),
      throwsA(isA<StateError>()),
    );
    expect(controller.data.books, isEmpty);
    final importedAssetDirectory = Directory(
      '${temporary.path}${Platform.pathSeparator}yejian'
      '${Platform.pathSeparator}imported-assets',
    );
    expect(await importedAssetDirectory.list().toList(), isEmpty);
    controller.dispose();
  });

  test('工程导入后 SQLite 可重新加载章节、角色、世界观与情节', () async {
    final source = LibraryData.seeded(profileSetupComplete: true);
    final project = ProjectArchive.decode(
      await ProjectArchive.encode(
        books: [source.books.first],
        profile: source.profile,
        isCollection: false,
      ),
      fileName: 'one.sns',
    );
    final store = SqliteStore(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      legacyJsonPath: '${temporary.path}/missing-library.json',
    );
    addTearDown(store.close);
    final controller = AppController(
      store: store,
      data: LibraryData.empty(),
      projectAssetDirectory: temporary,
    );
    await controller.importProjectArchive(project, replaceExisting: false);
    final restored = (await store.load()).books.single;
    expect(restored.chapters.length, source.books.first.chapters.length);
    expect(restored.roles.length, source.books.first.roles.length);
    expect(restored.worlds.length, source.books.first.worlds.length);
    expect(restored.events.length, source.books.first.events.length);
    expect(restored.storyLinks.length, source.books.first.storyLinks.length);
    controller.dispose();
  });

  test('工程导出仅在主动调用时生成 .sns 与 .snss', () async {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final saver = _MemorySaver();
    final controller = AppController(
      store: _MemoryStore(data),
      data: data,
      documentSaver: saver,
    );
    expect(saver.bytes, isNull);
    expect(
      (await controller.exportCurrentBookProject()).status,
      DocumentSaveStatus.saved,
    );
    expect(saver.name, endsWith('.sns'));
    expect(
      ProjectArchive.decode(saver.bytes!, fileName: saver.name).books,
      hasLength(1),
    );
    expect(
      (await controller.exportLibraryProject()).status,
      DocumentSaveStatus.saved,
    );
    expect(saver.name, endsWith('.snss'));
    expect(
      ProjectArchive.decode(saver.bytes!, fileName: saver.name).isCollection,
      isTrue,
    );
    controller.dispose();
  });

  test('插图后 Markdown 导出打包正文与图片，TXT 保持可读', () async {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final saver = _MemorySaver();
    final controller = AppController(
      store: _MemoryStore(data),
      data: data,
      documentSaver: saver,
      projectAssetDirectory: temporary,
    );
    final chapter = controller.activeChapter!;
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
      'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
    );
    final insertion = await controller.insertChapterImageBytes(
      imageBytes,
      offset: chapter.body.length,
      alt: '插图说明',
    );
    expect(chapter.body, insertion.body);
    expect(chapter.images, hasLength(1));
    expect(await File(chapter.images.single.path).readAsBytes(), imageBytes);
    expect(chapter.wordCount, lessThan(chapter.body.length));

    expect(
      (await controller.exportMarkdown()).status,
      DocumentSaveStatus.saved,
    );
    expect(saver.name, endsWith('-Markdown.zip'));
    final files = ZipDecoder().decodeBytes(saver.bytes!);
    final markdown = utf8.decode(
      files.singleWhere((file) => file.name.endsWith('.md')).readBytes()!,
    );
    expect(markdown, contains('![插图说明](assets/'));
    expect(markdown, isNot(contains('yejian-image:')));
    expect(
      files.singleWhere((file) => file.name.startsWith('assets/')).readBytes(),
      imageBytes,
    );
    expect(buildPlainText(data.books.first), contains('〔图片：插图说明〕'));
    controller.dispose();
  });
}
