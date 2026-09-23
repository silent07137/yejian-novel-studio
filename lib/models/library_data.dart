class WriterProfile {
  WriterProfile({
    this.authorName = '未命名',
    this.avatarPath,
    this.writingDays = 1,
    this.setupComplete = false,
  });

  String authorName;
  String? avatarPath;
  int writingDays;
  bool setupComplete;

  factory WriterProfile.fromJson(
    Map<String, dynamic> json, {
    bool migrateLegacyName = false,
  }) {
    final storedName = (json['authorName'] as String? ?? '').trim();
    return WriterProfile(
      authorName: storedName.isEmpty || migrateLegacyName && storedName == '阿谧'
          ? '未命名'
          : storedName,
      avatarPath: json['avatarPath'] as String?,
      writingDays: json['writingDays'] as int? ?? 1,
      setupComplete: json['setupComplete'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'authorName': authorName,
    'avatarPath': avatarPath,
    'writingDays': writingDays,
    'setupComplete': setupComplete,
  };
}

class AppSettings {
  AppSettings({
    this.palette = 'yejian',
    this.appearanceMode = 'light',
    this.fontSize = 18,
    this.lineHeight = 1.4,
    this.customFontPath,
  });

  String palette;
  String appearanceMode;
  double fontSize;
  double lineHeight;
  String? customFontPath;

  factory AppSettings.fromJson(
    Map<String, dynamic> json, {
    bool migrateLegacyPalette = false,
  }) {
    final storedPalette = json['palette'] as String? ?? 'yejian';
    return AppSettings(
      palette: migrateLegacyPalette && storedPalette == 'mist'
          ? 'yejian'
          : storedPalette,
      appearanceMode: switch (json['appearanceMode'] as String?) {
        'dark' => 'dark',
        'system' => 'system',
        _ => 'light',
      },
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.4,
      customFontPath: json['customFontPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'palette': palette,
    'appearanceMode': appearanceMode,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'customFontPath': customFontPath,
  };
}

class Chapter {
  Chapter({
    required this.id,
    required this.title,
    this.volumeId,
    this.body = '',
    this.summary = '',
    this.status = '草稿',
    this.exportEnabled = true,
    this.sortIndex = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  String id;
  String title;
  String? volumeId;
  String body;
  String summary;
  String status;
  bool exportEnabled;
  int sortIndex;
  DateTime updatedAt;

  int get wordCount => countWords(body);

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名章节',
    volumeId: json['volumeId'] as String?,
    body: json['body'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    status: json['status'] as String? ?? '草稿',
    exportEnabled: json['exportEnabled'] as bool? ?? true,
    sortIndex: (json['sortIndex'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'volumeId': volumeId,
    'body': body,
    'summary': summary,
    'status': status,
    'exportEnabled': exportEnabled,
    'sortIndex': sortIndex,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class Volume {
  Volume({
    required this.id,
    required this.title,
    this.summary = '',
    this.status = '进行中',
    this.exportEnabled = true,
    this.sortIndex = 0,
  });

  String id;
  String title;
  String summary;
  String status;
  bool exportEnabled;
  int sortIndex;

  factory Volume.fromJson(Map<String, dynamic> json) => Volume(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名分卷',
    summary: json['summary'] as String? ?? '',
    status: json['status'] as String? ?? '进行中',
    exportEnabled: json['exportEnabled'] as bool? ?? true,
    sortIndex: (json['sortIndex'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'status': status,
    'exportEnabled': exportEnabled,
    'sortIndex': sortIndex,
  };
}

class RoleRelation {
  RoleRelation({
    required this.id,
    required this.targetRoleId,
    required this.name,
    this.direction = '单向',
    this.description = '',
    this.stage = '',
  });

  String id;
  String targetRoleId;
  String name;
  String direction;
  String description;
  String stage;

  factory RoleRelation.fromJson(Map<String, dynamic> json) => RoleRelation(
    id: json['id'] as String,
    targetRoleId: json['targetRoleId'] as String? ?? '',
    name: json['name'] as String? ?? '关系',
    direction: json['direction'] as String? ?? '单向',
    description: json['description'] as String? ?? '',
    stage: json['stage'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'targetRoleId': targetRoleId,
    'name': name,
    'direction': direction,
    'description': description,
    'stage': stage,
  };
}

class CustomFieldDefinition {
  CustomFieldDefinition({
    required this.id,
    required this.name,
    this.type = 'shortText',
    this.scope = 'local',
    this.appliesTo,
    this.enabled = true,
    this.required = false,
    this.deleted = false,
    List<String>? options,
  }) : options = options ?? [];

  String id;
  String name;
  String type;
  String scope;
  String? appliesTo;
  bool enabled;
  bool required;
  bool deleted;
  List<String> options;

  factory CustomFieldDefinition.fromJson(Map<String, dynamic> json) =>
      CustomFieldDefinition(
        id: json['id'] as String,
        name: json['name'] as String? ?? '未命名字段',
        type: json['type'] as String? ?? 'shortText',
        scope: json['scope'] as String? ?? 'local',
        appliesTo: json['appliesTo'] as String?,
        enabled: json['enabled'] as bool? ?? true,
        required: json['required'] as bool? ?? false,
        deleted: json['deleted'] as bool? ?? false,
        options: _stringList(json['options']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'scope': scope,
    'appliesTo': appliesTo,
    'enabled': enabled,
    'required': required,
    'deleted': deleted,
    'options': options,
  };
}

List<CustomFieldDefinition> defaultRoleBaseFields() => [
  for (final item in const [
    ('name', '姓名', 'shortText'),
    ('alias', '别名', 'shortText'),
    ('age', '年龄', 'shortText'),
    ('identity', '身份 / 职业', 'shortText'),
    ('appearance', '外貌', 'longText'),
    ('personality', '性格', 'longText'),
    ('background', '背景经历', 'longText'),
    ('goal', '目标 / 动机', 'longText'),
    ('ability', '能力 / 特长', 'longText'),
    ('weakness', '弱点', 'longText'),
    ('relationships', '人物关系', 'longText'),
    ('notes', '备注', 'longText'),
  ])
    CustomFieldDefinition(
      id: item.$1,
      name: item.$2,
      type: item.$3,
      scope: 'book',
      required: item.$1 == 'name',
    ),
];

List<CustomFieldDefinition> defaultWorldBaseFields() => [
  for (final item in const [
    ('title', '名称', 'shortText'),
    ('type', '类别', 'shortText'),
    ('description', '简介', 'longText'),
    ('features', '核心特点', 'longText'),
    ('rule', '规则与限制', 'longText'),
    ('references', '关联资料', 'shortText'),
    ('notes', '备注', 'longText'),
  ])
    CustomFieldDefinition(
      id: item.$1,
      name: item.$2,
      type: item.$3,
      scope: 'book',
      required: item.$1 == 'title' || item.$1 == 'type',
    ),
];

class RoleCard {
  RoleCard({
    required this.id,
    required this.name,
    this.alias = '',
    this.age = '',
    this.identity = '',
    this.description = '',
    this.appearance = '',
    this.personality = '',
    this.background = '',
    this.goal = '',
    this.ability = '',
    this.weakness = '',
    this.relationships = '',
    this.notes = '',
    List<String>? tags,
    List<RoleRelation>? relations,
    List<CustomFieldDefinition>? customFields,
    Map<String, dynamic>? customValues,
  }) : tags = tags ?? [],
       relations = relations ?? [],
       customFields = customFields ?? [],
       customValues = customValues ?? {};

  String id;
  String name;
  String alias;
  String age;
  String identity;
  String description;
  String appearance;
  String personality;
  String background;
  String goal;
  String ability;
  String weakness;
  String relationships;
  String notes;
  List<String> tags;
  List<RoleRelation> relations;
  List<CustomFieldDefinition> customFields;
  Map<String, dynamic> customValues;

  factory RoleCard.fromJson(Map<String, dynamic> json) => RoleCard(
    id: json['id'] as String,
    name: json['name'] as String? ?? '未命名角色',
    alias: json['alias'] as String? ?? '',
    age: json['age'] as String? ?? '',
    identity:
        json['identity'] as String? ?? json['profession'] as String? ?? '',
    description:
        json['description'] as String? ?? json['intro'] as String? ?? '',
    appearance: json['appearance'] as String? ?? '',
    personality: json['personality'] as String? ?? '',
    background: json['background'] as String? ?? '',
    goal: json['goal'] as String? ?? '',
    ability: json['ability'] as String? ?? '',
    weakness: json['weakness'] as String? ?? '',
    relationships: json['relationships'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    tags: _stringList(json['tags']),
    relations: (json['relations'] as List<dynamic>? ?? [])
        .map((item) => RoleRelation.fromJson(item as Map<String, dynamic>))
        .toList(),
    customFields: (json['customFields'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CustomFieldDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    customValues: Map<String, dynamic>.from(
      json['customValues'] as Map<String, dynamic>? ?? const {},
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'alias': alias,
    'age': age,
    'identity': identity,
    'description': description,
    'appearance': appearance,
    'personality': personality,
    'background': background,
    'goal': goal,
    'ability': ability,
    'weakness': weakness,
    'relationships': relationships,
    'notes': notes,
    'tags': tags,
    'relations': relations.map((relation) => relation.toJson()).toList(),
    'customFields': customFields.map((field) => field.toJson()).toList(),
    'customValues': customValues,
  };
}

class WorldCard {
  WorldCard({
    required this.id,
    required this.title,
    this.type = '自定义',
    this.description = '',
    this.features = '',
    this.rule = '',
    this.references = '',
    this.notes = '',
    Map<String, String>? details,
    List<String>? tags,
    List<CustomFieldDefinition>? customFields,
    Map<String, dynamic>? customValues,
  }) : details = details ?? {},
       tags = tags ?? [],
       customFields = customFields ?? [],
       customValues = customValues ?? {};

  String id;
  String title;
  String type;
  String description;
  String features;
  String rule;
  String references;
  String notes;
  Map<String, String> details;
  List<String> tags;
  List<CustomFieldDefinition> customFields;
  Map<String, dynamic> customValues;

  factory WorldCard.fromJson(Map<String, dynamic> json) => WorldCard(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名设定',
    type: json['type'] as String? ?? '自定义',
    description: json['description'] as String? ?? '',
    features: json['features'] as String? ?? '',
    rule: json['rule'] as String? ?? '',
    references: json['references'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    details: (json['details'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    ),
    tags: _stringList(json['tags']),
    customFields: (json['customFields'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              CustomFieldDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    customValues: Map<String, dynamic>.from(
      json['customValues'] as Map<String, dynamic>? ?? const {},
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'description': description,
    'features': features,
    'rule': rule,
    'references': references,
    'notes': notes,
    'details': details,
    'tags': tags,
    'customFields': customFields.map((field) => field.toJson()).toList(),
    'customValues': customValues,
  };
}

class StoryTrack {
  StoryTrack({
    required this.id,
    required this.name,
    this.type = '主线',
    this.color = 'purple',
  });

  String id;
  String name;
  String type;
  String color;

  factory StoryTrack.fromJson(Map<String, dynamic> json) => StoryTrack(
    id: json['id'] as String,
    name: json['name'] as String? ?? '未命名时间线',
    type: json['type'] as String? ?? '自定义',
    color: json['color'] as String? ?? 'purple',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'color': color,
  };
}

class StoryEvent {
  StoryEvent({
    required this.id,
    required this.title,
    required this.storyDate,
    this.order = 0,
    this.description = '',
    this.chapterId,
    this.persons = '',
    this.group = '尚未分组',
    this.flowLevel = 0,
    List<String>? trackIds,
    List<String>? roleIds,
  }) : trackIds = trackIds ?? [],
       roleIds = roleIds ?? [];

  String id;
  String title;
  String storyDate;
  double order;
  String description;
  String? chapterId;
  String persons;
  String group;
  int flowLevel;
  List<String> trackIds;
  List<String> roleIds;

  factory StoryEvent.fromJson(Map<String, dynamic> json) => StoryEvent(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名事件',
    storyDate:
        json['storyDate'] as String? ?? json['date'] as String? ?? '时间未定',
    order: (json['order'] as num?)?.toDouble() ?? 0,
    description: json['description'] as String? ?? '',
    chapterId: json['chapterId'] as String? ?? json['chapter'] as String?,
    persons: json['persons'] as String? ?? '',
    group: json['group'] as String? ?? '尚未分组',
    flowLevel: (json['flowLevel'] as num?)?.toInt() ?? 0,
    trackIds: _stringList(json['trackIds'] ?? json['tracks']),
    roleIds: _stringList(json['roleIds']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'storyDate': storyDate,
    'order': order,
    'description': description,
    'chapterId': chapterId,
    'persons': persons,
    'group': group,
    'flowLevel': flowLevel,
    'trackIds': trackIds,
    'roleIds': roleIds,
  };
}

class StoryLink {
  StoryLink({
    required this.id,
    required this.fromEventId,
    required this.toEventId,
    this.label = '关联',
  });

  String id;
  String fromEventId;
  String toEventId;
  String label;

  factory StoryLink.fromJson(Map<String, dynamic> json) => StoryLink(
    id: json['id'] as String,
    fromEventId:
        json['fromEventId'] as String? ?? json['from'] as String? ?? '',
    toEventId: json['toEventId'] as String? ?? json['to'] as String? ?? '',
    label: json['label'] as String? ?? '关联',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromEventId': fromEventId,
    'toEventId': toEventId,
    'label': label,
  };
}

class PlotClue {
  PlotClue({
    required this.id,
    required this.title,
    this.description = '',
    this.originChapterId,
    this.plannedChapterId,
    this.actualChapterId,
  });

  String id;
  String title;
  String description;
  String? originChapterId;
  String? plannedChapterId;
  String? actualChapterId;

  factory PlotClue.fromJson(Map<String, dynamic> json) => PlotClue(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名伏笔',
    description: json['description'] as String? ?? '',
    originChapterId:
        json['originChapterId'] as String? ?? json['origin'] as String?,
    plannedChapterId:
        json['plannedChapterId'] as String? ?? json['plan'] as String?,
    actualChapterId:
        json['actualChapterId'] as String? ?? json['actual'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'originChapterId': originChapterId,
    'plannedChapterId': plannedChapterId,
    'actualChapterId': actualChapterId,
  };
}

class IdeaNote {
  IdeaNote({required this.id, required this.body});

  String id;
  String body;

  factory IdeaNote.fromJson(Map<String, dynamic> json) =>
      IdeaNote(id: json['id'] as String, body: json['body'] as String? ?? '');

  Map<String, dynamic> toJson() => {'id': id, 'body': body};
}

class Book {
  Book({
    required this.id,
    required this.title,
    this.description = '',
    this.coverPath,
    List<Volume>? volumes,
    List<Chapter>? chapters,
    List<RoleCard>? roles,
    List<CustomFieldDefinition>? roleFields,
    List<CustomFieldDefinition>? roleBaseFields,
    List<WorldCard>? worlds,
    List<CustomFieldDefinition>? worldFields,
    List<CustomFieldDefinition>? worldBaseFields,
    List<StoryTrack>? tracks,
    List<StoryEvent>? events,
    List<StoryLink>? storyLinks,
    List<PlotClue>? clues,
    List<IdeaNote>? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : volumes = volumes ?? [],
       chapters = chapters ?? [],
       roles = roles ?? [],
       roleFields = roleFields ?? [],
       roleBaseFields = roleBaseFields == null || roleBaseFields.isEmpty
           ? defaultRoleBaseFields()
           : roleBaseFields,
       worlds = worlds ?? [],
       worldFields = worldFields ?? [],
       worldBaseFields = worldBaseFields == null || worldBaseFields.isEmpty
           ? defaultWorldBaseFields()
           : worldBaseFields,
       tracks = tracks ?? [],
       events = events ?? [],
       storyLinks = storyLinks ?? [],
       clues = clues ?? [],
       notes = notes ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  String id;
  String title;
  String description;
  String? coverPath;
  List<Volume> volumes;
  List<Chapter> chapters;
  List<RoleCard> roles;
  List<CustomFieldDefinition> roleFields;
  List<CustomFieldDefinition> roleBaseFields;
  List<WorldCard> worlds;
  List<CustomFieldDefinition> worldFields;
  List<CustomFieldDefinition> worldBaseFields;
  List<StoryTrack> tracks;
  List<StoryEvent> events;
  List<StoryLink> storyLinks;
  List<PlotClue> clues;
  List<IdeaNote> notes;
  DateTime createdAt;
  DateTime updatedAt;

  int get wordCount =>
      chapters.fold(0, (sum, chapter) => sum + chapter.wordCount);

  factory Book.fromJson(Map<String, dynamic> json) {
    final volumes = (json['volumes'] as List<dynamic>? ?? [])
        .map((item) => Volume.fromJson(item as Map<String, dynamic>))
        .toList();
    final tracks = (json['tracks'] as List<dynamic>? ?? [])
        .map((item) => StoryTrack.fromJson(item as Map<String, dynamic>))
        .toList();
    if (tracks.isEmpty) {
      tracks.add(StoryTrack(id: 'track-${json['id']}-main', name: '故事主线'));
    }
    final events = (json['events'] as List<dynamic>? ?? [])
        .map((item) => StoryEvent.fromJson(item as Map<String, dynamic>))
        .toList();
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      if (event.order == 0) event.order = index + 1;
      if (event.trackIds.isEmpty) event.trackIds.add(tracks.first.id);
    }
    final chapters = (json['chapters'] as List<dynamic>? ?? [])
        .map((item) => Chapter.fromJson(item as Map<String, dynamic>))
        .toList();
    for (var index = 0; index < chapters.length; index++) {
      if (chapters[index].sortIndex == 0) chapters[index].sortIndex = index;
    }
    return Book(
      id: json['id'] as String,
      title: json['title'] as String? ?? '未命名作品',
      description: json['description'] as String? ?? '',
      coverPath: json['coverPath'] as String?,
      volumes: volumes,
      chapters: chapters,
      roles:
          (json['roles'] as List<dynamic>? ??
                  json['people'] as List<dynamic>? ??
                  [])
              .map((item) => RoleCard.fromJson(item as Map<String, dynamic>))
              .toList(),
      roleFields: (json['roleFields'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                CustomFieldDefinition.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      roleBaseFields: (json['roleBaseFields'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                CustomFieldDefinition.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      worlds: (json['worlds'] as List<dynamic>? ?? [])
          .map((item) => WorldCard.fromJson(item as Map<String, dynamic>))
          .toList(),
      worldFields: (json['worldFields'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                CustomFieldDefinition.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      worldBaseFields: (json['worldBaseFields'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                CustomFieldDefinition.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      tracks: tracks,
      events: events,
      storyLinks:
          (json['storyLinks'] as List<dynamic>? ??
                  json['flowLinks'] as List<dynamic>? ??
                  [])
              .map((item) => StoryLink.fromJson(item as Map<String, dynamic>))
              .where(
                (link) =>
                    events.any((event) => event.id == link.fromEventId) &&
                    events.any((event) => event.id == link.toEventId),
              )
              .toList(),
      clues: (json['clues'] as List<dynamic>? ?? [])
          .map((item) => PlotClue.fromJson(item as Map<String, dynamic>))
          .toList(),
      notes: (json['notes'] as List<dynamic>? ?? [])
          .map((item) => IdeaNote.fromJson(item as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'coverPath': coverPath,
    'volumes': volumes.map((volume) => volume.toJson()).toList(),
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'roles': roles.map((role) => role.toJson()).toList(),
    'roleFields': roleFields.map((field) => field.toJson()).toList(),
    'roleBaseFields': roleBaseFields.map((field) => field.toJson()).toList(),
    'worlds': worlds.map((world) => world.toJson()).toList(),
    'worldFields': worldFields.map((field) => field.toJson()).toList(),
    'worldBaseFields': worldBaseFields.map((field) => field.toJson()).toList(),
    'tracks': tracks.map((track) => track.toJson()).toList(),
    'events': events.map((event) => event.toJson()).toList(),
    'storyLinks': storyLinks.map((link) => link.toJson()).toList(),
    'clues': clues.map((clue) => clue.toJson()).toList(),
    'notes': notes.map((note) => note.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class LibraryData {
  LibraryData({
    required this.profile,
    required this.settings,
    required this.books,
    this.activeBookId,
  });

  static const schemaVersion = 4;

  WriterProfile profile;
  AppSettings settings;
  List<Book> books;
  String? activeBookId;

  int get totalWords => books.fold(0, (sum, book) => sum + book.wordCount);

  factory LibraryData.fromJson(Map<String, dynamic> json) {
    final version = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    return LibraryData(
      profile: WriterProfile.fromJson(
        json['profile'] as Map<String, dynamic>? ?? {},
        migrateLegacyName: version < 2,
      ),
      settings: AppSettings.fromJson(
        json['settings'] as Map<String, dynamic>? ?? {},
        migrateLegacyPalette: version < 2,
      ),
      books: (json['books'] as List<dynamic>? ?? [])
          .map((item) => Book.fromJson(item as Map<String, dynamic>))
          .toList(),
      activeBookId: json['activeBookId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'profile': profile.toJson(),
    'settings': settings.toJson(),
    'books': books.map((book) => book.toJson()).toList(),
    'activeBookId': activeBookId,
  };

  factory LibraryData.empty() =>
      LibraryData(profile: WriterProfile(), settings: AppSettings(), books: []);

  factory LibraryData.seeded({bool profileSetupComplete = false}) {
    final firstVolume = Volume(id: 'volume-1', title: '雾中来信');
    final secondVolume = Volume(id: 'volume-2', title: '灯塔回声');
    final first = Chapter(
      id: 'chapter-1',
      title: '消失的第七封信',
      volumeId: firstVolume.id,
      summary: '林照在旧书中发现一封没有收信人的信。',
      status: '定稿',
      body:
          '入秋后的第一场雨，落在旧书馆关门以前。\n\n'
          '林照把最后一本书放回高处，书脊间却掉下一封信。信封很薄，没有署名，只有一枚模糊的灯塔印记。',
    );
    final second = Chapter(
      id: 'chapter-2',
      title: '不肯熄灭的灯',
      volumeId: firstVolume.id,
      summary: '林照与江迟相遇，发现灯光会留下记忆。',
      status: '修订中',
      body: '灯塔里的钟，比城里慢了七分钟。\n\n灯光亮起的那一刻，林照听见了雨声。',
    );
    final third = Chapter(
      id: 'chapter-3',
      title: '归途的名字',
      volumeId: secondVolume.id,
      summary: '发现灯塔与旧信的关联，准备回收时间差的伏笔。',
    );
    final tracks = [
      StoryTrack(id: 'track-main', name: '来信主线'),
      StoryTrack(id: 'track-lin', name: '林照', type: '角色线', color: 'blue'),
      StoryTrack(
        id: 'track-history',
        name: '旧城往事',
        type: '世界历史',
        color: 'amber',
      ),
      StoryTrack(
        id: 'track-other',
        name: '另一种选择',
        type: '平行世界／轮回',
        color: 'sage',
      ),
    ];
    final book = Book(
      id: 'book-1',
      title: '雾灯来信',
      description: '一座旧城、七封信，以及重新亮起的灯塔。',
      volumes: [firstVolume, secondVolume],
      chapters: [first, second, third],
      roles: [
        RoleCard(
          id: 'role-1',
          name: '林照',
          alias: '阿照',
          age: '22',
          identity: '档案整理员',
          description: '习惯在书页间寻找被遗忘的故事。',
          appearance: '短发，浅灰外套，随身带一本旧索引册。',
          personality: '慢热、细致，对缺失的记录格外在意。',
          goal: '找到第七封信真正的收信人。',
          ability: '辨识旧信笔迹与印记。',
          tags: ['主角', '慢热'],
          customFields: [
            CustomFieldDefinition(
              id: 'role-field-loop',
              name: '轮回记忆',
              type: 'longText',
            ),
          ],
          customValues: {
            'role-field-camp': '书馆',
            'role-field-loop': '偶尔会梦见未曾寄出的信。',
          },
        ),
        RoleCard(
          id: 'role-2',
          name: '江迟',
          identity: '修灯人',
          description: '修好每一盏灯，却从不点亮自己的那一盏。',
          goal: '让熄灭的灯塔重新亮起。',
          tags: ['关键人物'],
          customValues: {'role-field-camp': '灯塔'},
        ),
      ],
      roleFields: [
        CustomFieldDefinition(
          id: 'role-field-camp',
          name: '所属阵营',
          type: 'singleChoice',
          scope: 'book',
          options: ['书馆', '灯塔', '旧城议会'],
        ),
      ],
      worlds: [
        WorldCard(
          id: 'world-1',
          title: '灯塔书馆',
          type: '地点',
          description: '沿海旧城的一座书馆，与废弃灯塔隔街相望。',
          features: '第七排书架没有固定的藏书目录。',
          rule: '闭馆后，第七排书架会出现无法归类的旧信。',
          details: {'所属地区': '旧城海岸', '环境': '多雨，夜里常有海雾。'},
          tags: ['核心设定', '悬念'],
          customValues: {
            'world-field-visibility': '公开',
            'world-field-population': '约 3.2 万人',
          },
        ),
        WorldCard(
          id: 'world-2',
          title: '留光',
          type: '世界规则',
          description: '特制灯罩能够短暂留住一段记忆。',
          rule: '只能重现记忆，不能改变已经发生的事。',
          details: {'来源': '旧式灯罩与承载记忆的物品', '代价': '点亮后，这段记忆会消散。'},
          tags: ['核心设定'],
          customValues: {'world-field-visibility': '作者私有'},
        ),
      ],
      worldFields: [
        CustomFieldDefinition(
          id: 'world-field-visibility',
          name: '可见性',
          type: 'singleChoice',
          scope: 'book',
          options: ['公开', '作者私有'],
        ),
        CustomFieldDefinition(
          id: 'world-field-population',
          name: '人口',
          type: 'number',
          scope: 'type',
          appliesTo: '地点',
        ),
      ],
      tracks: tracks,
      events: [
        StoryEvent(
          id: 'event-1',
          title: '旧灯塔最后一次熄灭',
          storyDate: '霜历 208 年 · 冬',
          order: 1,
          description: '十年前的往事，在故事第三章才被讲述。',
          chapterId: third.id,
          persons: '江迟',
          roleIds: ['role-2'],
          group: '灯塔旧事',
          trackIds: ['track-history'],
        ),
        StoryEvent(
          id: 'event-2',
          title: '第七封信出现',
          storyDate: '霜历 218 年 · 秋一日',
          order: 2,
          description: '林照在第七排书架发现来历不明的信。',
          chapterId: first.id,
          persons: '林照',
          roleIds: ['role-1'],
          group: '来信之谜',
          trackIds: ['track-main'],
        ),
        StoryEvent(
          id: 'event-3',
          title: '灯塔重亮',
          storyDate: '霜历 218 年 · 秋二日',
          order: 3,
          description: '林照与江迟第一次相遇。',
          chapterId: second.id,
          persons: '林照、江迟',
          roleIds: ['role-1', 'role-2'],
          group: '来信之谜',
          flowLevel: 1,
          trackIds: ['track-main', 'track-lin'],
        ),
        StoryEvent(
          id: 'event-5',
          title: '决定寻找收信人',
          storyDate: '霜历 218 年 · 秋一日',
          order: 3.5,
          description: '林照决定追查第七封信真正的收信人。',
          chapterId: second.id,
          persons: '林照',
          roleIds: ['role-1'],
          group: '林照的选择',
          flowLevel: 2,
          trackIds: ['track-lin'],
        ),
        StoryEvent(
          id: 'event-4',
          title: '带着信离开旧城',
          storyDate: '霜历 218 年 · 秋三日',
          order: 4,
          description: '平行分支：林照选择不再追问。',
          persons: '林照',
          roleIds: ['role-1'],
          group: '故事走向',
          flowLevel: 2,
          trackIds: ['track-other'],
        ),
      ],
      storyLinks: [
        StoryLink(
          id: 'link-1',
          fromEventId: 'event-1',
          toEventId: 'event-3',
          label: '留下线索',
        ),
        StoryLink(
          id: 'link-2',
          fromEventId: 'event-2',
          toEventId: 'event-3',
          label: '前往灯塔',
        ),
        StoryLink(
          id: 'link-3',
          fromEventId: 'event-3',
          toEventId: 'event-5',
          label: '继续追查',
        ),
        StoryLink(
          id: 'link-4',
          fromEventId: 'event-3',
          toEventId: 'event-4',
          label: '另一种选择',
        ),
      ],
      clues: [
        PlotClue(
          id: 'clue-1',
          title: '慢了七分钟的钟',
          description: '时间差与寄信的时间有关。',
          originChapterId: second.id,
          plannedChapterId: third.id,
        ),
      ],
      notes: [IdeaNote(id: 'note-1', body: '一句对白：“如果灯能记住一个人，熄灭以后，记忆会去哪里？”')],
    );
    return LibraryData(
      profile: WriterProfile(setupComplete: profileSetupComplete),
      settings: AppSettings(),
      books: [book],
      activeBookId: book.id,
    );
  }
}

List<String> _stringList(Object? value) => value is List
    ? value.map((item) => item.toString()).toList()
    : const <String>[];

int countWords(String text) {
  final han = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF]').allMatches(text).length;
  final nonHan = text.replaceAll(RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF]'), ' ');
  final words = RegExp(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*")
      .allMatches(nonHan)
      .length;
  return han + words;
}
