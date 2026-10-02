import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../models/library_data.dart';

class ProjectArchiveException implements Exception {
  const ProjectArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProjectArchiveData {
  const ProjectArchiveData({
    required this.isCollection,
    required this.books,
    required this.profile,
    required this.covers,
    required this.coverExtensions,
    required this.avatar,
    required this.avatarExtension,
    this.chapterImages = const {},
    this.chapterImageExtensions = const {},
    this.isLegacy = false,
  });

  final bool isCollection;
  final List<Book> books;
  final WriterProfile profile;
  final Map<String, Uint8List> covers;
  final Map<String, String> coverExtensions;
  final Uint8List? avatar;
  final String? avatarExtension;
  final Map<String, Uint8List> chapterImages;
  final Map<String, String> chapterImageExtensions;
  final bool isLegacy;
}

/// Portable, versioned ZIP container. No paths from the archive are ever
/// extracted directly to disk; only validated, named assets are restored.
class ProjectArchive {
  static const format = 'yejian-project';
  static const version = 3;
  static const maxArchiveBytes = 128 * 1024 * 1024;
  static const maxContentBytes = 64 * 1024 * 1024;
  static const maxAssetBytes = 32 * 1024 * 1024;
  static const maxExpandedBytes = 256 * 1024 * 1024;

