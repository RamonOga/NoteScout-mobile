import 'dart:convert';

import 'models.dart';

/// Снимок данных пользователя, сохранённый для оффлайна.
///
/// Хранится в том виде, в каком пришёл от сервера: набор заметок и теги.
/// Это важнее, чем кажется: снимок ничего не знает про схему таблиц, поэтому
/// новое поле в модели не требует миграции — старый снимок прочитается без
/// него, а не сломается.
class NotesSnapshot {
  const NotesSnapshot({
    required this.notes,
    required this.tags,
    this.savedAt,
  });

  const NotesSnapshot.empty()
      : notes = const <Note>[],
        tags = const <Tag>[],
        savedAt = null;

  final List<Note> notes;
  final List<Tag> tags;
  final DateTime? savedAt;

  bool get isEmpty => notes.isEmpty && tags.isEmpty;

  /// Добавляет заметки, заменяя уже известные по идентификатору.
  ///
  /// Именно слияние, а не замена: снимок собирается из всех удачных ответов,
  /// а они приходят постранично и под разными фильтрами.
  NotesSnapshot withNotes(Iterable<Note> incoming) {
    if (incoming.isEmpty) return this;
    final byId = <String, Note>{for (final Note note in notes) note.id: note};
    for (final Note note in incoming) {
      byId[note.id] = note;
    }
    return NotesSnapshot(
      notes: byId.values.toList(growable: false),
      tags: tags,
      savedAt: savedAt,
    );
  }

  /// Убирает заметку: после удаления её в кеше быть не должно, иначе она
  /// вернётся в список при первом же обрыве связи.
  NotesSnapshot withoutNote(String id) => NotesSnapshot(
        notes: notes.where((Note note) => note.id != id).toList(growable: false),
        tags: tags,
        savedAt: savedAt,
      );

  NotesSnapshot withTags(List<Tag> incoming) => NotesSnapshot(
        notes: notes,
        tags: incoming,
        savedAt: savedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'savedAt': savedAt?.toIso8601String(),
        'notes': notes.map((Note note) => note.toJson()).toList(growable: false),
        'tags': tags.map((Tag tag) => tag.toJson()).toList(growable: false),
      };

  factory NotesSnapshot.fromJson(Map<String, dynamic> json) => NotesSnapshot(
        savedAt: json['savedAt'] == null
            ? null
            : DateTime.parse(json['savedAt'] as String),
        notes: (json['notes'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(Note.fromJson)
            .toList(growable: false),
        tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(Tag.fromJson)
            .toList(growable: false),
      );
}

/// Место, где лежит снимок.
///
/// Отдельный интерфейс ради двух вещей: тесты подставляют память, а на web
/// каталога приложения нет, и там хранилище не создаётся вовсе.
abstract class NotesCacheStore {
  Future<String?> read();
  Future<void> write(String content);
  Future<void> clear();
}

/// Кеш заметок одного пользователя.
class NotesCache {
  /// Создание хранилища асинхронное — каталог приложения спрашивается
  /// у платформы, — поэтому здесь Future. Наружу это не протекает: методы
  /// кеша сами дожидаются готовности.
  NotesCache(this._store);

  NotesCache.fromStore(NotesCacheStore store)
      : _store = Future<NotesCacheStore?>.value(store);

  final Future<NotesCacheStore?> _store;

  /// Читает снимок. Битый или оставшийся от старой версии — не повод падать
  /// и не повод показывать пустоту: просто начинаем копить заново.
  Future<NotesSnapshot?> load() async {
    final NotesCacheStore? store = await _store;
    if (store == null) return null;
    final String? raw = await store.read();
    if (raw == null) return null;
    try {
      return NotesSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await store.clear();
      return null;
    }
  }

  /// Читает снимок, применяет изменение и сохраняет обратно.
  Future<void> update(NotesSnapshot Function(NotesSnapshot snapshot) change) async {
    final NotesCacheStore? store = await _store;
    if (store == null) return;
    final NotesSnapshot current = await load() ?? const NotesSnapshot.empty();
    final NotesSnapshot next = change(current);
    await store.write(
      jsonEncode(
        NotesSnapshot(
          notes: next.notes,
          tags: next.tags,
          savedAt: DateTime.now(),
        ).toJson(),
      ),
    );
  }

  Future<void> clear() async {
    final NotesCacheStore? store = await _store;
    await store?.clear();
  }
}
