import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/features/notes/data/models.dart';

void main() {
  group('NotesQuery', () {
    test('по умолчанию фильтров нет', () {
      const query = NotesQuery();

      expect(query.hasFilters, isFalse);
      expect(query.text, isEmpty);
      expect(query.tags, isEmpty);
      expect(query.mode, TagsMode.any);
      expect(query.includeArchived, isFalse);
      expect(query.deletedOnly, isFalse);
      expect(query.type, isNull);
    });

    test('режим корзины считается фильтром', () {
      const query = NotesQuery(deletedOnly: true);

      expect(query.hasFilters, isTrue);
    });

    test('copyWith меняет только переданные поля', () {
      const query = NotesQuery(text: 'док', tags: <String>{'java'});

      final updated = query.copyWith(includeArchived: true);

      expect(updated.text, 'док');
      expect(updated.tags, <String>{'java'});
      expect(updated.includeArchived, isTrue);
    });

    test('copyWith умеет сбросить тип записи в null', () {
      const query = NotesQuery(type: NoteType.link);

      final cleared = query.copyWith(type: null);

      expect(cleared.type, isNull);
      // Поле, которое не трогали, остаётся прежним.
      expect(cleared.mode, TagsMode.any);
    });

    test('withoutFilters сохраняет строку поиска', () {
      const query = NotesQuery(
        text: 'док',
        tags: <String>{'java'},
        includeArchived: true,
        deletedOnly: true,
        type: NoteType.link,
      );

      final cleared = query.withoutFilters();

      expect(cleared.text, 'док');
      expect(cleared.hasFilters, isTrue, reason: 'строка поиска — тоже фильтр');
      expect(cleared.tags, isEmpty);
      expect(cleared.includeArchived, isFalse);
      expect(cleared.deletedOnly, isFalse, reason: 'сброс выводит из корзины');
      expect(cleared.type, isNull);
    });

    test('равенство учитывает состав тегов, а не их порядок', () {
      const first = NotesQuery(tags: <String>{'java', 'kotlin'});
      const second = NotesQuery(tags: <String>{'kotlin', 'java'});

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('NoteDraft', () {
    test('пустые поля уходят пустой строкой — так поле очищается', () {
      const draft = NoteDraft(title: 'Тест', type: NoteType.text);

      final json = draft.toJson();

      expect(json['title'], 'Тест');
      expect(json['type'], 'TEXT');
      expect(json['content'], '');
      expect(json['url'], '');
      expect(json['tags'], isEmpty);
    });

    test('ссылка отправляется с типом LINK', () {
      const draft = NoteDraft(
        title: 'Spring',
        type: NoteType.link,
        url: 'https://spring.io',
        tags: <String>['java'],
      );

      final json = draft.toJson();

      expect(json['type'], 'LINK');
      expect(json['url'], 'https://spring.io');
      expect(json['tags'], <String>['java']);
    });
  });

  group('Note', () {
    test('разбирает ответ без необязательных полей', () {
      final note = Note.fromJson(<String, dynamic>{
        'id': 'id-1',
        'type': 'TEXT',
        'title': 'Заголовок',
        'tags': <String>['работа'],
        'createdAt': '2026-09-01T10:00:00Z',
        'updatedAt': '2026-09-02T10:00:00Z',
      });

      expect(note.type, NoteType.text);
      expect(note.content, isNull);
      expect(note.url, isNull);
      expect(note.isArchived, isFalse);
      expect(note.preview, isEmpty);
    });

    test('для ссылки preview показывает адрес', () {
      final note = Note.fromJson(<String, dynamic>{
        'id': 'id-2',
        'type': 'LINK',
        'title': 'Spring',
        'url': 'https://spring.io',
        'tags': <String>[],
        'createdAt': '2026-09-01T10:00:00Z',
        'updatedAt': '2026-09-02T10:00:00Z',
      });

      expect(note.type, NoteType.link);
      expect(note.preview, 'https://spring.io');
    });

    test('архивная запись помечается', () {
      final note = Note.fromJson(<String, dynamic>{
        'id': 'id-3',
        'type': 'TEXT',
        'title': 'Старое',
        'tags': <String>[],
        'createdAt': '2026-09-01T10:00:00Z',
        'updatedAt': '2026-09-02T10:00:00Z',
        'archivedAt': '2026-09-03T10:00:00Z',
      });

      expect(note.isArchived, isTrue);
    });

    test('удалённая запись помечается и хранит момент удаления', () {
      final note = Note.fromJson(<String, dynamic>{
        'id': 'id-4',
        'type': 'TEXT',
        'title': 'В корзине',
        'tags': <String>[],
        'createdAt': '2026-09-01T10:00:00Z',
        'updatedAt': '2026-09-04T10:00:00Z',
        'deletedAt': '2026-09-04T10:00:00Z',
      });

      expect(note.isDeleted, isTrue);
      expect(note.deletedAt, DateTime.parse('2026-09-04T10:00:00Z'));
    });

    test('активная запись удалённой не считается', () {
      final note = Note.fromJson(<String, dynamic>{
        'id': 'id-5',
        'type': 'TEXT',
        'title': 'Живая',
        'tags': <String>[],
        'createdAt': '2026-09-01T10:00:00Z',
        'updatedAt': '2026-09-02T10:00:00Z',
      });

      expect(note.isDeleted, isFalse);
      expect(note.deletedAt, isNull);
    });
  });
}