  static Future<Uint8List> encode({
    required List<Book> books,
    required WriterProfile profile,
    required bool isCollection,
  }) async {
    if (books.isEmpty || !isCollection && books.length != 1) {
      throw const ProjectArchiveException('工程文件至少需要一本书；单书工程只能包含一本书');
    }
    if (books.length > 1000) {
      throw const ProjectArchiveException('工程包含过多作品，最多支持 1000 本');
    }
    final ids = books.map((book) => book.id).toList();
    if (ids.any((id) => id.isEmpty) || ids.toSet().length != ids.length) {
      throw const ProjectArchiveException('书架中存在无效或重复的作品 ID');
    }
    final archive = Archive();
    final assets = <String, Map<String, String>>{};
    final bookPayloads = <Map<String, dynamic>>[];
    final imageIds = <String>{};
    for (final (index, book) in books.indexed) {
      if (!book.fullyLoaded) {
        throw const ProjectArchiveException('作品尚未加载完整，请稍后再导出');
      }
      final payload = book.toJson()..['coverPath'] = null;
      final chapters = payload['chapters'] as List<dynamic>;
      for (final (chapterIndex, chapter) in book.chapters.indexed) {
        final chapterPayload = chapters[chapterIndex] as Map<String, dynamic>;
        final images = chapterPayload['images'] as List<dynamic>;
        for (final (imageIndex, image) in chapter.images.indexed) {
          if (image.id.isEmpty || !imageIds.add(image.id)) {
            throw const ProjectArchiveException('正文图片 ID 无效或重复');
          }
          final bytes = await _readAsset(image.path, '正文图片');
          final extension = _imageExtension(image.path);
          final entry =
              'assets/chapter-$index-$chapterIndex-$imageIndex.$extension';
          archive.add(ArchiveFile.bytes(entry, bytes));
          assets['image:${image.id}'] = {
            'path': entry,
            'sha256': _hash(bytes),
            'extension': extension,
          };
          (images[imageIndex] as Map<String, dynamic>)['path'] = null;
        }
      }
      bookPayloads.add(payload);
      if (book.coverPath case final String path when path.isNotEmpty) {
        final bytes = await _readAsset(path, '《${book.title}》的封面');
        final extension = _imageExtension(path);
        final entry = 'assets/cover-$index.$extension';
        archive.add(ArchiveFile.bytes(entry, bytes));
        assets['cover:${book.id}'] = {
          'path': entry,
          'sha256': _hash(bytes),
          'extension': extension,
        };
      }
    }
    final profilePayload = profile.toJson()..['avatarPath'] = null;
    if (profile.avatarPath case final String path when path.isNotEmpty) {
      final bytes = await _readAsset(path, '作者头像');
      final extension = _imageExtension(path);
      final entry = 'assets/avatar.$extension';
      archive.add(ArchiveFile.bytes(entry, bytes));
      assets['avatar'] = {
        'path': entry,
        'sha256': _hash(bytes),
        'extension': extension,
      };
    }
    final parts = <String, Map<String, dynamic>>{};
    var contentSize = 0;
    String writePart(String path, Object value) {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
      contentSize += bytes.length;
      if (contentSize > maxContentBytes) {
        throw const ProjectArchiveException('工程正文超过 64 MB，暂不支持导出');
      }
      parts[path] = {'sha256': _hash(bytes), 'size': bytes.length};
      archive.add(ArchiveFile.bytes(path, bytes));
      return path;
    }

    final bookIndex = <Map<String, dynamic>>[];
    for (final (index, original) in bookPayloads.indexed) {
      final payload = Map<String, dynamic>.from(original);
      final root = 'books/$index';
      final chapterPaths = <String>[];
      final chapters = payload.remove('chapters') as List<dynamic>;
      for (final (chapterIndex, chapter) in chapters.indexed) {
        chapterPaths.add(
          writePart('$root/chapters/$chapterIndex.json', chapter),
        );
      }
      Map<String, dynamic> take(List<String> keys) => {
        for (final key in keys) key: payload.remove(key),
      };
      bookIndex.add({
        'chapters': chapterPaths,
        'volumes': writePart('$root/volumes.json', {
          'volumes': payload.remove('volumes'),
        }),
        'roles': writePart(
          '$root/roles.json',
          take(['roles', 'roleFields', 'roleBaseFields']),
        ),
        'worlds': writePart(
          '$root/worlds.json',
          take(['worlds', 'worldFields', 'worldBaseFields']),
        ),
        'story': writePart(
          '$root/story.json',
          take(['tracks', 'events', 'storyLinks', 'clues', 'notes']),
        ),
        'metadata': writePart('$root/book.json', payload),
      });
    }
    writePart('profile.json', profilePayload);
    writePart('library.json', {'profile': 'profile.json', 'books': bookIndex});
    final manifest = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': format,
          'formatVersion': version,
          'kind': isCollection ? 'collection' : 'book',
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'files': parts,
          'assets': assets,
        }),
      ),
    );
    archive.add(ArchiveFile.bytes('manifest.json', manifest));
    if (manifest.length > 4 * 1024 * 1024 ||
        archive.length > 20000 ||
        archive.fold<int>(0, (sum, file) => sum + file.size) >
            maxExpandedBytes) {
      throw const ProjectArchiveException('工程条目过多或解压后超过 256 MB，暂不支持导出');
    }
    final encoded = ZipEncoder().encodeBytes(archive);
    if (encoded.length > maxArchiveBytes) {
      throw const ProjectArchiveException('工程文件超过 128 MB，暂不支持导出');
    }
    return encoded;
  }

  static ProjectArchiveData decode(Uint8List bytes, {String? fileName}) {
    // Kept for callers that report the chosen document's name. Android may
    // supply a MIME-derived cache name, so neither it nor its suffix is trusted.
    if (bytes.length > maxArchiveBytes) {
      throw const ProjectArchiveException('工程文件超过 128 MB，拒绝导入');
    }
    if (bytes.isEmpty) {
      throw const ProjectArchiveException('工程文件为空');
    }
    if (bytes.first == 0x7b) {
      return _decodeLegacy(bytes);
    }
    try {
      // Inspect declared sizes before asking the decoder to expand content.
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.length > 20000) {
        throw const ProjectArchiveException('工程文件包含过多条目');
      }
      final files = <String, ArchiveFile>{};
      var expandedBytes = 0;
      for (final file in archive) {
        if (!file.isFile ||
            file.symbolicLink != null ||
            file.name.contains('..') ||
            file.name.contains('\\') ||
            file.name.startsWith('/') ||
            file.name.contains(':') ||
            files.containsKey(file.name)) {
          throw const ProjectArchiveException('工程文件包含无效条目');
        }
        if (file.size < 0) {
          throw const ProjectArchiveException('工程文件包含无效条目');
        }
        expandedBytes += file.size;
        if (expandedBytes > maxExpandedBytes) {
          throw const ProjectArchiveException('工程文件解压后超过 256 MB');
        }
        files[file.name] = file;
      }
      final manifestBytes = _entry(files, 'manifest.json', 4 * 1024 * 1024);
      final manifest = _jsonMap(manifestBytes, '工程清单');
      if (manifest['format'] != format) {
        throw const ProjectArchiveException('不是页间工程文件');
      }
      final formatVersion = manifest['formatVersion'];
      if (formatVersion is! int ||
          formatVersion < 1 ||
          formatVersion > version) {
        throw const ProjectArchiveException('工程格式版本不受支持，请更新应用');
      }
      final kind = manifest['kind'];
      if (kind != 'book' && kind != 'collection') {
        throw const ProjectArchiveException('工程类型无效');
      }
      final isCollection = kind == 'collection';
      final referencedFiles = <String>{'manifest.json'};
      final Map<String, dynamic> content;
      if (formatVersion == 3) {
        content = _decodeParts(files, manifest, referencedFiles);
      } else {
        final contentBytes = _entry(files, 'content.json', maxContentBytes);
        if (_hash(contentBytes) != manifest['contentSha256']) {
          throw const ProjectArchiveException('工程内容校验失败');
        }
        content = _jsonMap(contentBytes, '工程内容');
        referencedFiles.add('content.json');
      }
      final books = _booksFromContent(content, isCollection: isCollection);
      final profileJson = content['profile'];
      if (profileJson is! Map<String, dynamic>) {
        throw const ProjectArchiveException('工程作者信息无效');
      }
      final profile = WriterProfile.fromJson(profileJson)..avatarPath = null;
      final assetsJson = manifest['assets'];
      if (assetsJson is! Map<String, dynamic>) {
        throw const ProjectArchiveException('工程资源清单无效');
      }
      final covers = <String, Uint8List>{};
      final coverExtensions = <String, String>{};
      final chapterImages = <String, Uint8List>{};
      final chapterImageExtensions = <String, String>{};
      Uint8List? avatar;
      String? avatarExtension;
      final bookIds = books.map((book) => book.id).toSet();
      final imageIds = <String>{};
      for (final book in books) {
        for (final chapter in book.chapters) {
          for (final image in chapter.images) {
            if (image.id.isEmpty || !imageIds.add(image.id)) {
              throw const ProjectArchiveException('工程正文图片 ID 无效或重复');
            }
          }
        }
      }
      if (formatVersion == 1 && imageIds.isNotEmpty) {
        throw const ProjectArchiveException('旧版工程包含不受支持的正文图片');
      }
      for (final entry in assetsJson.entries) {
        final description = entry.value;
        if (description is! Map<String, dynamic>) {
          throw const ProjectArchiveException('工程资源清单无效');
        }
        final path = description['path'];
        final extension = description['extension'];
        if (path is! String ||
            !path.startsWith('assets/') ||
            !referencedFiles.add(path) ||
            extension is! String ||
            !RegExp(r'^(png|jpg|jpeg|webp|bin)$').hasMatch(extension)) {
          throw const ProjectArchiveException('工程资源路径无效');
        }
        final asset = _entry(files, path, maxAssetBytes);
        if (_hash(asset) != description['sha256']) {
          throw const ProjectArchiveException('工程图片校验失败');
        }
        if (entry.key == 'avatar') {
          avatar = asset;
          avatarExtension = extension;
        } else if (entry.key.startsWith('cover:') &&
            bookIds.contains(entry.key.substring(6))) {
          final bookId = entry.key.substring(6);
          covers[bookId] = asset;
          coverExtensions[bookId] = extension;
        } else if (entry.key.startsWith('image:') &&
            formatVersion >= 2 &&
            imageIds.contains(entry.key.substring(6))) {
          final imageId = entry.key.substring(6);
          chapterImages[imageId] = asset;
          chapterImageExtensions[imageId] = extension;
        } else {
          throw const ProjectArchiveException('工程资源归属无效');
        }
      }
      if (files.keys.any((path) => !referencedFiles.contains(path))) {
        throw const ProjectArchiveException('工程文件包含未声明的内容');
      }
      if (imageIds.any((id) => !chapterImages.containsKey(id))) {
        throw const ProjectArchiveException('工程正文图片缺失');
      }
      return ProjectArchiveData(
        isCollection: isCollection,
        books: books,
        profile: profile,
        covers: covers,
        coverExtensions: coverExtensions,
        avatar: avatar,
        avatarExtension: avatarExtension,
        chapterImages: chapterImages,
        chapterImageExtensions: chapterImageExtensions,
      );
    } on ProjectArchiveException {
      rethrow;
    } on Object {
      throw const ProjectArchiveException('工程文件损坏或格式不受支持');
    }
  }

  static Map<String, dynamic> _decodeParts(
    Map<String, ArchiveFile> files,
    Map<String, dynamic> manifest,
    Set<String> referencedFiles,
  ) {
    final descriptions = manifest['files'];
    if (descriptions is! Map<String, dynamic> || descriptions.length > 20000) {
      throw const ProjectArchiveException('工程分文件清单无效');
    }
    var contentSize = 0;
    Map<String, dynamic> readPart(Object? path) {
      if (path is! String ||
          !path.endsWith('.json') ||
          !referencedFiles.add(path)) {
        throw const ProjectArchiveException('工程分文件引用无效或重复');
      }
      final description = descriptions[path];
      if (description is! Map<String, dynamic>) {
        throw const ProjectArchiveException('工程分文件未登记');
      }
      final bytes = _entry(files, path, maxContentBytes);
      contentSize += bytes.length;
      if (contentSize > maxContentBytes ||
          bytes.length != description['size'] ||
          _hash(bytes) != description['sha256']) {
        throw const ProjectArchiveException('工程分文件校验失败');
      }
      return _jsonMap(bytes, '工程分文件');
    }

    final index = readPart('library.json');
    final profile = readPart(index['profile']);
    final entries = index['books'];
    if (entries is! List || entries.isEmpty || entries.length > 1000) {
      throw const ProjectArchiveException('工程作品索引无效');
    }
    final books = <Map<String, dynamic>>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic> || entry['chapters'] is! List) {
        throw const ProjectArchiveException('工程作品索引无效');
      }
      final book = readPart(entry['metadata']);
      const sectionKeys = {
        'volumes': ['volumes'],
        'roles': ['roles', 'roleFields', 'roleBaseFields'],
        'worlds': ['worlds', 'worldFields', 'worldBaseFields'],
        'story': ['tracks', 'events', 'storyLinks', 'clues', 'notes'],
      };
      for (final section in sectionKeys.entries) {
        final part = readPart(entry[section.key]);
        if (part.length != section.value.length ||
            section.value.any((key) => part[key] is! List)) {
          throw const ProjectArchiveException('工程分区内容无效');
        }
        for (final key in section.value) {
          book[key] = part[key];
        }
      }
      book['chapters'] = [
        for (final path in entry['chapters'] as List) readPart(path),
      ];
      books.add(book);
    }
    if (descriptions.keys.any((path) => !referencedFiles.contains(path))) {
      throw const ProjectArchiveException('工程包含未使用的分文件');
    }
    return {'profile': profile, 'books': books};
  }

  static ProjectArchiveData _decodeLegacy(Uint8List bytes) {
    try {
      final payload = _jsonMap(bytes, '旧版工程');
      final formatName = payload['format'];
      final isCollection = formatName == 'snss';
      if (!isCollection && formatName != 'sns' ||
          payload['formatVersion'] != 1) {
        throw const ProjectArchiveException('旧版工程格式不受支持');
      }
      final library = payload['library'];
      final books = isCollection
          ? _booksFromContent(
              library as Map<String, dynamic>,
              isCollection: true,
            )
          : _booksFromContent({
              'books': [payload['book']],
            }, isCollection: false);
      for (final book in books) {
        for (final chapter in book.chapters) {
          chapter.images.clear();
        }
      }
      final profileJson = isCollection
          ? (library as Map<String, dynamic>)['profile']
          : payload['profile'];
      final profile = WriterProfile.fromJson(
        profileJson is Map<String, dynamic> ? profileJson : {},
      )..avatarPath = null;
      return ProjectArchiveData(
        isCollection: isCollection,
        books: books,
        profile: profile,
        covers: const {},
        coverExtensions: const {},
        avatar: null,
        avatarExtension: null,
        isLegacy: true,
      );
    } on ProjectArchiveException {
      rethrow;
    } on Object {
      throw const ProjectArchiveException('旧版工程文件损坏或格式不受支持');
    }
  }

  static List<Book> _booksFromContent(
    Map<String, dynamic> content, {
    required bool isCollection,
  }) {
    final list = content['books'];
    if (list is! List || list.isEmpty || !isCollection && list.length != 1) {
      throw const ProjectArchiveException('工程内没有有效作品');
    }
    if (list.length > 1000) {
      throw const ProjectArchiveException('工程包含过多作品');
    }
    final books = <Book>[];
    final ids = <String>{};
    for (final item in list) {
      if (item is! Map<String, dynamic>) {
        throw const ProjectArchiveException('工程作品数据无效');
      }
      final book = Book.fromJson(item)..coverPath = null;
      if (book.id.isEmpty || !ids.add(book.id)) {
        throw const ProjectArchiveException('工程作品 ID 无效或重复');
      }
      books.add(book);
    }
    return books;
  }

  static Future<Uint8List> _readAsset(String path, String label) async {
    try {
      final file = File(path);
      final size = await file.length();
      if (size > maxAssetBytes) {
        throw ProjectArchiveException('$label 超过 32 MB');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxAssetBytes) {
        throw ProjectArchiveException('$label 超过 32 MB');
      }
      return bytes;
    } on ProjectArchiveException {
      rethrow;
    } on FileSystemException {
      throw ProjectArchiveException('无法读取$label，请重新选择图片后再导出');
    }
  }

  static Uint8List _entry(
    Map<String, ArchiveFile> files,
    String path,
    int maxBytes,
  ) {
    final file = files[path];
    if (file == null || file.size > maxBytes) {
      throw ProjectArchiveException('工程条目缺失或过大：$path');
    }
    final bytes = file.readBytes();
    if (bytes == null || bytes.length > maxBytes) {
      throw ProjectArchiveException('工程条目损坏：$path');
    }
    return bytes;
  }

  static Map<String, dynamic> _jsonMap(Uint8List bytes, String label) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw ProjectArchiveException('$label格式无效');
    }
    return value;
  }

  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  static String _imageExtension(String path) {
    final name = path.toLowerCase().split(RegExp(r'[/\\]')).last;
    final extension = name.contains('.') ? name.split('.').last : '';
    return RegExp(r'^(png|jpg|jpeg|webp)$').hasMatch(extension)
        ? extension
        : 'bin';
  }
}

ProjectArchiveData decodeProjectArchive(Uint8List bytes) =>
    ProjectArchive.decode(bytes);
