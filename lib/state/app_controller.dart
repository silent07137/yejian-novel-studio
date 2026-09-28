import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../ai/ai_service.dart';
import '../ai/ai_history.dart';
import '../data/local_store.dart';
import '../domain/entity_id.dart';
import '../domain/chapter_markdown.dart';
import '../domain/project_archive.dart';
import '../models/library_data.dart';
import '../platform/document_saver.dart';

enum WorkspacePage {
  home,
  bookOverview,
  writing,
  characters,
  timeline,
  export,
  settings,
  appSettings,
  aiSettings,
  aiHistory,
  about,
  profile,
}

enum SaveState { saved, saving, failed }

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.data,
    DocumentSaver? documentSaver,
    this.projectAssetDirectory,
    AiSettingsStore? aiSettingsStore,
    AiHistoryStore? aiHistoryStore,
    AiTextService? aiTextService,
  }) : documentSaver = documentSaver ?? SystemDocumentSaver(),
       aiSettingsStore = aiSettingsStore ?? const SecureAiSettingsStore(),
       aiHistoryStore = aiHistoryStore ?? FileAiHistoryStore(),
       aiTextService = aiTextService ?? const AiTextService() {
    selectedBookId =
        data.activeBookId ?? (data.books.isEmpty ? null : data.books.first.id);
    selectedChapterId = activeBook?.chapters.firstOrNull?.id;
  }

  final DataStore store;
  final DocumentSaver documentSaver;
  final AiSettingsStore aiSettingsStore;
  final AiHistoryStore aiHistoryStore;
  final AiTextService aiTextService;
  final Directory? projectAssetDirectory;
  LibraryData data;
  WorkspacePage page = WorkspacePage.home;
  SaveState saveState = SaveState.saved;
  String? selectedBookId;
  String? selectedChapterId;
  String? loadedFontFamily;
  Timer? _saveTimer;
  bool _disposed = false;
  final List<WorkspacePage> _pageHistory = [];
  final Map<String, double> _editorScrollOffsets = {};
  final Map<String, int> _pageSelections = {};

  Book? get activeBook {
    for (final book in data.books) {
      if (book.id == selectedBookId) return book;
    }
    return data.books.firstOrNull;
  }

  Chapter? get activeChapter {
    final book = activeBook;
    if (book == null) return null;
    for (final chapter in book.chapters) {
      if (chapter.id == selectedChapterId) return chapter;
    }
    return book.chapters.firstOrNull;
  }

  String get pageTitle => switch (page) {
    WorkspacePage.home => '书架',
    WorkspacePage.bookOverview => activeBook?.title ?? '作品',
    WorkspacePage.writing => activeBook?.title ?? '写作',
    WorkspacePage.characters => '${activeBook?.title ?? '本书'} · 设定',
    WorkspacePage.timeline => '${activeBook?.title ?? '本书'} · 情节',
    WorkspacePage.export => '导出工程',
    WorkspacePage.settings => '设置',
    WorkspacePage.appSettings => '应用设置',
    WorkspacePage.aiSettings => 'AI 助手',
    WorkspacePage.aiHistory => '生成历史',
    WorkspacePage.about => '关于应用',
    WorkspacePage.profile => '个人中心',
  };

  bool get isBookWorkspace => switch (page) {
    WorkspacePage.writing ||
    WorkspacePage.characters ||
    WorkspacePage.timeline ||
    WorkspacePage.export => true,
    _ => false,
  };

  bool get isBookContext => switch (page) {
    WorkspacePage.bookOverview ||
    WorkspacePage.writing ||
    WorkspacePage.characters ||
    WorkspacePage.timeline ||
    WorkspacePage.export => true,
    _ => false,
  };

  bool get isAppNavigationContext => switch (page) {
    WorkspacePage.home ||
    WorkspacePage.settings ||
    WorkspacePage.appSettings ||
    WorkspacePage.aiSettings ||
    WorkspacePage.aiHistory ||
    WorkspacePage.about ||
    WorkspacePage.profile => true,
    _ => false,
  };

  bool get canGoBack =>
      _pageHistory.isNotEmpty ||
      (page != WorkspacePage.home && page != WorkspacePage.settings);

  double editorScrollOffset(String chapterId) =>
      _editorScrollOffsets[chapterId] ?? 0;

  void saveEditorScrollOffset(String chapterId, double offset) {
    _editorScrollOffsets[chapterId] = offset;
  }

  int pageSelection(String key) => _pageSelections[key] ?? 0;

  void savePageSelection(String key, int value) {
    _pageSelections[key] = value;
  }

  void navigate(WorkspacePage value) {
    if (page == value) return;
    _pageHistory.clear();
    page = value;
    notifyListeners();
  }

  void navigateBook(WorkspacePage value) {
    if (page == value) return;
    _pageHistory.clear();
    page = value;
    notifyListeners();
  }

  void openSubpage(WorkspacePage value) {
    if (page == value) return;
    _pageHistory.add(page);
    page = value;
    notifyListeners();
  }

  void goBack() {
    if (_pageHistory.isNotEmpty) {
      page = _pageHistory.removeLast();
      notifyListeners();
      return;
    }
    if (isBookWorkspace) {
      _pageHistory.clear();
      page = WorkspacePage.bookOverview;
      notifyListeners();
      return;
    }
    if (page == WorkspacePage.appSettings ||
        page == WorkspacePage.aiSettings ||
        page == WorkspacePage.aiHistory ||
        page == WorkspacePage.about ||
        page == WorkspacePage.profile) {
      page = _pageHistory.isEmpty
          ? WorkspacePage.settings
          : _pageHistory.removeLast();
      notifyListeners();
      return;
    }
    page = _pageHistory.isEmpty
        ? WorkspacePage.home
        : _pageHistory.removeLast();
    notifyListeners();
  }

  void completeProfileSetup(String value) {
    final name = value.trim();
    data.profile.authorName = name.isEmpty ? '未命名' : name;
    data.profile.setupComplete = true;
    _queueSave();
    notifyListeners();
  }

  void enterEmptyLibrary() {
    data.profile.setupComplete = true;
    page = WorkspacePage.home;
    _queueSave();
    notifyListeners();
  }

  void startFirstBook(String title) {
    data.profile.setupComplete = true;
    createBook(title);
  }

  void installSampleProject() {
    final sample = LibraryData.seeded(profileSetupComplete: true);
    data.profile.setupComplete = true;
    data.books.addAll(sample.books);
    data.activeBookId = sample.activeBookId;
    selectedBookId = sample.activeBookId;
    selectedChapterId = activeBook?.chapters.firstOrNull?.id;
    page = WorkspacePage.home;
    _queueSave();
    notifyListeners();
  }

  void openBook(String bookId) {
    selectedBookId = bookId;
    data.activeBookId = bookId;
    final book = activeBook;
    selectedChapterId = book?.chapters.firstOrNull?.id;
    _pageHistory.clear();
    page = WorkspacePage.bookOverview;
    _queueSave();
    notifyListeners();
  }

  void continueWriting() {
    if (activeBook == null) return;
    _pageHistory
      ..clear()
      ..add(WorkspacePage.bookOverview);
    page = WorkspacePage.writing;
    notifyListeners();
  }

  void openChapter(String chapterId) {
    selectedChapterId = chapterId;
    continueWriting();
  }

  void updateActiveBookInfo({
    required String title,
    required String description,
  }) {
    final book = activeBook;
    if (book == null) return;
    updateBookInfo(book.id, title: title, description: description);
  }

  void updateBookInfo(
    String bookId, {
    required String title,
    required String description,
  }) {
    final book = data.books.where((item) => item.id == bookId).firstOrNull;
    if (book == null) return;
    book.title = title.trim().isEmpty ? '未命名作品' : title.trim();
    book.description = description.trim();
    book.updatedAt = DateTime.now();
    _queueSave();
    notifyListeners();
  }

  void deleteBook(String bookId) {
    if (!data.books.any((book) => book.id == bookId)) return;
    data.books.removeWhere((book) => book.id == bookId);
    if (selectedBookId == bookId || data.activeBookId == bookId) {
      selectedBookId = data.books.firstOrNull?.id;
      data.activeBookId = selectedBookId;
      selectedChapterId = activeBook?.chapters.firstOrNull?.id;
      _pageHistory.clear();
      page = WorkspacePage.home;
    }
    _queueSave();
    notifyListeners();
  }

  void selectChapter(String chapterId) {
    selectedChapterId = chapterId;
    notifyListeners();
  }

  void createBook(String title) {
    final bookId = newEntityId('book');
    final book = Book(
      id: bookId,
      title: title.trim().isEmpty ? '未命名作品' : title.trim(),
      tracks: [StoryTrack(id: newEntityId('track'), name: '故事主线')],
    );
    data.books.add(book);
    selectedBookId = book.id;
    selectedChapterId = null;
    data.activeBookId = book.id;
    _pageHistory.clear();
    page = WorkspacePage.bookOverview;
    _queueSave();
    notifyListeners();
  }

  void createVolume(String title) {
    final book = activeBook;
    if (book == null) return;
    book.volumes.add(
      Volume(
        id: newEntityId('volume'),
        title: title.trim().isEmpty ? '未命名分卷' : title.trim(),
        sortIndex: book.volumes.length,
      ),
    );
    _touchBook();
  }

  void updateVolume(String volumeId, {required String title, String? summary}) {
    final volume = activeBook?.volumes
        .where((item) => item.id == volumeId)
        .firstOrNull;
    if (volume == null) return;
    volume.title = title.trim().isEmpty ? '未命名分卷' : title.trim();
    if (summary != null) volume.summary = summary.trim();
    _touchBook();
  }

  void deleteDirectoryItems({
    Set<String> chapterIds = const {},
    Set<String> volumeIds = const {},
    bool deleteVolumeChapters = false,
  }) {
    final book = activeBook;
    if (book == null) return;
    final deletingChapters = <String>{
      ...chapterIds,
      if (deleteVolumeChapters)
        ...book.chapters
            .where((chapter) => volumeIds.contains(chapter.volumeId))
            .map((chapter) => chapter.id),
    };
    book.volumes.removeWhere((volume) => volumeIds.contains(volume.id));
    book.chapters.removeWhere(
      (chapter) => deletingChapters.contains(chapter.id),
    );
    for (final chapter in book.chapters) {
      if (volumeIds.contains(chapter.volumeId)) chapter.volumeId = null;
    }
    for (final event in book.events) {
      if (deletingChapters.contains(event.chapterId)) event.chapterId = null;
    }
    if (deletingChapters.contains(selectedChapterId)) {
      selectedChapterId = book.chapters.firstOrNull?.id;
    }
    for (var index = 0; index < book.volumes.length; index++) {
      book.volumes[index].sortIndex = index;
    }
    _normalizeChapterOrder(book);
    _touchBook();
  }

  void updateChapterSettings(
    String chapterId, {
    required String title,
    required String summary,
    required String status,
    required String? volumeId,
    required bool exportEnabled,
  }) {
    final book = activeBook;
    final chapter = _chapterById(chapterId);
    if (book == null || chapter == null) return;
    chapter.title = title.trim().isEmpty ? '未命名章节' : title.trim();
    chapter.summary = summary.trim();
    chapter.status = ['草稿', '修订中', '定稿'].contains(status) ? status : '草稿';
    chapter.volumeId = book.volumes.any((volume) => volume.id == volumeId)
        ? volumeId
        : null;
    chapter.exportEnabled = exportEnabled;
    chapter.updatedAt = DateTime.now();
    _touchBook();
  }

  void createChapter({String? volumeId}) {
    final book = activeBook;
    if (book == null) return;
    final chapter = Chapter(
      id: newEntityId('chapter'),
      title: '未命名章节',
      volumeId: volumeId,
      sortIndex: book.chapters.length,
    );
    book.chapters.add(chapter);
    book.updatedAt = DateTime.now();
    selectedChapterId = chapter.id;
    _queueSave();
    notifyListeners();
  }

  void renameChapter(String chapterId, String title) {
    final chapter = _chapterById(chapterId);
    if (chapter == null) return;
    chapter.title = title.trim().isEmpty ? '未命名章节' : title.trim();
    chapter.updatedAt = DateTime.now();
    _touchBook();
  }

  void duplicateChapter(String chapterId) {
    final book = activeBook;
    final source = _chapterById(chapterId);
    if (book == null || source == null) return;
    final index = book.chapters.indexOf(source);
    var duplicatedBody = source.body;
    final duplicatedImages = <ChapterImage>[];
    for (final image in source.images) {
      final newId = newEntityId('image');
      duplicatedBody = duplicatedBody.replaceAll(
        'yejian-image:${image.id}',
        'yejian-image:$newId',
      );
      duplicatedImages.add(
        ChapterImage(id: newId, path: image.path, alt: image.alt),
      );
    }
    final copy = Chapter(
      id: newEntityId('chapter'),
      title: '${source.title}（副本）',
      volumeId: source.volumeId,
      body: duplicatedBody,
      summary: source.summary,
      status: '草稿',
      exportEnabled: source.exportEnabled,
      sortIndex: index + 1,
      markers: [
        for (final marker in source.markers)
          ChapterMarker(
            id: newEntityId('marker'),
            kind: marker.kind,
            start: marker.start,
            end: marker.end,
            quote: marker.quote,
            note: marker.note,
            referenceId: marker.referenceId,
          ),
      ],
      images: duplicatedImages,
    );
    book.chapters.insert(index + 1, copy);
    selectedChapterId = copy.id;
    _normalizeChapterOrder(book);
    _touchBook();
  }

  void moveChapter(String chapterId, int delta) {
    final book = activeBook;
    final chapter = _chapterById(chapterId);
    if (book == null || chapter == null) return;
    final siblings = book.chapters
        .where((item) => item.volumeId == chapter.volumeId)
        .toList();
    final siblingIndex = siblings.indexOf(chapter);
    final targetIndex = siblingIndex + delta;
    if (targetIndex < 0 || targetIndex >= siblings.length) return;
    final index = book.chapters.indexOf(chapter);
    final target = book.chapters.indexOf(siblings[targetIndex]);
    book.chapters[index] = siblings[targetIndex];
    book.chapters[target] = chapter;
    _normalizeChapterOrder(book);
    _touchBook();
  }

  void moveChapterToVolume(String chapterId, String? volumeId) {
    final chapter = _chapterById(chapterId);
    if (chapter == null) return;
    chapter.volumeId = volumeId;
    chapter.updatedAt = DateTime.now();
    _touchBook();
  }

  void setChapterStatus(String chapterId, String status) {
    final chapter = _chapterById(chapterId);
    if (chapter == null) return;
    chapter.status = status;
    chapter.updatedAt = DateTime.now();
    _touchBook();
  }

  void toggleChapterExport(String chapterId) {
    final chapter = _chapterById(chapterId);
    if (chapter == null) return;
    chapter.exportEnabled = !chapter.exportEnabled;
    chapter.updatedAt = DateTime.now();
    _touchBook();
  }

  void deleteChapter(String chapterId) {
    if (_chapterById(chapterId) == null) return;
    deleteDirectoryItems(chapterIds: {chapterId});
  }

  Chapter? _chapterById(String chapterId) {
    final book = activeBook;
    if (book == null) return null;
    for (final chapter in book.chapters) {
      if (chapter.id == chapterId) return chapter;
    }
    return null;
  }

  void _normalizeChapterOrder(Book book) {
    for (var index = 0; index < book.chapters.length; index++) {
      book.chapters[index].sortIndex = index;
    }
  }

  void createRole(String name) {
    final book = activeBook;
    if (book == null) return;
    book.roles.add(RoleCard(id: newEntityId('role'), name: name));
    book.updatedAt = DateTime.now();
    _queueSave();
    notifyListeners();
  }

  RoleCard newRoleDraft() => RoleCard(id: newEntityId('role'), name: '');

  void saveRole(RoleCard role) {
    final book = activeBook;
    if (book == null || role.name.trim().isEmpty) return;
    final sharedFields = role.customFields
        .where((field) => field.scope == 'book')
        .toList();
    for (final field in sharedFields) {
      final fieldIndex = book.roleFields.indexWhere(
        (item) => item.id == field.id,
      );
      if (fieldIndex < 0) {
        book.roleFields.add(field);
      } else {
        book.roleFields[fieldIndex] = field;
      }
    }
    role.customFields.removeWhere((field) => field.scope == 'book');
    final index = book.roles.indexWhere((item) => item.id == role.id);
    if (index < 0) {
      book.roles.add(role);
    } else {
      book.roles[index] = role;
    }
    _touchBook();
  }

  void reorderRoles(int oldIndex, int newIndex) {
    final book = activeBook;
    if (book == null || oldIndex < 0 || oldIndex >= book.roles.length) return;
    if (newIndex < 0 || newIndex >= book.roles.length || newIndex == oldIndex) {
      return;
    }
    book.roles.insert(newIndex, book.roles.removeAt(oldIndex));
    _touchBook();
  }

  void deleteRole(String roleId) {
    final book = activeBook;
    if (book == null) return;
    book.roles.removeWhere((item) => item.id == roleId);
    _touchBook();
  }

  void createWorld(String title, String type) {
    final book = activeBook;
    if (book == null) return;
    book.worlds.add(
      WorldCard(
        id: newEntityId('world'),
        title: title.trim().isEmpty ? '未命名设定' : title.trim(),
        type: type,
      ),
    );
    _touchBook();
  }

  WorldCard newWorldDraft() =>
      WorldCard(id: newEntityId('world'), title: '', type: '地点');

  void saveWorld(WorldCard world) {
    final book = activeBook;
    if (book == null || world.title.trim().isEmpty) return;
    final sharedFields = world.customFields
        .where((field) => field.scope == 'book' || field.scope == 'type')
        .toList();
    for (final field in sharedFields) {
      final fieldIndex = book.worldFields.indexWhere(
        (item) => item.id == field.id,
      );
      if (fieldIndex < 0) {
        book.worldFields.add(field);
      } else {
        book.worldFields[fieldIndex] = field;
      }
    }
    world.customFields.removeWhere(
      (field) => field.scope == 'book' || field.scope == 'type',
    );
    final index = book.worlds.indexWhere((item) => item.id == world.id);
    if (index < 0) {
      book.worlds.add(world);
    } else {
      book.worlds[index] = world;
    }
    _touchBook();
  }

  void reorderWorlds(int oldIndex, int newIndex) {
    final book = activeBook;
    if (book == null || oldIndex < 0 || oldIndex >= book.worlds.length) return;
    if (newIndex < 0 ||
        newIndex >= book.worlds.length ||
        newIndex == oldIndex) {
      return;
    }
    book.worlds.insert(newIndex, book.worlds.removeAt(oldIndex));
    _touchBook();
  }

  void deleteWorld(String worldId) {
    final book = activeBook;
    if (book == null) return;
    book.worlds.removeWhere((item) => item.id == worldId);
    _touchBook();
  }

  void updateTemplateField({
    required bool role,
    required bool base,
    required CustomFieldDefinition field,
  }) {
    final book = activeBook;
    if (book == null) return;
    final fields = role
        ? (base ? book.roleBaseFields : book.roleFields)
        : (base ? book.worldBaseFields : book.worldFields);
    final index = fields.indexWhere((item) => item.id == field.id);
    if (index < 0) {
      fields.add(field);
    } else {
      fields[index] = field;
    }
    _touchBook();
  }

  void addTemplateField({
    required bool role,
    required String name,
    required String type,
    List<String> options = const [],
  }) {
    final book = activeBook;
    if (book == null || name.trim().isEmpty) return;
    final fields = role ? book.roleFields : book.worldFields;
    fields.add(
      CustomFieldDefinition(
        id: newEntityId(role ? 'role-field' : 'world-field'),
        name: name.trim(),
        type: type,
        scope: 'book',
        options: options,
      ),
    );
    _touchBook();
  }

  void deleteTemplateField({required bool role, required String fieldId}) {
    final book = activeBook;
    if (book == null) return;
    final fields = role ? book.roleFields : book.worldFields;
    final field = fields.where((item) => item.id == fieldId).firstOrNull;
    if (field == null) return;
    field
      ..enabled = false
      ..deleted = true;
    _touchBook();
  }

  void moveTemplateField({
    required bool role,
    required bool base,
    required String fieldId,
    required int delta,
  }) {
    final book = activeBook;
    if (book == null) return;
    final fields = role
        ? (base ? book.roleBaseFields : book.roleFields)
        : (base ? book.worldBaseFields : book.worldFields);
    final index = fields.indexWhere((item) => item.id == fieldId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= fields.length) return;
    final field = fields.removeAt(index);
    fields.insert(target, field);
    _touchBook();
  }

  void createTrack(String name, String type) {
    final book = activeBook;
    if (book == null) return;
    const colors = ['purple', 'blue', 'sage', 'amber'];
    book.tracks.add(
      StoryTrack(
        id: newEntityId('track'),
        name: name.trim().isEmpty ? '未命名时间线' : name.trim(),
        type: type,
        color: colors[book.tracks.length % colors.length],
      ),
    );
    _touchBook();
  }

  void updateTrack(
    String trackId, {
    required String name,
    required String type,
  }) {
    final book = activeBook;
    if (book == null) return;
    final track = book.tracks.where((item) => item.id == trackId).firstOrNull;
    if (track == null) return;
    track
      ..name = name.trim().isEmpty ? '未命名时间线' : name.trim()
      ..type = type;
    _touchBook();
  }

  void deleteTrack(String trackId) {
    final book = activeBook;
    if (book == null || book.tracks.length <= 1) return;
    book.tracks.removeWhere((track) => track.id == trackId);
    final fallback = book.tracks.first.id;
    for (final event in book.events) {
      event.trackIds.remove(trackId);
      if (event.trackIds.isEmpty) event.trackIds.add(fallback);
    }
    _touchBook();
  }

  void createEvent(
    String title, {
    String storyDate = '时间未定',
    String description = '',
    String? chapterId,
    String persons = '',
    List<String>? roleIds,
    String group = '尚未分组',
    List<String>? trackIds,
    int? timeLevel,
    int? sameTimeOrder,
    int? flowLevel,
  }) {
    final book = activeBook;
    if (book == null) return;
    if (book.tracks.isEmpty) {
      book.tracks.add(StoryTrack(id: newEntityId('track'), name: '故事主线'));
    }
    final selectedRoleIds = roleIds ?? const <String>[];
    final selectedRoleNames = book.roles
        .where((role) => selectedRoleIds.contains(role.id))
        .map((role) => role.name)
        .join('、');
    final level = timeLevel != null && timeLevel > 0
        ? timeLevel
        : book.events.fold<int>(
                0,
                (max, event) => event.timeLevel > max ? event.timeLevel : max,
              ) +
              1;
    final withinLevel = sameTimeOrder != null && sameTimeOrder > 0
        ? sameTimeOrder
        : book.events
                  .where((event) => event.timeLevel == level)
                  .fold<int>(
                    0,
                    (max, event) =>
                        event.sameTimeOrder > max ? event.sameTimeOrder : max,
                  ) +
              1;
    book.events.add(
      StoryEvent(
        id: newEntityId('event'),
        title: title,
        storyDate: storyDate.trim().isEmpty ? '时间未定' : storyDate.trim(),
        timeLevel: level,
        sameTimeOrder: withinLevel,
        order: level.toDouble(),
        description: description.trim(),
        chapterId: chapterId ?? selectedChapterId,
        persons: selectedRoleNames.isEmpty ? persons : selectedRoleNames,
        roleIds: selectedRoleIds,
        group: group.trim().isEmpty ? '尚未分组' : group.trim(),
        flowLevel:
            flowLevel ??
            (book.events.isEmpty
                ? 0
                : book.events
                          .map((event) => event.flowLevel)
                          .reduce((a, b) => a > b ? a : b) +
                      1),
        trackIds: trackIds?.isNotEmpty == true
            ? trackIds
            : [book.tracks.first.id],
      ),
    );
    _touchBook();
  }

  void updateEvent(StoryEvent updated) {
    final book = activeBook;
    if (book == null ||
        updated.title.trim().isEmpty ||
        updated.timeLevel < 1 ||
        updated.sameTimeOrder < 1) {
      return;
    }
    final index = book.events.indexWhere((event) => event.id == updated.id);
    if (index < 0) return;
    book.events[index] = updated;
    _touchBook();
  }

  void deleteEvent(String eventId) {
    final book = activeBook;
    if (book == null) return;
    book.events.removeWhere((event) => event.id == eventId);
    book.storyLinks.removeWhere(
      (link) => link.fromEventId == eventId || link.toEventId == eventId,
    );
    _touchBook();
  }

  void createStoryLink(String fromId, String toId, String label) {
    final book = activeBook;
    if (book == null || fromId == toId) return;
    final exists = book.storyLinks.any(
      (link) => link.fromEventId == fromId && link.toEventId == toId,
    );
    if (exists) return;
    book.storyLinks.add(
      StoryLink(
        id: newEntityId('link'),
        fromEventId: fromId,
        toEventId: toId,
        label: label.trim().isEmpty ? '关联' : label.trim(),
      ),
    );
    _touchBook();
  }

  String? createClue(
    String title,
    String description, {
    String? originChapterId,
    String? plannedChapterId,
  }) {
    final book = activeBook;
    if (book == null) return null;
    final clueId = newEntityId('clue');
    book.clues.add(
      PlotClue(
        id: clueId,
        title: title.trim().isEmpty ? '未命名伏笔' : title.trim(),
        description: description.trim(),
        originChapterId: originChapterId,
        plannedChapterId: plannedChapterId,
      ),
    );
    _touchBook();
    return clueId;
  }

  void deleteClue(String clueId) {
    final book = activeBook;
    if (book == null) return;
    book.clues.removeWhere((clue) => clue.id == clueId);
    for (final chapter in book.chapters) {
      chapter.markers.removeWhere(
        (marker) => marker.kind == 'clue' && marker.referenceId == clueId,
      );
    }
    _touchBook();
  }

  String? createNote(String body) {
    final book = activeBook;
    if (book == null || body.trim().isEmpty) return null;
    final noteId = newEntityId('note');
    book.notes.insert(0, IdeaNote(id: noteId, body: body.trim()));
    _touchBook();
    return noteId;
  }

  void deleteNote(String noteId) {
    final book = activeBook;
    if (book == null) return;
    book.notes.removeWhere((note) => note.id == noteId);
    for (final chapter in book.chapters) {
      chapter.markers.removeWhere(
        (marker) => marker.kind == 'idea' && marker.referenceId == noteId,
      );
    }
    _touchBook();
  }

  ChapterMarker? addChapterMarker({
    required int start,
    required int end,
    required String kind,
    required String note,
    String? referenceId,
  }) {
    final chapter = activeChapter;
    final book = activeBook;
    if (chapter == null ||
        book == null ||
        start < 0 ||
        end > chapter.body.length ||
        start >= end) {
      return null;
    }
    if (kind == 'clue' && !book.clues.any((clue) => clue.id == referenceId)) {
      return null;
    }
    if (kind == 'idea' && !book.notes.any((idea) => idea.id == referenceId)) {
      return null;
    }
    if (kind != 'revision' && kind != 'clue' && kind != 'idea') return null;
    final marker = ChapterMarker(
      id: newEntityId('marker'),
      kind: kind,
      start: start,
      end: end,
      quote: chapter.body.substring(start, end),
      note: note.trim(),
      referenceId: referenceId,
    );
    chapter.markers.add(marker);
    _touchBook();
    return marker;
  }

  void updateChapterMarker(String markerId, String note) {
    final chapter = activeChapter;
    if (chapter == null) return;
    for (final marker in chapter.markers) {
      if (marker.id == markerId) {
        marker.note = note.trim();
        _touchBook();
        return;
      }
    }
  }

  void deleteChapterMarker(String markerId) {
    final chapter = activeChapter;
    if (chapter == null) return;
    chapter.markers.removeWhere((marker) => marker.id == markerId);
    _touchBook();
  }

  void updateChapterTitle(String value) {
    final chapter = activeChapter;
    if (chapter == null) return;
    chapter.title = value;
    _touchBook();
  }

  void updateChapterBody(String value) {
    final chapter = activeChapter;
    if (chapter == null) return;
    if (chapter.body == value) return;
    _relocateChapterMarkers(chapter.markers, chapter.body, value);
    chapter.body = value;
    chapter.updatedAt = DateTime.now();
    _touchBook();
  }

  Future<ImageInsertion> insertChapterImageBytes(
    Uint8List bytes, {
    required int offset,
    String alt = '',
  }) async {
    final chapter = activeChapter;
    if (chapter == null) throw StateError('请先选择章节');
    if (bytes.length > ProjectArchive.maxAssetBytes) {
      throw StateError('图片超过 32 MB，请选择较小的图片');
    }
    final extension = _imageExtensionFromBytes(bytes);
    if (extension == null) {
      throw StateError('仅支持 PNG、JPEG 和 WebP 图片');
    }
    final image = ChapterImage(
      id: newEntityId('image'),
      path: '',
      alt: alt.trim(),
    );
    final support =
        projectAssetDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}yejian'
      '${Platform.pathSeparator}chapter-images',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${image.id}.$extension',
    );
    var imageAdded = false;
    try {
      await file.writeAsBytes(bytes, flush: true);
      if (activeChapter?.id != chapter.id) {
        throw StateError('当前章节已切换，请重新插入图片');
      }
      image.path = file.path;
      final insertion = insertChapterImageReference(
        chapter.body,
        offset,
        image,
      );
      chapter.images.add(image);
      imageAdded = true;
      updateChapterBody(insertion.body);
      return insertion;
    } on Object {
      if (imageAdded) chapter.images.remove(image);
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  String? _imageExtensionFromBytes(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    return null;
  }

  void _relocateChapterMarkers(
    List<ChapterMarker> markers,
    String oldText,
    String newText,
  ) {
    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            newText.codeUnitAt(newText.length - suffix - 1)) {
      suffix++;
    }
    final oldChangeEnd = oldText.length - suffix;
    final delta = newText.length - oldText.length;
    for (final marker in markers) {
      if (marker.end <= prefix) continue;
      if (marker.start >= oldChangeEnd) {
        marker.start += delta;
        marker.end += delta;
        continue;
      }
      // Keep the bookmark near the edited passage even when its quote changes.
      final start = marker.start <= prefix ? marker.start : prefix;
      marker.start = start.clamp(0, newText.length);
      marker.end = (marker.end + delta).clamp(marker.start, newText.length);
    }
  }

  void updateAuthorName(String value) {
    data.profile.authorName = value.trim().isEmpty ? '未命名' : value;
    _queueSave();
    notifyListeners();
  }

  void updatePalette(String value) {
    data.settings.palette = value;
    _queueSave();
    notifyListeners();
  }

  void updateAppearanceMode(String value) {
    data.settings.appearanceMode = switch (value) {
      'dark' => 'dark',
      'system' => 'system',
      _ => 'light',
    };
    _queueSave();
    notifyListeners();
  }

  void updateFontSize(double value) {
    data.settings.fontSize = value;
    _queueSave();
    notifyListeners();
  }

  void updateLineHeight(double value) {
    data.settings.lineHeight = value;
    _queueSave();
    notifyListeners();
  }

  Future<void> chooseAvatar() async {
    final image = await _chooseImage();
    if (image == null) return;
    data.profile.avatarPath = image.path;
    _queueSave();
    notifyListeners();
  }

  Future<void> chooseCover(Book book) async {
    final image = await _chooseImage();
    if (image == null) return;
    book.coverPath = image.path;
    book.updatedAt = DateTime.now();
    _queueSave();
    notifyListeners();
  }

  Future<XFile?> _chooseImage() => openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: '图片', extensions: ['jpg', 'jpeg', 'png', 'webp']),
    ],
  );

  Future<void> chooseCustomFont() async {
    final font = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '字体', extensions: ['ttf', 'otf']),
      ],
    );
    if (font == null) return;
    data.settings.customFontPath = font.path;
    await loadConfiguredFont();
    _queueSave();
    notifyListeners();
  }

  Future<void> clearCustomFont() async {
    data.settings.customFontPath = null;
    loadedFontFamily = null;
    _queueSave();
    notifyListeners();
  }

  Future<void> loadConfiguredFont() async {
    final path = data.settings.customFontPath;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    try {
      final bytes = await file.readAsBytes();
      final family = 'YejianCustom${path.hashCode.abs()}';
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      loadedFontFamily = family;
    } on Object {
      loadedFontFamily = null;
    }
  }

  Future<DocumentSaveResult> exportCurrentBookProject() async {
    final book = activeBook;
    if (book == null) {
      return const DocumentSaveResult.failed('当前没有可导出的作品');
    }
    final name = '${_safeFileName(book.title)}.sns';
    try {
      await flush();
      if (saveState == SaveState.failed) {
        return const DocumentSaveResult.failed('作品尚未成功保存，暂不能导出工程');
      }
      final bytes = await ProjectArchive.encode(
        books: [book],
        profile: data.profile,
        isCollection: false,
      );
      return await documentSaver.save(
        bytes: bytes,
        suggestedName: name,
        mimeType: 'application/octet-stream',
        extensions: const ['sns'],
      );
    } on ProjectArchiveException catch (error) {
      return DocumentSaveResult.failed(error.message);
    }
  }

  Future<DocumentSaveResult> exportLibraryProject() async {
    if (data.books.isEmpty) {
      return const DocumentSaveResult.failed('书架中还没有作品');
    }
    try {
      await flush();
      if (saveState == SaveState.failed) {
        return const DocumentSaveResult.failed('作品尚未成功保存，暂不能导出工程');
      }
      final bytes = await ProjectArchive.encode(
        books: data.books,
        profile: data.profile,
        isCollection: true,
      );
      return await documentSaver.save(
        bytes: bytes,
        suggestedName: '页间作品集.snss',
        mimeType: 'application/octet-stream',
        extensions: const ['snss'],
      );
    } on ProjectArchiveException catch (error) {
      return DocumentSaveResult.failed(error.message);
    }
  }

  Future<ProjectArchiveData?> chooseProjectArchive() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '页间工程',
          extensions: ['sns', 'snss'],
          mimeTypes: [
            'application/octet-stream',
            'application/zip',
            'application/json',
          ],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > ProjectArchive.maxArchiveBytes) {
      throw const ProjectArchiveException('工程文件超过 128 MB，拒绝导入');
    }
    return ProjectArchive.decode(await file.readAsBytes(), fileName: file.name);
  }

  Future<int> importProjectArchive(
    ProjectArchiveData project, {
    required bool replaceExisting,
  }) async {
    final incomingIds = project.books.map((book) => book.id).toSet();
    final existingIds = data.books.map((book) => book.id).toSet();
    if (!replaceExisting && incomingIds.any(existingIds.contains)) {
      throw const ProjectArchiveException('工程中有已存在的作品，请确认是否替换');
    }
    await flush();
    if (saveState == SaveState.failed) {
      throw const ProjectArchiveException('当前作品尚未成功保存，已取消导入');
    }
    final candidate = LibraryData.fromJson(data.toJson());
    final createdAssets = <File>[];
    final restoreProfile =
        data.books.isEmpty &&
        data.profile.authorName == '未命名' &&
        data.profile.avatarPath == null;
    try {
      for (final incoming in project.books) {
        final book = Book.fromJson(incoming.toJson());
        if (project.covers[book.id] case final Uint8List cover) {
          book.coverPath = await _storeImportedAsset(
            cover,
            project.coverExtensions[book.id] ?? 'bin',
            createdAssets,
          );
        }
        for (final chapter in book.chapters) {
          for (final image in chapter.images) {
            final bytes = project.chapterImages[image.id];
            if (bytes == null) {
              throw const ProjectArchiveException('工程正文图片缺失，已取消导入');
            }
            image.path = await _storeImportedAsset(
              bytes,
              project.chapterImageExtensions[image.id] ?? 'bin',
              createdAssets,
            );
          }
        }
        final index = candidate.books.indexWhere((item) => item.id == book.id);
        if (index < 0) {
          candidate.books.add(book);
        } else {
          candidate.books[index] = book;
        }
      }
      if (restoreProfile) {
        candidate.profile = WriterProfile.fromJson(project.profile.toJson());
        if (project.avatar case final Uint8List avatar) {
          candidate.profile.avatarPath = await _storeImportedAsset(
            avatar,
            project.avatarExtension ?? 'bin',
            createdAssets,
          );
        }
      }
      candidate.activeBookId ??= project.books.first.id;
      _validateProjectEntityIds(candidate.books);
      await store.save(candidate);
    } on Object {
      for (final asset in createdAssets) {
        if (await asset.exists()) await asset.delete();
      }
      rethrow;
    }
    data = candidate;
    selectedBookId = candidate.activeBookId;
    selectedChapterId = activeBook?.chapters.firstOrNull?.id;
    _pageHistory.clear();
    page = WorkspacePage.home;
    saveState = SaveState.saved;
    notifyListeners();
    return project.books.length;
  }

  Future<String> _storeImportedAsset(
    Uint8List bytes,
    String extension,
    List<File> createdAssets,
  ) async {
    final support =
        projectAssetDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}yejian'
      '${Platform.pathSeparator}imported-assets',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${newEntityId('asset')}.$extension',
    );
    createdAssets.add(file);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _validateProjectEntityIds(List<Book> books) {
    final ids = <String>{};
    void check(String type, String id) {
      if (id.isEmpty || !ids.add('$type:$id')) {
        throw const ProjectArchiveException('工程数据 ID 与现有作品冲突，已取消导入');
      }
    }

    for (final book in books) {
      check('book', book.id);
      for (final item in book.volumes) {
        check('volume', item.id);
      }
      for (final item in book.chapters) {
        check('chapter', item.id);
        for (final marker in item.markers) {
          check('chapter_marker', marker.id);
        }
        for (final image in item.images) {
          check('chapter_image', image.id);
        }
      }
      for (final item in book.roles) {
        check('role', item.id);
      }
      for (final item in book.roleFields) {
        check('role_field', item.id);
      }
      for (final item in book.worlds) {
        check('world', item.id);
      }
      for (final item in book.worldFields) {
        check('world_field', item.id);
      }
      for (final item in book.tracks) {
        check('track', item.id);
      }
      for (final item in book.events) {
        check('event', item.id);
      }
      for (final item in book.storyLinks) {
        check('story_link', item.id);
      }
      for (final item in book.clues) {
        check('clue', item.id);
      }
      for (final item in book.notes) {
        check('note', item.id);
      }
    }
  }

  Future<DocumentSaveResult> exportPlainText() async {
    final book = activeBook;
    if (book == null) {
      return const DocumentSaveResult.failed('当前没有可导出的作品');
    }
    final name = '${_safeFileName(book.title)}.txt';
    return documentSaver.save(
      bytes: Uint8List.fromList(utf8.encode(buildPlainText(book))),
      suggestedName: name,
      mimeType: 'text/plain',
      extensions: const ['txt'],
    );
  }

  Future<DocumentSaveResult> exportMarkdown() async {
    final book = activeBook;
    if (book == null) {
      return const DocumentSaveResult.failed('当前没有可导出的作品');
    }
    final usedImages = <String, ChapterImage>{};
    for (final chapter in _exportableChapters(book)) {
      final referenced = referencedChapterImageIds(chapter.body);
      for (final image in chapter.images) {
        if (referenced.contains(image.id)) usedImages[image.id] = image;
      }
    }
    final baseName = _safeFileName(book.title);
    if (usedImages.isEmpty) {
      return documentSaver.save(
        bytes: Uint8List.fromList(utf8.encode(buildMarkdown(book))),
        suggestedName: '$baseName.md',
        mimeType: 'text/markdown',
        extensions: const ['md', 'markdown'],
      );
    }
    try {
      final archive = Archive();
      final imagePaths = <String, String>{};
      for (final image in usedImages.values) {
        final file = File(image.path);
        if (!await file.exists() ||
            await file.length() > ProjectArchive.maxAssetBytes) {
          return const DocumentSaveResult.failed('正文图片丢失或超过 32 MB，无法完整导出');
        }
        final extension = image.path.split('.').last.toLowerCase();
        final safeExtension = {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)
            ? extension
            : 'bin';
        final path = 'assets/${image.id}.$safeExtension';
        imagePaths[image.id] = path;
        archive.add(ArchiveFile.bytes(path, await file.readAsBytes()));
      }
      archive.add(
        ArchiveFile.bytes(
          '$baseName.md',
          utf8.encode(buildMarkdown(book, imagePaths: imagePaths)),
        ),
      );
      final bytes = ZipEncoder().encodeBytes(archive);
      return await documentSaver.save(
        bytes: bytes,
        suggestedName: '$baseName-Markdown.zip',
        mimeType: 'application/zip',
        extensions: const ['zip'],
      );
    } on FileSystemException {
      return const DocumentSaveResult.failed('无法读取正文图片，Markdown 未导出');
    }
  }

  void _touchBook() {
    final book = activeBook;
    if (book != null) book.updatedAt = DateTime.now();
    _queueSave();
    notifyListeners();
  }

  void _queueSave() {
    saveState = SaveState.saving;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await _saveNow();
  }

  Future<void> _saveNow() async {
    try {
      await store.save(data);
      saveState = SaveState.saved;
    } on Object {
      saveState = SaveState.failed;
    }
    if (!_disposed) notifyListeners();
  }

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  @override
  void dispose() {
    _disposed = true;
    if (_saveTimer?.isActive ?? false) {
      unawaited(flush());
    }
    super.dispose();
  }
}

