import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/library_data.dart';

abstract class DataStore {
  Future<LibraryData> load();
  Future<void> save(LibraryData data);
}

class LocalStore implements DataStore {
  static const _fileName = 'library.json';

  Future<File> _dataFile() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}yejian',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  @override
  Future<LibraryData> load() async {
    try {
      final file = await _dataFile();
      if (!await file.exists()) {
        final seeded = LibraryData.seeded();
        await save(seeded);
        return seeded;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return LibraryData.fromJson(json);
    } on Object {
      return LibraryData.seeded();
    }
  }

  @override
  Future<void> save(LibraryData data) async {
    final file = await _dataFile();
    final temporary = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await temporary.writeAsString(encoder.convert(data.toJson()), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }
}
