import 'dart:convert';
import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Keeps all Windows application support files next to the installed program.
/// The installer places the executable in a user-writable `yejian` directory.
Future<void> configureWindowsDataDirectory() async {
  if (!Platform.isWindows) return;

  final original = PathProviderPlatform.instance;
  if (original is _InstalledDataPathProvider) return;
  final previousPath = await original.getApplicationSupportPath();
  final destination = Directory(
    '${File(Platform.resolvedExecutable).parent.path}'
    '${Platform.pathSeparator}user-data',
  );
  if (previousPath != null) {
    await migrateWindowsDataDirectory(
      previous: Directory(previousPath),
      destination: destination,
    );
  }
  await destination.create(recursive: true);
  PathProviderPlatform.instance = _InstalledDataPathProvider(
    original,
    destination.path,
  );
}

/// Copies old AppData files once. Never deletes or overwrites an existing file.
Future<void> migrateWindowsDataDirectory({
  required Directory previous,
  required Directory destination,
}) async {
  if (!await previous.exists()) return;
  if (previous.absolute.path.toLowerCase() ==
      destination.absolute.path.toLowerCase()) {
    return;
  }

  final marker = File(
    '${destination.path}${Platform.pathSeparator}.legacy-migration-complete',
  );
  if (await marker.exists()) return;
  final copiedDatabase = File(
    '${destination.path}${Platform.pathSeparator}yejian'
    '${Platform.pathSeparator}yejian.db',
  );
  final destinationHadDatabase = await copiedDatabase.exists();

  await destination.create(recursive: true);
  await for (final entity in previous.list(
    recursive: true,
    followLinks: false,
  )) {
    final relative = entity.path.substring(previous.path.length);
    if (destinationHadDatabase &&
        (relative.endsWith('${Platform.pathSeparator}yejian.db') ||
            relative.endsWith('${Platform.pathSeparator}yejian.db-wal') ||
            relative.endsWith('${Platform.pathSeparator}yejian.db-shm'))) {
      continue;
    }
    final targetPath = '${destination.path}$relative';
    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
    } else if (entity is File) {
      final target = File(targetPath);
      if (!await target.exists()) {
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
    }
  }

  final oldPath = previous.absolute.path;
  final newPath = destination.absolute.path;
  if (await copiedDatabase.exists()) {
    await _rewriteDatabasePaths(copiedDatabase.path, oldPath, newPath);
  } else {
    final legacyJson = File(
      '${destination.path}${Platform.pathSeparator}yejian'
      '${Platform.pathSeparator}library.json',
    );
    if (await legacyJson.exists()) {
      final contents = await legacyJson.readAsString();
      await legacyJson.writeAsString(
        contents.replaceAll(
          jsonEncode(oldPath).substring(1, jsonEncode(oldPath).length - 1),
          jsonEncode(newPath).substring(1, jsonEncode(newPath).length - 1),
        ),
        flush: true,
      );
    }
  }
  await marker.writeAsString('1', flush: true);
}

Future<void> _rewriteDatabasePaths(
  String databasePath,
  String oldPath,
  String newPath,
) async {
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(databasePath);
  try {
    final oldEscaped = jsonEncode(oldPath);
    final newEscaped = jsonEncode(newPath);
    final oldJsonPath = oldEscaped.substring(1, oldEscaped.length - 1);
    final newJsonPath = newEscaped.substring(1, newEscaped.length - 1);
    await database.transaction((transaction) async {
      final tables = await transaction.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );
      for (final row in tables) {
        final table = row['name'] as String;
        final quotedTable = '"${table.replaceAll('"', '""')}"';
        final columns = await transaction.rawQuery(
          'PRAGMA table_info($quotedTable)',
        );
        for (final column in columns) {
          if (!(column['type'] as String).toUpperCase().contains('TEXT')) {
            continue;
          }
          final name = column['name'] as String;
          final quotedName = '"${name.replaceAll('"', '""')}"';
          await transaction.rawUpdate(
            'UPDATE $quotedTable SET $quotedName = '
            'REPLACE(REPLACE($quotedName, ?, ?), ?, ?) '
            'WHERE INSTR($quotedName, ?) > 0 OR INSTR($quotedName, ?) > 0',
            [oldJsonPath, newJsonPath, oldPath, newPath, oldJsonPath, oldPath],
          );
        }
      }
    });
  } finally {
    await database.close();
  }
}

class _InstalledDataPathProvider extends PathProviderPlatform {
  _InstalledDataPathProvider(this.delegate, this.supportPath);

  final PathProviderPlatform delegate;
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getTemporaryPath() => delegate.getTemporaryPath();

  @override
  Future<String?> getLibraryPath() => delegate.getLibraryPath();

  @override
  Future<String?> getApplicationDocumentsPath() =>
      delegate.getApplicationDocumentsPath();

  @override
  Future<String?> getApplicationCachePath() =>
      delegate.getApplicationCachePath();

  @override
  Future<String?> getExternalStoragePath() => delegate.getExternalStoragePath();

  @override
  Future<List<String>?> getExternalCachePaths() =>
      delegate.getExternalCachePaths();

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) =>
      delegate.getExternalStoragePaths(type: type);

  @override
  Future<String?> getDownloadsPath() => delegate.getDownloadsPath();
}