String buildPlainText(Book book) {
  final buffer = StringBuffer()..writeln(book.title);
  String? lastVolumeId;
  for (final chapter in _exportableChapters(book)) {
    if (chapter.volumeId != lastVolumeId) {
      final volume = book.volumes
          .where((item) => item.id == chapter.volumeId && item.exportEnabled)
          .firstOrNull;
      if (volume != null) {
        buffer
          ..writeln()
          ..writeln('【${volume.title}】');
      }
      lastVolumeId = chapter.volumeId;
    }
    buffer
      ..writeln()
      ..writeln(chapter.title)
      ..writeln()
      ..writeln(plainTextFromMarkdown(chapter.body));
  }
  return buffer.toString().trimRight();
}

String buildMarkdown(Book book, {Map<String, String> imagePaths = const {}}) {
  final buffer = StringBuffer()..writeln('# ${book.title}');
  String? lastVolumeId;
  for (final chapter in _exportableChapters(book)) {
    if (chapter.volumeId != lastVolumeId) {
      final volume = book.volumes
          .where((item) => item.id == chapter.volumeId && item.exportEnabled)
          .firstOrNull;
      if (volume != null) {
        buffer
          ..writeln()
          ..writeln('## ${volume.title}');
      }
      lastVolumeId = chapter.volumeId;
    }
    buffer
      ..writeln()
      ..writeln('### ${chapter.title}')
      ..writeln()
      ..writeln(markdownForExternalExport(chapter.body, imagePaths));
  }
  return buffer.toString().trimRight();
}

Iterable<Chapter> _exportableChapters(Book book) sync* {
  for (final chapter in book.chapters) {
    if (!chapter.exportEnabled) continue;
    final volume = book.volumes
        .where((item) => item.id == chapter.volumeId)
        .firstOrNull;
    if (volume?.exportEnabled == false) continue;
    yield chapter;
  }
}
