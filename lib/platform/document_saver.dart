import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum DocumentSaveStatus { saved, cancelled, failed }

enum DirectoryLinkStatus { linked, cancelled, failed, unsupported }

class DirectoryLinkResult {
  const DirectoryLinkResult(this.status, {this.uri, this.message});

  final DirectoryLinkStatus status;
  final String? uri;
  final String? message;
}

class DocumentSaveResult {
  const DocumentSaveResult._(this.status, {this.location, this.message});

  const DocumentSaveResult.saved(String location)
    : this._(DocumentSaveStatus.saved, location: location);

  const DocumentSaveResult.cancelled() : this._(DocumentSaveStatus.cancelled);

  const DocumentSaveResult.failed(String message)
    : this._(DocumentSaveStatus.failed, message: message);

  final DocumentSaveStatus status;
  final String? location;
  final String? message;
}

abstract interface class DocumentSaver {
  Future<DocumentSaveResult> save({
    required Uint8List bytes,
    required String suggestedName,
    required String mimeType,
    required List<String> extensions,
  });
}

class SystemDocumentSaver implements DocumentSaver {
  static const _channel = MethodChannel('com.silent07137.yejian/document');

  @override
  Future<DocumentSaveResult> save({
    required Uint8List bytes,
    required String suggestedName,
    required String mimeType,
    required List<String> extensions,
  }) async {
    try {
      if (Platform.isAndroid) {
        return await _saveOnAndroid(
          bytes: bytes,
          suggestedName: suggestedName,
          mimeType: mimeType,
        );
      }
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(
            label: extensions.join('/').toUpperCase(),
            extensions: extensions,
          ),
        ],
      );
      if (location == null) return const DocumentSaveResult.cancelled();
      final file = XFile.fromData(
        bytes,
        mimeType: mimeType,
        name: suggestedName,
      );
      await file.saveTo(location.path);
      return DocumentSaveResult.saved(location.path);
    } on PlatformException catch (error) {
      return DocumentSaveResult.failed(error.message ?? '系统文件保存失败');
    } on FileSystemException {
      return const DocumentSaveResult.failed('无法写入所选位置，请检查空间或权限');
    } on UnsupportedError {
      return const DocumentSaveResult.failed('当前平台暂不支持此保存方式');
    }
  }

  Future<DocumentSaveResult> _saveOnAndroid({
    required Uint8List bytes,
    required String suggestedName,
    required String mimeType,
  }) async {
    final tempRoot = await getTemporaryDirectory();
    final directory = Directory(
      '${tempRoot.path}${Platform.pathSeparator}yejian-exports',
    );
    await directory.create(recursive: true);
    final source = File(
      '${directory.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}-$suggestedName',
    );
    await source.writeAsBytes(bytes, flush: true);
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'saveDocument',
        {
          'sourcePath': source.path,
          'name': suggestedName,
          'mimeType': mimeType,
        },
      );
      final status = response?['status'];
      if (status == 'saved') {
        return DocumentSaveResult.saved(
          response?['name'] ?? response?['uri'] ?? '系统文档',
        );
      }
      if (status == 'cancelled') return const DocumentSaveResult.cancelled();
      return DocumentSaveResult.failed(response?['message'] ?? '系统没有完成文件保存');
    } finally {
      if (await source.exists()) await source.delete();
    }
  }
}

class AndroidExportDirectory {
  static const _channel = MethodChannel('com.silent07137.yejian/document');

  static Future<String?> linkedUri() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getLinkedExportDirectory');
    } on PlatformException {
      return null;
    }
  }

  static Future<DirectoryLinkResult> link() async {
    if (!Platform.isAndroid) {
      return const DirectoryLinkResult(DirectoryLinkStatus.unsupported);
    }
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'linkExportDirectory',
      );
      return switch (response?['status']) {
        'linked' => DirectoryLinkResult(
          DirectoryLinkStatus.linked,
          uri: response?['uri'],
        ),
        'cancelled' => const DirectoryLinkResult(DirectoryLinkStatus.cancelled),
        _ => DirectoryLinkResult(
          DirectoryLinkStatus.failed,
          message: response?['message'] ?? '无法关联导出目录',
        ),
      };
    } on PlatformException catch (error) {
      return DirectoryLinkResult(
        DirectoryLinkStatus.failed,
        message: error.message ?? '无法关联导出目录',
      );
    }
  }

  static Future<void> clear() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('clearLinkedExportDirectory');
  }
}
