/// Тип записи. Совпадает со значениями поля `type` на бэкенде.
enum NoteType {
  text,
  link;

  static NoteType fromApi(String? value) =>
      value == 'LINK' ? NoteType.link : NoteType.text;

  String get apiValue => this == NoteType.link ? 'LINK' : 'TEXT';

  String get label => this == NoteType.link ? 'Ссылка' : 'Заметка';
}

/// Заметка или ссылка.
class Note {
  const Note({
    required this.id,
    required this.type,
    required this.title,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.content,
    this.url,
    this.archivedAt,
  });

  final String id;
  final NoteType type;
  final String title;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? content;
  final String? url;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  /// Короткий текст для карточки в списке.
  String get preview {
    final text = content?.trim();
    if (text != null && text.isNotEmpty) return text;
    final link = url?.trim();
    if (link != null && link.isNotEmpty) return link;
    return '';
  }

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        type: NoteType.fromApi(json['type'] as String?),
        title: json['title'] as String,
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        content: json['content'] as String?,
        url: json['url'] as String?,
        archivedAt: json['archivedAt'] == null
            ? null
            : DateTime.parse(json['archivedAt'] as String),
      );

  @override
  bool operator ==(Object other) => other is Note && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Обратная операция к [Note.fromJson] — нужна оффлайн-кешу.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.apiValue,
        'title': title,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'content': content,
        'url': url,
        'archivedAt': archivedAt?.toIso8601String(),
      };

  @override
  String toString() => 'Note($id, $title)';
}

/// Тег пользователя вместе с числом активных заметок.
class Tag {
  const Tag({required this.id, required this.name, required this.noteCount});

  final String id;
  final String name;
  final int noteCount;

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id'] as String,
        name: json['name'] as String,
        noteCount: json['noteCount'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'noteCount': noteCount,
      };

  @override
  bool operator ==(Object other) => other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Режим фильтрации по нескольким тегам.
enum TagsMode {
  any,
  all;

  String get apiValue => this == TagsMode.all ? 'ALL' : 'ANY';

  String get label => this == TagsMode.all ? 'все теги' : 'любой тег';
}

/// Что пользователь выбрал в фильтрах списка.
///
/// Живёт в слое данных, потому что это одновременно и состояние фильтров,
/// и параметры запроса: держать две почти одинаковые модели смысла нет.
class NotesQuery {
  const NotesQuery({
    this.text = '',
    this.tags = const <String>{},
    this.mode = TagsMode.any,
    this.includeArchived = false,
    this.type,
  });

  /// Строка полнотекстового поиска.
  final String text;

  /// Выбранные теги (нормализованные имена, как их отдаёт бэкенд).
  final Set<String> tags;

  final TagsMode mode;
  final bool includeArchived;
  final NoteType? type;

  bool get hasFilters =>
      text.trim().isNotEmpty || tags.isNotEmpty || includeArchived || type != null;

  /// Сентинел: отличает «не передан» от «передан null» для необязательного поля.
  static const Object _unset = Object();

  NotesQuery copyWith({
    String? text,
    Set<String>? tags,
    TagsMode? mode,
    bool? includeArchived,
    Object? type = _unset,
  }) =>
      NotesQuery(
        text: text ?? this.text,
        tags: tags ?? this.tags,
        mode: mode ?? this.mode,
        includeArchived: includeArchived ?? this.includeArchived,
        type: identical(type, _unset) ? this.type : type as NoteType?,
      );

  /// Сбрасывает всё, кроме текста поиска: его пользователь стирает сам.
  NotesQuery withoutFilters() => NotesQuery(text: text);

  @override
  bool operator ==(Object other) =>
      other is NotesQuery &&
      other.text == text &&
      other.mode == mode &&
      other.includeArchived == includeArchived &&
      other.type == type &&
      other.tags.length == tags.length &&
      other.tags.containsAll(tags);

  @override
  int get hashCode => Object.hash(
        text,
        mode,
        includeArchived,
        type,
        Object.hashAllUnordered(tags),
      );
}

/// Данные, которые экран редактора отправляет на сервер.
class NoteDraft {
  const NoteDraft({
    required this.title,
    required this.type,
    this.content,
    this.url,
    this.tags = const <String>[],
  });

  final String title;
  final NoteType type;
  final String? content;
  final String? url;
  final List<String> tags;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'type': type.apiValue,
        // Пустая строка — способ очистить поле. В JSON «null» и «поле не
        // передано» для PATCH неразличимы, поэтому очистка выражается именно
        // пустой строкой — так это и описано в docs/api.md.
        'content': content ?? '',
        'url': url ?? '',
        'tags': tags,
      };
}
