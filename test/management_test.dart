import 'package:flutter_test/flutter_test.dart';
import 'package:yejian_native/data/local_store.dart';
import 'package:yejian_native/models/library_data.dart';
import 'package:yejian_native/state/app_controller.dart';

class _MemoryStore implements DataStore {
  _MemoryStore(this.data);

  LibraryData data;

  @override
  Future<LibraryData> load() async => data;

  @override
  Future<void> save(LibraryData data) async => this.data = data;
}

void main() {
  test('正文标注随编辑移动，删除关联资料时清理引用', () {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: _MemoryStore(data), data: data);
    final book = controller.activeBook!;
    final chapter = controller.activeChapter!;
    final clue = book.clues.first;
    final idea = book.notes.first;
    final revision = controller.addChapterMarker(
      start: 0,
      end: 4,
      kind: 'revision',
      note: '待推敲',
    )!;
    final clueMarker = controller.addChapterMarker(
      start: 5,
      end: 9,
      kind: 'clue',
      note: '',
      referenceId: clue.id,
    )!;
    controller.addChapterMarker(
      start: 10,
      end: 12,
      kind: 'idea',
      note: '',
      referenceId: idea.id,
    );

    controller.updateChapterBody('引子：${chapter.body}');
    expect(revision.start, 3);
    expect(clueMarker.start, 8);
    controller.updateChapterMarker(revision.id, '再改一遍');
    expect(revision.note, '再改一遍');
    controller.deleteClue(clue.id);
    expect(chapter.markers.where((item) => item.kind == 'clue'), isEmpty);
    controller.deleteNote(idea.id);
    expect(chapter.markers.where((item) => item.kind == 'idea'), isEmpty);
    expect(chapter.markers.single.id, revision.id);
    controller.deleteChapterMarker(revision.id);
    expect(chapter.markers, isEmpty);
  });

  test('分卷删除可保留卷内章节，章节状态可编辑', () {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: _MemoryStore(data), data: data);
    final book = controller.activeBook!;
    final volumeId = book.volumes.first.id;
    final chapter = book.chapters.firstWhere(
      (chapter) => chapter.volumeId == volumeId,
    );

    controller.updateChapterSettings(
      chapter.id,
      title: '改名后的章节',
      summary: '新梗概',
      status: '修订中',
      volumeId: volumeId,
      exportEnabled: false,
    );
    controller.deleteDirectoryItems(volumeIds: {volumeId});

    expect(book.volumes.any((volume) => volume.id == volumeId), isFalse);
    expect(book.chapters.any((item) => item.id == chapter.id), isTrue);
    expect(chapter.volumeId, isNull);
    expect(chapter.title, '改名后的章节');
    expect(chapter.status, '修订中');
    expect(chapter.exportEnabled, isFalse);
  });

  test('模板字段可停用、改名、新增和删除', () {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: _MemoryStore(data), data: data);
    final book = controller.activeBook!;
    final alias = book.roleBaseFields.firstWhere(
      (field) => field.id == 'alias',
    );

    controller.updateTemplateField(
      role: true,
      base: true,
      field: CustomFieldDefinition(
        id: alias.id,
        name: '其他称呼',
        type: alias.type,
        scope: alias.scope,
        enabled: false,
      ),
    );
    controller.addTemplateField(
      role: true,
      name: '阵营',
      type: 'singleChoice',
      options: ['主角方', '中立', '反派方'],
    );
    final camp = book.roleFields.last;
    controller.deleteTemplateField(role: true, fieldId: camp.id);

    final renamed = book.roleBaseFields.firstWhere(
      (field) => field.id == 'alias',
    );
    expect(renamed.name, '其他称呼');
    expect(renamed.enabled, isFalse);
    expect(camp.name, '阵营');
    expect(camp.deleted, isTrue);
    expect(camp.enabled, isFalse);
  });

  test('时间线和事件可编辑删除且不产生悬空连线', () {
    final data = LibraryData.seeded(profileSetupComplete: true);
    final controller = AppController(store: _MemoryStore(data), data: data);
    final book = controller.activeBook!;
    final track = book.tracks.last;
    final event = book.events.first;
    book.storyLinks.add(
      StoryLink(
        id: 'temporary-link',
        fromEventId: event.id,
        toEventId: book.events.last.id,
      ),
    );

    controller.updateTrack(track.id, name: '修订时间线', type: '自定义');
    controller.updateEvent(
      StoryEvent(
        id: event.id,
        title: '修订事件',
        storyDate: '秋三日',
        order: 3,
        trackIds: [track.id],
      ),
    );
    controller.deleteEvent(event.id);
    controller.deleteTrack(track.id);

    expect(book.events.any((item) => item.id == event.id), isFalse);
    expect(
      book.storyLinks.any(
        (link) => link.fromEventId == event.id || link.toEventId == event.id,
      ),
      isFalse,
    );
    expect(book.tracks.any((item) => item.id == track.id), isFalse);
    expect(book.events.every((item) => item.trackIds.isNotEmpty), isTrue);
  });
}
