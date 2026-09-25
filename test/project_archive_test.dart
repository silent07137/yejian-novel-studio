import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
    final expected = data.books.first.toJson()..['coverPath'] = null;
    expect(decoded.isCollection, isFalse);
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

  test('多书 .snss 保留全部作品，且与 .sns 后缀不可混用', () async {
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
    expect(
      () => ProjectArchive.decode(bytes, fileName: 'books.sns'),
      throwsA(isA<ProjectArchiveException>()),
    );
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
          file.name == 'content.json'
              ? utf8.encode('{"profile":{},"books":[]}')
              : file.readBytes()!,
        ),
      );
    }
    expect(
      () => ProjectArchive.decode(
        ZipEncoder().encodeBytes(altered),
        fileName: 'broken.sns',
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
    final migrated = ProjectArchive.decode(legacy, fileName: 'old.sns');
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
}
