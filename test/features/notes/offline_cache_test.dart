import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/core/error/api_exception.dart';
import 'package:notescout_mobile/features/notes/data/models.dart';
import 'package:notescout_mobile/features/notes/data/notes_api.dart';
import 'package:notescout_mobile/features/notes/data/notes_cache.dart';
import 'package:notescout_mobile/features/notes/data/notes_repository.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/in_memory_cache_store.dart';
import '../../support/notes_fixtures.dart';

/// Обрыв связи так, как его видит Dio: ответа нет вовсе.
Future<ResponseBody> _offline(RequestOptions options) async {
  throw DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
  );
}

Note _note({
  required String id,
  String title = 'Заметка',
  String? content,
  List<String> tags = const <String>[],
  String type = 'TEXT',
  String? archivedAt,
  String? deletedAt,
  String updatedAt = '2026-09-02T10:00:00Z',
}) {
  final Map<String, dynamic> json = noteJson(
    id: id,
    title: title,
    content: content,
    tags: tags,
    type: type,
    archivedAt: archivedAt,
    deletedAt: deletedAt,
  );
  json['updatedAt'] = updatedAt;
  return Note.fromJson(json);
}

void main() {
  group('NotesSnapshot', () {
    test('слияние заменяет заметку по идентификатору, а не дублирует', () {
      const NotesSnapshot empty = NotesSnapshot.empty();

      final NotesSnapshot once = empty.withNotes(<Note>[_note(id: 'a', title: 'Старое')]);
      final NotesSnapshot twice =
          once.withNotes(<Note>[_note(id: 'a', title: 'Новое'), _note(id: 'b')]);

      expect(twice.notes, hasLength(2));
      expect(
        twice.notes.firstWhere((Note note) => note.id == 'a').title,
        'Новое',
      );
    });

    test('withoutNote убирает запись', () {
      final NotesSnapshot snapshot = const NotesSnapshot.empty()
          .withNotes(<Note>[_note(id: 'a'), _note(id: 'b')]);

      expect(snapshot.withoutNote('a').notes.map((Note n) => n.id), <String>['b']);
    });

    test('переживает запись и чтение целиком', () {
      final NotesSnapshot original = const NotesSnapshot.empty()
          .withNotes(<Note>[_note(id: 'a', title: 'Заметка', tags: <String>['java'])])
          .withTags(<Tag>[
            const Tag(id: 't1', name: 'java', noteCount: 3),
          ]);

      final NotesSnapshot restored =
          NotesSnapshot.fromJson(original.toJson());

      expect(restored.notes.single.title, 'Заметка');
      expect(restored.notes.single.tags, <String>['java']);
      expect(restored.tags.single.name, 'java');
      expect(restored.tags.single.noteCount, 3);
    });
  });

  group('NotesCache', () {
    test('пустое хранилище — это отсутствие снимка, а не ошибка', () async {
      final cache = NotesCache.fromStore(InMemoryCacheStore());

      expect(await cache.load(), isNull);
    });

    test('битый снимок стирается, а не роняет чтение', () async {
      final store = InMemoryCacheStore(content: '{это не json');
      final cache = NotesCache.fromStore(store);

      expect(await cache.load(), isNull);
      expect(store.clears, 1, reason: 'мусор незачем хранить дальше');
    });

    test('update дописывает заметки к уже сохранённым', () async {
      final cache = NotesCache.fromStore(InMemoryCacheStore());

      await cache.update((NotesSnapshot s) => s.withNotes(<Note>[_note(id: 'a')]));
      await cache.update((NotesSnapshot s) => s.withNotes(<Note>[_note(id: 'b')]));

      final NotesSnapshot? snapshot = await cache.load();
      expect(snapshot!.notes.map((Note n) => n.id).toSet(), <String>{'a', 'b'});
    });
  });

  group('matchNotes', () {
    final List<Note> notes = <Note>[
      _note(id: 'a', title: 'Документация Spring', tags: <String>['java'], updatedAt: '2026-09-03T10:00:00Z'),
      _note(id: 'b', title: 'Рецепт борща', tags: <String>['еда'], updatedAt: '2026-09-01T10:00:00Z'),
      _note(id: 'c', title: 'Старое', tags: <String>['java'], archivedAt: '2026-08-01T10:00:00Z'),
      _note(id: 'd', title: 'Ссылка', type: 'LINK', tags: <String>['java'], updatedAt: '2026-09-04T10:00:00Z'),
    ];

    test('без фильтров отдаёт всё, кроме архива, и сортирует по времени', () {
      final List<Note> matched = matchNotes(notes, const NotesQuery());

      expect(matched.map((Note n) => n.id), <String>['d', 'a', 'b']);
    });

    test('архив показывается только по запросу', () {
      final List<Note> matched =
          matchNotes(notes, const NotesQuery(includeArchived: true));

      expect(matched.map((Note n) => n.id), contains('c'));
    });

    test('фильтр по типу', () {
      final List<Note> matched =
          matchNotes(notes, const NotesQuery(type: NoteType.link));

      expect(matched.map((Note n) => n.id), <String>['d']);
    });

    test('режимы ANY и ALL по тегам', () {
      final List<Note> any = matchNotes(
        notes,
        const NotesQuery(tags: <String>{'java', 'еда'}, mode: TagsMode.any),
      );
      final List<Note> all = matchNotes(
        notes,
        const NotesQuery(tags: <String>{'java', 'еда'}, mode: TagsMode.all),
      );

      expect(any.map((Note n) => n.id).toSet(), <String>{'a', 'b', 'd'});
      expect(all, isEmpty);
    });

    test('поиск по тексту не зависит от регистра и ищет в тексте заметки', () {
      final List<Note> byTitle =
          matchNotes(notes, const NotesQuery(text: 'докум'));
      final List<Note> byContent = matchNotes(
        <Note>[_note(id: 'x', title: 'Заголовок', content: 'Внутри про Kotlin')],
        const NotesQuery(text: 'kotlin'),
      );

      expect(byTitle.map((Note n) => n.id), <String>['a']);
      expect(byContent.map((Note n) => n.id), <String>['x']);
    });

    test('корзина показывает только удалённые, а обычный список — только живые',
        () {
      final List<Note> all = <Note>[
        _note(id: 'alive', title: 'Живая'),
        _note(
          id: 'gone',
          title: 'Удалённая',
          deletedAt: '2026-09-05T10:00:00Z',
          updatedAt: '2026-09-05T10:00:00Z',
        ),
      ];

      expect(
        matchNotes(all, const NotesQuery()).map((Note n) => n.id),
        <String>['alive'],
      );
      expect(
        matchNotes(all, const NotesQuery(deletedOnly: true)).map((Note n) => n.id),
        <String>['gone'],
      );
    });

    test('в корзине архив не мешает показать удалённую заметку', () {
      // Заметку могли удалить уже из архива — вернуть её всё равно нужно.
      final List<Note> archived = <Note>[
        _note(
          id: 'gone',
          archivedAt: '2026-08-01T10:00:00Z',
          deletedAt: '2026-09-05T10:00:00Z',
        ),
      ];

      expect(
        matchNotes(archived, const NotesQuery(deletedOnly: true)),
        hasLength(1),
      );
      expect(matchNotes(archived, const NotesQuery()), isEmpty);
    });
  });

  group('NotesRepository', () {
    test('удачный ответ попадает в снимок', () async {
      final store = InMemoryCacheStore();
      final repository = NotesRepository(
        api: NotesApi(
          apiClient: dioWith(
            FakeHttpAdapter(
              (_) async => jsonResponse(
                notesPageJson(<Map<String, dynamic>>[noteJson(id: 'a', title: 'A')]),
              ),
            ),
          ),
        ),
        cache: NotesCache.fromStore(store),
      );

      final NotesListResult result = await repository.list(query: const NotesQuery());

      expect(result.fromCache, isFalse);
      expect((await NotesCache.fromStore(store).load())!.notes.single.title, 'A');
    });

    test('обрыв связи отдаёт снимок и помечает данные оффлайном', () async {
      final store = InMemoryCacheStore();
      final cache = NotesCache.fromStore(store);
      await cache.update(
        (NotesSnapshot s) => s.withNotes(<Note>[_note(id: 'a', title: 'Из кеша')]),
      );

      final repository = NotesRepository(
        api: NotesApi(apiClient: dioWith(FakeHttpAdapter(_offline))),
        cache: cache,
      );

      final NotesListResult result = await repository.list(query: const NotesQuery());

      expect(result.fromCache, isTrue);
      expect(result.page.items.single.title, 'Из кеша');
      expect(result.page.totalElements, 1);
    });

    test('без снимка обрыв связи остаётся ошибкой', () async {
      final repository = NotesRepository(
        api: NotesApi(apiClient: dioWith(FakeHttpAdapter(_offline))),
        cache: NotesCache.fromStore(InMemoryCacheStore()),
      );

      await expectLater(
        repository.list(query: const NotesQuery()),
        throwsA(isA<ApiException>()),
      );
    });

    test('ошибку сервера кешем не подменяем', () async {
      final store = InMemoryCacheStore();
      final cache = NotesCache.fromStore(store);
      await cache.update((NotesSnapshot s) => s.withNotes(<Note>[_note(id: 'a')]));

      final repository = NotesRepository(
        api: NotesApi(
          apiClient: dioWith(
            FakeHttpAdapter(
              (_) async =>
                  apiErrorResponse('INTERNAL_ERROR', 'Сервер прилёг', statusCode: 500),
            ),
          ),
        ),
        cache: cache,
      );

      // Показать старое вместо ошибки сервера — значит скрыть поломку.
      await expectLater(
        repository.list(query: const NotesQuery()),
        throwsA(isA<ApiException>()),
      );
    });

    test('forgetNote убирает заметку из снимка', () async {
      final cache = NotesCache.fromStore(InMemoryCacheStore());
      await cache.update((NotesSnapshot s) => s.withNotes(<Note>[_note(id: 'a')]));

      final repository = NotesRepository(
        api: NotesApi(apiClient: dioWith(FakeHttpAdapter(_offline))),
        cache: cache,
      );
      await repository.forgetNote('a');

      final NotesSnapshot? snapshot = await cache.load();
      expect(snapshot!.notes, isEmpty);
    });

    test('теги оффлайн берутся из снимка', () async {
      final cache = NotesCache.fromStore(InMemoryCacheStore());
      await cache.update(
        (NotesSnapshot s) => s.withTags(<Tag>[
          const Tag(id: 't1', name: 'java', noteCount: 3),
        ]),
      );

      final repository = NotesRepository(
        api: NotesApi(apiClient: dioWith(FakeHttpAdapter(_offline))),
        cache: cache,
      );

      final List<Tag> tags = await repository.tags();
      expect(tags.single.name, 'java');
    });

    test('вторая страница оффлайна отдаётся из снимка по частям', () async {
      final store = InMemoryCacheStore();
      final cache = NotesCache.fromStore(store);
      await cache.update(
        (NotesSnapshot s) => s.withNotes(<Note>[
          for (int i = 0; i < 25; i++)
            _note(id: 'n$i', title: 'Заметка $i', updatedAt: '2026-09-01T10:00:00Z'),
        ]),
      );

      final repository = NotesRepository(
        api: NotesApi(apiClient: dioWith(FakeHttpAdapter(_offline))),
        cache: cache,
      );

      final NotesListResult first = await repository.list(query: const NotesQuery());
      final NotesListResult second =
          await repository.list(query: const NotesQuery(), page: 1);

      expect(first.page.items, hasLength(NotesApi.pageSize));
      expect(first.page.hasNext, isTrue);
      expect(second.page.items, hasLength(5));
      expect(second.page.hasNext, isFalse);
    });
  });
}
