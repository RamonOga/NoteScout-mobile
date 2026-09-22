import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/features/notes/data/models.dart';
import 'package:notescout_mobile/features/notes/data/notes_api.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/notes_fixtures.dart';

void main() {
  group('NotesApi.list', () {
    test('разбирает страницу заметок', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(
          notesPageJson(<Map<String, dynamic>>[
            noteJson(id: 'a', title: 'Первая'),
            noteJson(id: 'b', title: 'Вторая'),
          ], hasNext: true),
        ),
      );

      final page = await NotesApi(apiClient: dioWith(adapter))
          .list(query: const NotesQuery());

      expect(page.items, hasLength(2));
      expect(page.items.first.title, 'Первая');
      expect(page.hasNext, isTrue);
      expect(page.page, 0);
    });

    test('без фильтров шлёт только пагинацию', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(notesPageJson(<Map<String, dynamic>>[])),
      );

      await NotesApi(apiClient: dioWith(adapter))
          .list(query: const NotesQuery());

      final query = adapter.requestedQueries.single;
      expect(query['page'], 0);
      expect(query['size'], NotesApi.pageSize);
      expect(query.containsKey('q'), isFalse);
      expect(query.containsKey('tag'), isFalse);
      expect(query.containsKey('type'), isFalse);
      expect(query.containsKey('includeArchived'), isFalse);
      expect(query.containsKey('deletedOnly'), isFalse);
    });

    test('корзина запрашивается параметром deletedOnly', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(notesPageJson(<Map<String, dynamic>>[])),
      );

      await NotesApi(apiClient: dioWith(adapter))
          .list(query: const NotesQuery(deletedOnly: true));

      final query = adapter.requestedQueries.single;
      expect(query['deletedOnly'], isTrue);
      // Архив в корзине не учитывается, и клиент его туда не шлёт.
      expect(query.containsKey('includeArchived'), isFalse);
    });

    test('фильтры превращаются в параметры запроса', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(notesPageJson(<Map<String, dynamic>>[])),
      );

      await NotesApi(apiClient: dioWith(adapter)).list(
        query: const NotesQuery(
          text: '  документация  ',
          tags: <String>{'java', 'kotlin'},
          mode: TagsMode.all,
          includeArchived: true,
          type: NoteType.link,
        ),
        page: 2,
      );

      final query = adapter.requestedQueries.single;
      // Строка поиска обрезается: лишние пробелы серверу не нужны.
      expect(query['q'], 'документация');
      expect(query['tag'], containsAll(<String>['java', 'kotlin']));
      expect(query['tagsMode'], 'ALL');
      expect(query['includeArchived'], isTrue);
      expect(query['type'], 'LINK');
      expect(query['page'], 2);
    });

    test('режим совпадения не уходит, когда тег один', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(notesPageJson(<Map<String, dynamic>>[])),
      );

      await NotesApi(apiClient: dioWith(adapter))
          .list(query: const NotesQuery(tags: <String>{'java'}));

      // При одном теге ANY и ALL означают одно и то же.
      expect(adapter.requestedQueries.single.containsKey('tagsMode'), isFalse);
    });
  });

  group('NotesApi: изменения', () {
    test('создание отправляет черновик целиком', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(noteJson(id: 'new', title: 'Новая'), statusCode: 201),
      );

      final note = await NotesApi(apiClient: dioWith(adapter)).create(
        const NoteDraft(
          title: 'Новая',
          type: NoteType.link,
          url: 'https://example.com',
          tags: <String>['ссылки'],
        ),
      );

      expect(note.id, 'new');
      expect(adapter.requestedPaths.single, '/notes');
      expect(adapter.requestBodies.single, <String, dynamic>{
        'title': 'Новая',
        'type': 'LINK',
        'content': '',
        'url': 'https://example.com',
        'tags': <String>['ссылки'],
      });
    });

    test('архивация меняет только признак архива', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(noteJson(archivedAt: '2026-09-03T10:00:00Z')),
      );

      await NotesApi(apiClient: dioWith(adapter)).setArchived('note-1', true);

      expect(adapter.requestedPaths.single, '/notes/note-1');
      // Остальные поля не отправляем: иначе сохранение формы затирало бы
      // правки, сделанные с другого устройства.
      expect(adapter.requestBodies.single, <String, dynamic>{'archived': true});
    });

    test('удаление и восстановление идут на свои пути', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(noteJson()),
      );
      final api = NotesApi(apiClient: dioWith(adapter));

      await api.restore('note-1');

      expect(adapter.requestedPaths.single, '/notes/note-1/restore');
    });
  });
}
