import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yejian_native/platform/windows_data_directory.dart';

void main() {
  test('copies Windows data and rewrites paths without deleting originals', () async {
    final root = await Directory.systemTemp.createTemp(
      'yejian-data-migration-',
    );
    addTearDown(() => root.delete(recursive: true));
    final previous = Directory('${root.path}${Platform.pathSeparator}old');
    final destination = Directory('${root.path}${Platform.pathSeparator}new');
    final oldData = Directory(
      '${previous.path}${Platform.pathSeparator}yejian',
    );
    await oldData.create(recursive: true);
    final oldAssetPath =
        '${oldData.path}${Platform.pathSeparator}chapter-images'
        '${Platform.pathSeparator}image.png';
    await File(oldAssetPath).create(recursive: true);
    await File(
      '${previous.path}${Platform.pathSeparator}flutter_secure_storage.dat',
    ).writeAsBytes([1, 2, 3]);

    sqfliteFfiInit();
    final oldDatabasePath = '${oldData.path}${Platform.pathSeparator}yejian.db';
    final oldDatabase = await databaseFactoryFfi.openDatabase(oldDatabasePath);
    await oldDatabase.execute('CREATE TABLE sample (path TEXT, payload TEXT)');
    await oldDatabase.insert('sample', {
      'path': oldAssetPath,
      'payload': jsonEncode({'path': oldAssetPath}),
    });
    await oldDatabase.close();

    await migrateWindowsDataDirectory(
      previous: previous,
      destination: destination,
    );

    final newDatabasePath =
        '${destination.path}${Platform.pathSeparator}yejian'
        '${Platform.pathSeparator}yejian.db';
    final newDatabase = await databaseFactoryFfi.openDatabase(newDatabasePath);
    final row = (await newDatabase.query('sample')).single;
    await newDatabase.close();
    final expectedAssetPath = oldAssetPath.replaceFirst(
      previous.path,
      destination.path,
    );
    expect(row['path'], expectedAssetPath);
    expect(
      (jsonDecode(row['payload'] as String) as Map)['path'],
      expectedAssetPath,
    );
    expect(await File(expectedAssetPath).exists(), isTrue);
    expect(
      await File(
        '${destination.path}${Platform.pathSeparator}flutter_secure_storage.dat',
      ).readAsBytes(),
      [1, 2, 3],
    );
    expect(await File(oldDatabasePath).exists(), isTrue);
    expect(await File(oldAssetPath).exists(), isTrue);
  });

  test('leaves an already initialized destination untouched', () async {
    final root = await Directory.systemTemp.createTemp('yejian-existing-data-');
    addTearDown(() => root.delete(recursive: true));
    final previous = Directory('${root.path}${Platform.pathSeparator}old');
    final destination = Directory('${root.path}${Platform.pathSeparator}new');
    final relative = 'yejian${Platform.pathSeparator}yejian.db';
    await File('${previous.path}${Platform.pathSeparator}$relative')
        .create(recursive: true);
    final existing = File(
      '${destination.path}${Platform.pathSeparator}$relative',
    );
    await existing.create(recursive: true);
    await existing.writeAsString('new data');
    await File(
      '${destination.path}${Platform.pathSeparator}.legacy-migration-complete',
    ).writeAsString('1');

    await migrateWindowsDataDirectory(
      previous: previous,
      destination: destination,
    );

    expect(await existing.readAsString(), 'new data');
  });
}
