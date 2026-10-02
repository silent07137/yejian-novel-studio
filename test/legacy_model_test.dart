import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yejian_native/data/sqlite_store.dart';
import 'package:yejian_native/models/library_data.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('legacy events without track IDs get a mutable default track', () {
    final book = Book.fromJson({
      'id': 'legacy-book',
      'title': '旧版作品',
      'events': [
        {'id': 'legacy-event', 'title': '旧版事件'},
      ],
    });

    expect(book.events.single.trackIds, [book.tracks.single.id]);
    book.events.single.roleIds.add('role-1');
    expect(book.events.single.roleIds, ['role-1']);
  });

  test(
    'legacy library JSON imports into SQLite without a startup error',
    () async {
      final directory = await Directory.systemTemp.createTemp('yejian-legacy-');
      addTearDown(() => directory.delete(recursive: true));
      final legacyFile = File(
        '${directory.path}${Platform.pathSeparator}library.json',
      );
      await legacyFile.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'books': [
            {
              'id': 'legacy-book',
              'title': '旧版作品',
              'events': [
                {'id': 'legacy-event', 'title': '旧版事件'},
              ],
            },
          ],
        }),
      );
      final store = SqliteStore(
        databasePath: '${directory.path}${Platform.pathSeparator}yejian.db',
        factory: databaseFactoryFfi,
        legacyJsonPath: legacyFile.path,
      );
      addTearDown(store.close);

      final data = await store.load();
      expect(data.books.single.events.single.trackIds, [
        data.books.single.tracks.single.id,
      ]);
      expect(await legacyFile.exists(), isTrue);
    },
  );
}
