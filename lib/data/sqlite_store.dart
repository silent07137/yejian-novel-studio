import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/library_data.dart';
import 'local_store.dart';

class RevisionConflict implements Exception {
  const RevisionConflict({
    required this.entityId,
    required this.expected,
    required this.actual,
  });

  final String entityId;
  final int expected;
  final int actual;

  @override
  String toString() =>
      'RevisionConflict($entityId, expected: $expected, actual: $actual)';
}

/// 页间的本地事务存储。
///
/// Android 使用 sqflite，Windows/Linux/macOS 使用同一套 SQLite 架构的 FFI
/// 实现。旧版 library.json 仅作为一次性迁移来源，不再作为主存储。
class SqliteStore implements SectionedDataStore {
  SqliteStore({
    this.databasePath,
    this.factory,
    this.legacyJsonPath,
    this.lazyLoad = false,
  });

  static const databaseVersion = 3;
  static const databaseFileName = 'yejian.db';

  final String? databasePath;
  final DatabaseFactory? factory;
  final String? legacyJsonPath;
  final bool lazyLoad;
  Database? _db;
  Future<Database>? _opening;
  final Map<String, String> _chapterMetadataSnapshots = {};
  final Map<String, String> _chapterBodySnapshots = {};

  Future<Database> get database {
    if (_db case final Database db) return Future.value(db);
    return _opening ??= _open()
        .then((db) {
          _db = db;
          return db;
        })
        .whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final selectedFactory = factory ?? _platformFactory();
    final path = databasePath ?? await _defaultDatabasePath();
    return selectedFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          // Android 的 sqflite 会把有返回行的 PRAGMA 视为查询；使用
          // execute() 会在数据库打开阶段抛错，导致应用停在启动画面。
          await db.rawQuery('PRAGMA busy_timeout = 5000');
          if (!Platform.isAndroid && !Platform.isIOS) {
            await db.rawQuery('PRAGMA journal_mode = WAL');
          }
        },
        onCreate: _createSchema,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE app_settings ADD COLUMN appearance_mode TEXT NOT NULL DEFAULT 'light'",
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE chapters ADD COLUMN word_count INTEGER',
            );
            for (final row in await db.query(
              'chapters',
              columns: ['id', 'body'],
            )) {
              final count = Chapter(
                id: row['id']! as String,
                title: '',
                body: row['body'] as String? ?? '',
              ).wordCount;
              await db.update(
                'chapters',
                {'word_count': count},
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            }
            await db.execute(
              'ALTER TABLE structured_entities ADD COLUMN chapter_id TEXT',
            );
            // Do not require SQLite's optional JSON extension on older Android
            // devices. Decode the existing attachment metadata in Dart.
            for (final row in await db.query(
              'structured_entities',
              columns: ['entity_type', 'id', 'payload'],
              where: "entity_type IN ('chapter_marker', 'chapter_image')",
            )) {
              final payload =
                  jsonDecode(row['payload']! as String) as Map<String, dynamic>;
              await db.update(
                'structured_entities',
                {'chapter_id': payload['chapterId']},
                where: 'entity_type = ? AND id = ?',
                whereArgs: [row['entity_type'], row['id']],
              );
            }
            await db.execute(
              'CREATE INDEX idx_structured_chapter ON structured_entities(project_id, entity_type, chapter_id)',
            );
          }
        },
      ),
    );
  }

  DatabaseFactory _platformFactory() {
    if (Platform.isAndroid || Platform.isIOS) return sqflite.databaseFactory;
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  Future<String> _defaultDatabasePath() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}yejian',
    );
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}$databaseFileName';
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE app_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        author_name TEXT NOT NULL,
        avatar_path TEXT,
        writing_days INTEGER NOT NULL DEFAULT 1,
        setup_complete INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        palette TEXT NOT NULL,
        appearance_mode TEXT NOT NULL DEFAULT 'light',
        font_size REAL NOT NULL,
        line_height REAL NOT NULL,
        custom_font_path TEXT,
        active_project_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        cover_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sort_index INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1,
        snapshot TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE volumes (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL REFERENCES projects(id),
        title TEXT NOT NULL,
        summary TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT '进行中',
        export_enabled INTEGER NOT NULL DEFAULT 1,
        sort_index INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1,
        snapshot TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL REFERENCES projects(id),
        volume_id TEXT REFERENCES volumes(id),
        title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        word_count INTEGER,
        summary TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT '草稿',
        export_enabled INTEGER NOT NULL DEFAULT 1,
        sort_index INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        snapshot TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE structured_entities (
        entity_type TEXT NOT NULL,
        id TEXT NOT NULL,
        project_id TEXT NOT NULL REFERENCES projects(id),
        chapter_id TEXT,
        sort_index INTEGER NOT NULL DEFAULT 0,
        payload TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        snapshot TEXT NOT NULL,
        deleted_at TEXT,
        PRIMARY KEY (entity_type, id)
      )
    ''');
    await db.execute('''
      CREATE TABLE drafts (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE entity_revisions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        snapshot TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(entity_type, entity_id, revision)
      )
    ''');
    await db.execute('''
      CREATE TABLE attachments (
        content_hash TEXT PRIMARY KEY,
        relative_path TEXT NOT NULL,
        mime_type TEXT,
        byte_length INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE migration_log (
        migration_key TEXT PRIMARY KEY,
        completed_at TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_projects_active ON projects(deleted_at, sort_index)',
    );
    await db.execute(
      'CREATE INDEX idx_volumes_project ON volumes(project_id, deleted_at, sort_index)',
    );
    await db.execute(
      'CREATE INDEX idx_chapters_project ON chapters(project_id, deleted_at, sort_index)',
    );
    await db.execute(
      'CREATE INDEX idx_entities_project ON structured_entities(project_id, entity_type, deleted_at, sort_index)',
    );
    await db.execute(
      'CREATE INDEX idx_structured_chapter ON structured_entities(project_id, entity_type, chapter_id)',
    );
    await db.execute(
      'CREATE INDEX idx_revisions_entity ON entity_revisions(entity_type, entity_id, revision DESC)',
    );
  }

  @override
  Future<LibraryData> load() async {
    final db = await database;
    await _migrateLegacyJson(db);
    final profiles = await db.query('app_profile', limit: 1);
    final settings = await db.query('app_settings', limit: 1);
    if (profiles.isEmpty && settings.isEmpty) return LibraryData.empty();

    final profileRow = profiles.firstOrNull;
    final settingsRow = settings.firstOrNull;
    final projectRows = await db.query(
      'projects',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_index, updated_at DESC',
    );
    final books = <Book>[];
    for (final row in projectRows) {
      books.add(await _loadProject(db, row));
    }
    return LibraryData(
      profile: WriterProfile(
        authorName: profileRow?['author_name'] as String? ?? '未命名',
        avatarPath: profileRow?['avatar_path'] as String?,
        writingDays: profileRow?['writing_days'] as int? ?? 1,
        setupComplete: (profileRow?['setup_complete'] as int? ?? 0) == 1,
      ),
      settings: AppSettings(
        palette: settingsRow?['palette'] as String? ?? 'yejian',
        appearanceMode: settingsRow?['appearance_mode'] as String? ?? 'light',
        fontSize: (settingsRow?['font_size'] as num?)?.toDouble() ?? 18,
        lineHeight: (settingsRow?['line_height'] as num?)?.toDouble() ?? 1.7,
        customFontPath: settingsRow?['custom_font_path'] as String?,
      ),
      books: books,
      activeBookId: settingsRow?['active_project_id'] as String?,
    );
  }

  Future<Book> _loadProject(Database db, Map<String, Object?> row) async {
    final projectId = row['id']! as String;
    final volumeRows = await db.query(
      'volumes',
      where: 'project_id = ? AND deleted_at IS NULL',
      whereArgs: [projectId],
      orderBy: 'sort_index',
    );
    final chapterRows = await db.query(
      'chapters',
      columns: lazyLoad
          ? [
              'id',
              'volume_id',
              'title',
              'summary',
              'status',
              'export_enabled',
              'sort_index',
              'updated_at',
              'word_count',
            ]
          : null,
      where: 'project_id = ? AND deleted_at IS NULL',
      whereArgs: [projectId],
      orderBy: 'sort_index',
    );
    final entities = lazyLoad
        ? <Map<String, Object?>>[]
        : await db.query(
            'structured_entities',
            where: 'project_id = ? AND deleted_at IS NULL',
            whereArgs: [projectId],
            orderBy: 'entity_type, sort_index',
          );
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final entity in entities) {
      final type = entity['entity_type']! as String;
      final payload = jsonDecode(entity['payload']! as String);
      if (payload is Map<String, dynamic>) {
        grouped.putIfAbsent(type, () => []).add(payload);
      }
    }
    final markersByChapter = <String, List<ChapterMarker>>{};
    for (final payload
        in grouped['chapter_marker'] ?? const <Map<String, dynamic>>[]) {
      final chapterId = payload['chapterId'] as String?;
      if (chapterId == null) continue;
      markersByChapter
          .putIfAbsent(chapterId, () => [])
          .add(ChapterMarker.fromJson(payload));
    }
    final imagesByChapter = <String, List<ChapterImage>>{};
    for (final payload
        in grouped['chapter_image'] ?? const <Map<String, dynamic>>[]) {
      final chapterId = payload['chapterId'] as String?;
      if (chapterId == null) continue;
      imagesByChapter
          .putIfAbsent(chapterId, () => [])
          .add(ChapterImage.fromJson(payload));
    }
    final sectionCounts = <String, int>{};
    if (lazyLoad) {
      for (final count in await db.rawQuery(
        'SELECT entity_type, COUNT(*) AS total FROM structured_entities WHERE project_id = ? AND deleted_at IS NULL GROUP BY entity_type',
        [projectId],
      )) {
        sectionCounts[count['entity_type']! as String] = count['total']! as int;
      }
      for (final chapter in chapterRows) {
        _chapterMetadataSnapshots[chapter['id']! as String] = jsonEncode({
          'project_id': projectId,
          'volume_id': chapter['volume_id'],
          'title': chapter['title'],
          'summary': chapter['summary'],
          'status': chapter['status'],
          'export_enabled': chapter['export_enabled'],
          'sort_index': chapter['sort_index'],
          'updated_at': chapter['updated_at'],
          'word_count': chapter['word_count'],
        });
      }
    }
    return Book(
      id: projectId,
      title: row['title']! as String,
      description: row['description'] as String? ?? '',
      coverPath: row['cover_path'] as String?,
      volumes: volumeRows
          .map(
            (item) => Volume(
              id: item['id']! as String,
              title: item['title']! as String,
              summary: item['summary'] as String? ?? '',
              status: item['status'] as String? ?? '进行中',
              exportEnabled: (item['export_enabled'] as int? ?? 1) == 1,
              sortIndex: item['sort_index'] as int? ?? 0,
            ),
          )
          .toList(),
      chapters: chapterRows
          .map(
            (item) => Chapter(
              id: item['id']! as String,
              title: item['title']! as String,
              volumeId: item['volume_id'] as String?,
              body: item['body'] as String? ?? '',
              bodyLoaded: !lazyLoad,
              savedWordCount: item['word_count'] as int?,
              summary: item['summary'] as String? ?? '',
              status: item['status'] as String? ?? '草稿',
              exportEnabled: (item['export_enabled'] as int? ?? 1) == 1,
              sortIndex: item['sort_index'] as int? ?? 0,
              markers: markersByChapter[item['id']],
              images: imagesByChapter[item['id']],
              updatedAt: DateTime.tryParse(item['updated_at'] as String? ?? ''),
            ),
          )
          .toList(),
      roles: _decodeList(grouped['role'], RoleCard.fromJson),
      roleFields: _decodeList(
        grouped['role_field'],
        CustomFieldDefinition.fromJson,
      ),
      roleBaseFields: _decodeList(
        grouped['role_base_field'],
        CustomFieldDefinition.fromJson,
      ),
      worlds: _decodeList(grouped['world'], WorldCard.fromJson),
      worldFields: _decodeList(
        grouped['world_field'],
        CustomFieldDefinition.fromJson,
      ),
      worldBaseFields: _decodeList(
        grouped['world_base_field'],
        CustomFieldDefinition.fromJson,
      ),
      tracks: _decodeList(grouped['track'], StoryTrack.fromJson),
      events: _decodeList(grouped['event'], StoryEvent.fromJson),
      storyLinks: _decodeList(grouped['story_link'], StoryLink.fromJson),
      clues: _decodeList(grouped['clue'], PlotClue.fromJson),
      notes: _decodeList(grouped['note'], IdeaNote.fromJson),
      loadedSections: lazyLoad ? <BookSection>{} : null,
      sectionCounts: sectionCounts,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
    );
  }

  List<T> _decodeList<T>(
    List<Map<String, dynamic>>? values,
    T Function(Map<String, dynamic>) decoder,
  ) => (values ?? const []).map(decoder).toList();

  @override
  Future<void> loadChapter(Book book, Chapter chapter) async {
    if (chapter.bodyLoaded) return;
    final db = await database;
    final rows = await db.query(
      'chapters',
      columns: ['body'],
      where: 'project_id = ? AND id = ? AND deleted_at IS NULL',
      whereArgs: [book.id, chapter.id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('章节已经不存在，请重新打开作品');
    final entities = await db.query(
      'structured_entities',
      columns: ['entity_type', 'payload'],
      where: "project_id = ? AND chapter_id = ? AND entity_type IN ('chapter_marker', 'chapter_image') AND deleted_at IS NULL",
      whereArgs: [book.id, chapter.id],
      orderBy: 'sort_index',
    );
    // Publish the hydrated chapter only after every part has been read.
    final markers = <ChapterMarker>[];
    final images = <ChapterImage>[];
    for (final row in entities) {
      final json =
          jsonDecode(row['payload']! as String) as Map<String, dynamic>;
      if (row['entity_type'] == 'chapter_marker') {
        markers.add(ChapterMarker.fromJson(json));
      } else {
        images.add(ChapterImage.fromJson(json));
      }
    }
    chapter.markers = markers;
    chapter.images = images;
    chapter.body = rows.single['body']! as String;
    _chapterBodySnapshots[chapter.id] = chapter.body;
  }

  @override
  Future<void> loadSection(Book book, BookSection section) async {
    if (book.loadedSections.contains(section)) return;
    final types = switch (section) {
      BookSection.roles => ['role', 'role_field', 'role_base_field'],
      BookSection.worlds => ['world', 'world_field', 'world_base_field'],
      BookSection.story => ['track', 'event', 'story_link', 'clue', 'note'],
    };
    final db = await database;
    final rows = await db.query(
      'structured_entities',
      columns: ['entity_type', 'payload'],
      where:
          'project_id = ? AND entity_type IN (${List.filled(types.length, '?').join(',')}) AND deleted_at IS NULL',
      whereArgs: [book.id, ...types],
      orderBy: 'entity_type, sort_index',
    );
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      grouped
          .putIfAbsent(row['entity_type']! as String, () => [])
          .add(jsonDecode(row['payload']! as String) as Map<String, dynamic>);
    }
    switch (section) {
      case BookSection.roles:
        book.roles = _decodeList(grouped['role'], RoleCard.fromJson);
        book.roleFields = _decodeList(
          grouped['role_field'],
          CustomFieldDefinition.fromJson,
        );
        book.roleBaseFields = grouped['role_base_field']?.isNotEmpty == true
            ? _decodeList(
                grouped['role_base_field'],
                CustomFieldDefinition.fromJson,
              )
            : defaultRoleBaseFields();
      case BookSection.worlds:
        book.worlds = _decodeList(grouped['world'], WorldCard.fromJson);
        book.worldFields = _decodeList(
          grouped['world_field'],
          CustomFieldDefinition.fromJson,
        );
        book.worldBaseFields = grouped['world_base_field']?.isNotEmpty == true
            ? _decodeList(
                grouped['world_base_field'],
                CustomFieldDefinition.fromJson,
              )
            : defaultWorldBaseFields();
      case BookSection.story:
        book.tracks = _decodeList(grouped['track'], StoryTrack.fromJson);
        book.events = _decodeList(grouped['event'], StoryEvent.fromJson);
        book.storyLinks = _decodeList(
          grouped['story_link'],
          StoryLink.fromJson,
        );
        book.clues = _decodeList(grouped['clue'], PlotClue.fromJson);
        book.notes = _decodeList(grouped['note'], IdeaNote.fromJson);
        normalizeTimelineEventOrder(book.events);
    }
    book.loadedSections.add(section);
  }

  @override
  Future<void> save(LibraryData data) async {
    final db = await database;
    await _saveToDatabase(db, data);
  }

  Future<void> _saveToDatabase(Database db, LibraryData data) async {
    final metadataSnapshots = <String, String>{};
    final bodySnapshots = <String, String>{};
    await db.transaction((txn) async {
      await txn.insert('app_profile', {
        'id': 1,
        'author_name': data.profile.authorName,
        'avatar_path': data.profile.avatarPath,
        'writing_days': data.profile.writingDays,
        'setup_complete': data.profile.setupComplete ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'id': 1,
        'palette': data.settings.palette,
        'appearance_mode': data.settings.appearanceMode,
        'font_size': data.settings.fontSize,
        'line_height': data.settings.lineHeight,
        'custom_font_path': data.settings.customFontPath,
        'active_project_id': data.activeBookId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final projectIds = <String>{};
      for (var index = 0; index < data.books.length; index++) {
        final book = data.books[index];
        projectIds.add(book.id);
        await _upsertVersioned(
          txn,
          table: 'projects',
          entityType: 'project',
          id: book.id,
          values: {
            'title': book.title,
            'description': book.description,
            'cover_path': book.coverPath,
            'created_at': book.createdAt.toIso8601String(),
            'updated_at': book.updatedAt.toIso8601String(),
            'sort_index': index,
          },
        );
        await _saveProjectChildren(txn, book, metadataSnapshots, bodySnapshots);
      }
      await _softDeleteMissing(txn, table: 'projects', activeIds: projectIds);
    });
    _chapterMetadataSnapshots.addAll(metadataSnapshots);
    _chapterBodySnapshots.addAll(bodySnapshots);
  }

  Future<void> _saveProjectChildren(
    Transaction txn,
    Book book,
    Map<String, String> metadataSnapshots,
    Map<String, String> bodySnapshots,
  ) async {
    final volumeIds = <String>{};
    for (var index = 0; index < book.volumes.length; index++) {
      final volume = book.volumes[index];
      volume.sortIndex = index;
      volumeIds.add(volume.id);
      await _upsertVersioned(
        txn,
        table: 'volumes',
        entityType: 'volume',
        id: volume.id,
        values: {
          'project_id': book.id,
          'title': volume.title,
          'summary': volume.summary,
          'status': volume.status,
          'export_enabled': volume.exportEnabled ? 1 : 0,
          'sort_index': index,
        },
      );
    }
    await _softDeleteMissing(
      txn,
      table: 'volumes',
      activeIds: volumeIds,
      where: 'project_id = ?',
      whereArgs: [book.id],
    );

    final chapterIds = <String>{};
    for (var index = 0; index < book.chapters.length; index++) {
      final chapter = book.chapters[index];
      chapter.sortIndex = index;
      chapterIds.add(chapter.id);
      final metadata = <String, Object?>{
        'project_id': book.id,
        'volume_id': chapter.volumeId,
        'title': chapter.title,
        'summary': chapter.summary,
        'status': chapter.status,
        'export_enabled': chapter.exportEnabled ? 1 : 0,
        'sort_index': index,
        'updated_at': chapter.updatedAt.toIso8601String(),
        'word_count': chapter.wordCount,
      };
      final metadataText = jsonEncode(metadata);
      if (_chapterMetadataSnapshots[chapter.id] == metadataText &&
          (!chapter.bodyLoaded ||
              _chapterBodySnapshots[chapter.id] == chapter.body)) {
        continue;
      }
      // Metadata edits on an unopened chapter must preserve its stored prose.
      var body = chapter.body;
      if (!chapter.bodyLoaded) {
        final stored = await txn.query(
          'chapters',
          columns: ['body'],
          where: 'project_id = ? AND id = ? AND deleted_at IS NULL',
          whereArgs: [book.id, chapter.id],
          limit: 1,
        );
        if (stored.isEmpty) {
          throw StateError('未加载章节的原文不存在，已取消保存');
        }
        body = stored.single['body']! as String;
      }
      await _upsertVersioned(
        txn,
        table: 'chapters',
        entityType: 'chapter',
        id: chapter.id,
        values: {...metadata, 'body': body},
      );
      metadataSnapshots[chapter.id] = metadataText;
      if (chapter.bodyLoaded) bodySnapshots[chapter.id] = body;
    }
    await _softDeleteMissing(
      txn,
      table: 'chapters',
      activeIds: chapterIds,
      where: 'project_id = ?',
      whereArgs: [book.id],
    );

    if (book.loadedSections.contains(BookSection.roles)) {
      await _saveStructured(
        txn,
        book.id,
        'role',
        book.roles,
        (v) => v.toJson(),
      );
      await _saveStructured(
        txn,
        book.id,
        'role_field',
        book.roleFields,
        (v) => v.toJson(),
      );
      await _saveStructured(
        txn,
        book.id,
        'role_base_field',
        book.roleBaseFields,
        (v) => v.toJson(),
        storageId: (v) => '${book.id}:${v.id}',
      );
    }
    if (book.loadedSections.contains(BookSection.worlds)) {
      await _saveStructured(
        txn,
        book.id,
        'world',
        book.worlds,
        (v) => v.toJson(),
      );
      await _saveStructured(
        txn,
        book.id,
        'world_field',
        book.worldFields,
        (v) => v.toJson(),
      );
      await _saveStructured(
        txn,
        book.id,
        'world_base_field',
        book.worldBaseFields,
        (v) => v.toJson(),
        storageId: (v) => '${book.id}:${v.id}',
      );
    }
    if (book.loadedSections.contains(BookSection.story)) {
      await _saveStructured(
        txn,
        book.id,
        'track',
        book.tracks,
        (v) => v.toJson(),
      );
      await _saveStructured(
        txn,
        book.id,
        'event',
        book.events,
        (v) => v.toJson(),
      );
      await _saveStructured(
        txn,
        book.id,
        'story_link',
        book.storyLinks,
        (v) => v.toJson(),
      );
      await _saveStructured(
        txn,
        book.id,
        'clue',
        book.clues,
        (v) => v.toJson(),
      );
      await _saveStructured(
        txn,
        book.id,
        'note',
        book.notes,
        (v) => v.toJson(),
      );
    }
    final loadedChapterIds = book.chapters
        .where((chapter) => chapter.bodyLoaded)
        .map((chapter) => chapter.id)
        .toSet();
    if (loadedChapterIds.isEmpty) return;
    await _saveStructured(
      txn,
      book.id,
      'chapter_marker',
      [
        for (final chapter in book.chapters.where(
          (chapter) => chapter.bodyLoaded,
        ))
          for (final marker in chapter.markers)
            {...marker.toJson(), 'chapterId': chapter.id},
      ],
      (value) => value,
      chapterIds: loadedChapterIds,
    );
    await _saveStructured(
      txn,
      book.id,
      'chapter_image',
      [
        for (final chapter in book.chapters.where(
          (chapter) => chapter.bodyLoaded,
        ))
          for (final image in chapter.images)
            {...image.toJson(), 'chapterId': chapter.id},
      ],
      (value) => value,
      chapterIds: loadedChapterIds,
    );
  }

  Future<void> _saveStructured<T>(
    Transaction txn,
    String projectId,
    String entityType,
    List<T> values,
    Map<String, dynamic> Function(T) encode, {
    String Function(T)? storageId,
    Set<String>? chapterIds,
  }) async {
    final activeIds = <String>{};
    for (var index = 0; index < values.length; index++) {
      final payload = encode(values[index]);
      final id = storageId?.call(values[index]) ?? payload['id']! as String;
      activeIds.add(id);
      await _upsertStructured(
        txn,
        entityType: entityType,
        id: id,
        projectId: projectId,
        sortIndex: index,
        payload: payload,
      );
    }
    await _softDeleteMissingStructured(
      txn,
      projectId: projectId,
      entityType: entityType,
      activeIds: activeIds,
      chapterIds: chapterIds,
    );
  }

  Future<void> _upsertStructured(
    Transaction txn, {
    required String entityType,
    required String id,
    required String projectId,
    required int sortIndex,
    required Map<String, dynamic> payload,
  }) async {
    final payloadText = jsonEncode(payload);
    final snapshot = jsonEncode({
      'project_id': projectId,
      'sort_index': sortIndex,
      'payload': payload,
    });
    final rows = await txn.query(
      'structured_entities',
      columns: ['revision', 'snapshot', 'deleted_at'],
      where: 'entity_type = ? AND id = ?',
      whereArgs: [entityType, id],
      limit: 1,
    );
    if (rows.isNotEmpty &&
        rows.first['snapshot'] == snapshot &&
        rows.first['deleted_at'] == null) {
      return;
    }
    final revision = rows.isEmpty ? 1 : (rows.first['revision']! as int) + 1;
    final values = <String, Object?>{
      'entity_type': entityType,
      'id': id,
      'project_id': projectId,
      'sort_index': sortIndex,
      'payload': payloadText,
      'chapter_id': payload['chapterId'] as String?,
      'revision': revision,
      'snapshot': snapshot,
      'deleted_at': null,
    };
    if (rows.isEmpty) {
      await txn.insert('structured_entities', values);
    } else {
      await txn.update(
        'structured_entities',
        values,
        where: 'entity_type = ? AND id = ?',
        whereArgs: [entityType, id],
      );
    }
    await _appendRevision(txn, entityType, id, revision, snapshot);
  }

  Future<void> _upsertVersioned(
    Transaction txn, {
    required String table,
    required String entityType,
    required String id,
    required Map<String, Object?> values,
  }) async {
    final snapshot = jsonEncode(values);
    final rows = await txn.query(
      table,
      columns: ['revision', 'snapshot', 'deleted_at'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty &&
        rows.first['snapshot'] == snapshot &&
        rows.first['deleted_at'] == null) {
      return;
    }
    final revision = rows.isEmpty ? 1 : (rows.first['revision']! as int) + 1;
    final storedValues = <String, Object?>{
      'id': id,
      ...values,
      'revision': revision,
      'snapshot': snapshot,
      'deleted_at': null,
    };
    if (rows.isEmpty) {
      await txn.insert(table, storedValues);
    } else {
      await txn.update(table, storedValues, where: 'id = ?', whereArgs: [id]);
    }
    await _appendRevision(txn, entityType, id, revision, snapshot);
  }

  Future<void> _appendRevision(
    Transaction txn,
    String entityType,
    String entityId,
    int revision,
    String snapshot,
  ) => txn.insert('entity_revisions', {
    'entity_type': entityType,
    'entity_id': entityId,
    'revision': revision,
    'snapshot': snapshot,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> _softDeleteMissing(
    Transaction txn, {
    required String table,
    required Set<String> activeIds,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final rows = await txn.query(
      table,
      columns: ['id', 'revision', 'snapshot'],
      where: [?where, 'deleted_at IS NULL'].join(' AND '),
      whereArgs: whereArgs,
    );
    final entityType = table == 'projects'
        ? 'project'
        : table.substring(0, table.length - 1);
    for (final row in rows) {
      final id = row['id']! as String;
      if (activeIds.contains(id)) continue;
      final deletedAt = DateTime.now().toUtc().toIso8601String();
      final revision = (row['revision']! as int) + 1;
      final snapshot = jsonEncode({
        'deletedAt': deletedAt,
        'previous': jsonDecode(row['snapshot']! as String),
      });
      await txn.update(
        table,
        {'deleted_at': deletedAt, 'revision': revision, 'snapshot': snapshot},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _appendRevision(txn, entityType, id, revision, snapshot);
    }
  }

  Future<void> _softDeleteMissingStructured(
    Transaction txn, {
    required String projectId,
    required String entityType,
    required Set<String> activeIds,
    Set<String>? chapterIds,
  }) async {
    final rows = await txn.query(
      'structured_entities',
      columns: ['id', 'revision', 'snapshot'],
      where:
          'project_id = ? AND entity_type = ? AND deleted_at IS NULL'
          '${chapterIds == null ? '' : ' AND chapter_id IN (${List.filled(chapterIds.length, '?').join(',')})'}',
      whereArgs: [projectId, entityType, ...?chapterIds],
    );
    for (final row in rows) {
      final id = row['id']! as String;
      if (activeIds.contains(id)) continue;
      final deletedAt = DateTime.now().toUtc().toIso8601String();
      final revision = (row['revision']! as int) + 1;
      final snapshot = jsonEncode({
        'deletedAt': deletedAt,
        'previous': jsonDecode(row['snapshot']! as String),
      });
      await txn.update(
        'structured_entities',
        {'deleted_at': deletedAt, 'revision': revision, 'snapshot': snapshot},
        where: 'entity_type = ? AND id = ?',
        whereArgs: [entityType, id],
      );
      await _appendRevision(txn, entityType, id, revision, snapshot);
    }
  }

  Future<void> _migrateLegacyJson(Database db) async {
    const key = 'legacy-library-json-v1';
    final done = await db.query(
      'migration_log',
      where: 'migration_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (done.isNotEmpty) return;
    final path = legacyJsonPath ?? await _defaultLegacyPath();
    final file = File(path);
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final legacy = LibraryData.fromJson(decoded);
      await _saveToDatabase(db, legacy);
      await db.insert('migration_log', {
        'migration_key': key,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'details': 'Imported from $path; source retained.',
      });
    } on FormatException {
      // 保留原文件并等待恢复工具处理，绝不以空数据覆盖损坏来源。
    }
  }

  Future<String> _defaultLegacyPath() async {
    final support = await getApplicationSupportDirectory();
    return '${support.path}${Platform.pathSeparator}yejian'
        '${Platform.pathSeparator}library.json';
  }

  Future<int?> chapterRevision(String chapterId) async {
    final db = await database;
    final rows = await db.query(
      'chapters',
      columns: ['revision'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [chapterId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['revision']! as int;
  }

  Future<int> updateChapterBody({
    required String chapterId,
    required String body,
    required int expectedRevision,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'chapters',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [chapterId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Chapter not found: $chapterId');
      final row = rows.first;
      final actual = row['revision']! as int;
      if (actual != expectedRevision) {
        throw RevisionConflict(
          entityId: chapterId,
          expected: expectedRevision,
          actual: actual,
        );
      }
      final revision = actual + 1;
      final values = <String, Object?>{
        'project_id': row['project_id'],
        'volume_id': row['volume_id'],
        'title': row['title'],
        'body': body,
        'summary': row['summary'],
        'status': row['status'],
        'export_enabled': row['export_enabled'],
        'sort_index': row['sort_index'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final snapshot = jsonEncode(values);
      await txn.update(
        'chapters',
        {...values, 'revision': revision, 'snapshot': snapshot},
        where: 'id = ? AND revision = ?',
        whereArgs: [chapterId, expectedRevision],
      );
      await _appendRevision(txn, 'chapter', chapterId, revision, snapshot);
      return revision;
    });
  }

  Future<List<Map<String, Object?>>> revisions(
    String entityType,
    String entityId,
  ) async {
    final db = await database;
    return db.query(
      'entity_revisions',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      orderBy: 'revision DESC',
    );
  }

  Future<void> restoreProject(String projectId) =>
      _restoreVersioned('projects', 'project', projectId);

  Future<void> restoreChapter(String chapterId) =>
      _restoreVersioned('chapters', 'chapter', chapterId);

  Future<void> _restoreVersioned(
    String table,
    String entityType,
    String entityId,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        table,
        where: 'id = ? AND deleted_at IS NOT NULL',
        whereArgs: [entityId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.first;
      final deletedSnapshot = jsonDecode(row['snapshot']! as String);
      final previous = deletedSnapshot is Map<String, dynamic>
          ? deletedSnapshot['previous']
          : null;
      if (previous is! Map<String, dynamic>) {
        throw const FormatException('Missing soft-delete snapshot');
      }
      final revision = (row['revision']! as int) + 1;
      final restoredSnapshot = jsonEncode(previous);
      await txn.update(
        table,
        {
          'deleted_at': null,
          'revision': revision,
          'snapshot': restoredSnapshot,
        },
        where: 'id = ?',
        whereArgs: [entityId],
      );
      await _appendRevision(
        txn,
        entityType,
        entityId,
        revision,
        restoredSnapshot,
      );
    });
  }

  Future<List<Map<String, Object?>>> deletedItems(String table) async {
    const allowed = {'projects', 'volumes', 'chapters'};
    if (!allowed.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported trash table');
    }
    final db = await database;
    return db.query(
      table,
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
  }

  Future<void> close() async {
    final db = _db ?? await _opening;
    _db = null;
    _chapterMetadataSnapshots.clear();
    _chapterBodySnapshots.clear();
    await db?.close();
  }
}
