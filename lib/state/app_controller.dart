import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/local_store.dart';
import '../domain/entity_id.dart';
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
  about,
  profile,
}

enum SaveState { saved, saving, failed }

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.data,
    DocumentSaver? documentSaver,
  }) : documentSaver = documentSaver ?? SystemDocumentSaver() {
    selectedBookId =
        data.activeBookId ?? (data.books.isEmpty ? null : data.books.first.id);
    selectedChapterId = activeBook?.chapters.firstOrNull?.id;
  }

  final DataStore store;
  final DocumentSaver documentSaver;
  LibraryData data;
  WorkspacePage page = WorkspacePage.home;
  SaveState saveState = SaveState.saved;
  String? selectedBookId;
  String? selectedChapterId;
  String? loadedFontFamily;
  Timer? _saveTimer;
  final List<WorkspacePage> _pageHistory = [];

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
    WorkspacePage.about ||
    WorkspacePage.profile => true,
    _ => false,
  };

  bool get canGoBack =>
      page != WorkspacePage.home && page != WorkspacePage.settings;

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
    if (isBookWorkspace) {
      _pageHistory.clear();
      page = WorkspacePage.bookOverview;
      notifyListeners();
      return;
    }
    if (page == WorkspacePage.appSettings ||
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
    final copy = Chapter(
      id: newEntityId('chapter'),
      title: '${source.title}（副本）',
      volumeId: source.volumeId,
      body: source.body,
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

  @Deprecated('Legacy JSON format; do not expose as a verified project backup.')
  Future<String?> exportCurrentBook() async {
    final book = activeBook;
    if (book == null) return null;
    final name = '${_safeFileName(book.title)}.sns';
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: '页间单书工程', extensions: ['sns']),
      ],
    );
    if (location == null) return null;
    final payload = {
      'format': 'sns',
      'formatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': data.profile.toJson(),
      'book': book.toJson(),
    };
    await _writeExport(location.path, payload, name);
    return location.path;
  }

  @Deprecated('Legacy JSON format; do not expose as a verified project backup.')
  Future<String?> exportLibrary() async {
    final location = await getSaveLocation(
      suggestedName: '页间作品集.snss',
      acceptedTypeGroups: const [
        XTypeGroup(label: '页间多书工程', extensions: ['snss']),
      ],
    );
    if (location == null) return null;
    final payload = {
      'format': 'snss',
      'formatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'library': data.toJson(),
    };
    await _writeExport(location.path, payload, '页间作品集.snss');
    return location.path;
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
    final name = '${_safeFileName(book.title)}.md';
    return documentSaver.save(
      bytes: Uint8List.fromList(utf8.encode(buildMarkdown(book))),
      suggestedName: name,
      mimeType: 'text/markdown',
      extensions: const ['md', 'markdown'],
    );
  }

  Future<void> _writeExport(
    String path,
    Map<String, dynamic> payload,
    String fileName,
  ) async {
    const encoder = JsonEncoder.withIndent('  ');
    final bytes = Uint8List.fromList(utf8.encode(encoder.convert(payload)));
    final file = XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: fileName,
    );
    await file.saveTo(path);
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
    notifyListeners();
  }

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  @override
  void dispose() {
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
      ..writeln(chapter.body);
  }
  return buffer.toString().trimRight();
}

String buildMarkdown(Book book) {
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
      ..writeln(chapter.body);
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
