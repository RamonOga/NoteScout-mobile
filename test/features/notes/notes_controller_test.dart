import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/core/error/api_exception.dart';
import 'package:notescout_mobile/features/notes/application/notes_controller.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/notes_fixtures.dart';

void main() {
  group('NotesController', () {
    test('загружает первую страницу', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(
          notesPageJson(<Map<String, dynamic>>[
            noteJson(id: 'a', title: 'Первая'),
            noteJson(id: 'b', title: 'Вторая'),
          ]),
        ),
      );
      final container = notesContainer(adapter);

      final state = await container.read(notesControllerProvider.future);

      expect(state.notes, hasLength(2));
      expect(state.notes.first.title, 'Первая');
      expect(state.hasNext, isFalse);
    });

    test('смена фильтра перезапрашивает список', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(notesPageJson(<Map<String, dynamic>>[noteJson()])),
      );
      final container = notesContainer(adapter);

      await container.read(notesControllerProvider.future);
      expect(adapter.requestedQueries.single.containsKey('q'), isFalse);

      container.read(notesQueryProvider.notifier).setText('докум');
      await container.read(notesControllerProvider.future);

      expect(adapter.requestedQueries, hasLength(2));
      expect(adapter.requestedQueries.last['q'], 'докум');
    });

    test('вход в корзину сбрасывает теги и архив', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(notesPageJson(<Map<String, dynamic>>[])),
      );
      final container = notesContainer(adapter);

      await container.read(notesControllerProvider.future);

      final queries = container.read(notesQueryProvider.notifier);
      queries.toggleTag('java');
      queries.setIncludeArchived(true);
      await container.read(notesControllerProvider.future);

      queries.setDeletedOnly(true);
      await container.read(notesControllerProvider.future);

      final last = adapter.requestedQueries.last;
      expect(last['deletedOnly'], isTrue);
      // Теги и архив в корзине смысла не имеют: счётчики тегов считают только
      // активные записи, а архив бэкенд в этом режиме не учитывает.
      expect(last.containsKey('tag'), isFalse);
      expect(last.containsKey('includeArchived'), isFalse);

      final query = container.read(notesQueryProvider);
      expect(query.tags, isEmpty);
      expect(query.includeArchived, isFalse);
    });

    test('выход из корзины возвращает обычный список', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(notesPageJson(<Map<String, dynamic>>[])),
      );
      final container = notesContainer(adapter);

      final queries = container.read(notesQueryProvider.notifier);
      queries.setDeletedOnly(true);
      await container.read(notesControllerProvider.future);
      expect(adapter.requestedQueries.last['deletedOnly'], isTrue);

      queries.setDeletedOnly(false);
      await container.read(notesControllerProvider.future);

      expect(adapter.requestedQueries.last.containsKey('deletedOnly'), isFalse);
    });

    test('догрузка добавляет следующую страницу и останавливается', () async {
      final adapter = FakeHttpAdapter((options) async {
        final page = options.queryParameters['page'] as int;
        return jsonResponse(
          notesPageJson(
            <Map<String, dynamic>>[noteJson(id: 'page-$page', title: 'Страница $page')],
            page: page,
            hasNext: page == 0,
          ),
        );
      });
      final container = notesContainer(adapter);

      await container.read(notesControllerProvider.future);
      await container.read(notesControllerProvider.notifier).loadMore();

      var state = container.read(notesControllerProvider).value!;
      expect(state.notes, hasLength(2));
      expect(state.hasNext, isFalse);

      // Вторая догрузка ничего не делает: страниц больше нет.
      await container.read(notesControllerProvider.notifier).loadMore();
      state = container.read(notesControllerProvider).value!;
      expect(state.notes, hasLength(2));
      expect(adapter.requestedQueries, hasLength(2));
    });

    test('ошибка обновления не стирает уже загруженный список', () async {
      var failNext = false;
      final adapter = FakeHttpAdapter((_) async {
        if (failNext) {
          return apiErrorResponse('INTERNAL_ERROR', 'Сервер прилёг', statusCode: 500);
        }
        return jsonResponse(
          notesPageJson(<Map<String, dynamic>>[noteJson(title: 'Уцелевшая')]),
        );
      });
      final container = notesContainer(adapter);

      await container.read(notesControllerProvider.future);

      failNext = true;
      await container.read(notesControllerProvider.notifier).refresh();

      final asyncState = container.read(notesControllerProvider);
      final state = asyncState.value!;

      expect(state.notes, hasLength(1), reason: 'данные должны остаться на экране');
      expect(state.refreshError, isNotNull);
      expect(state.refreshError, contains('Сервер прилёг'));
    });

    test('ошибка первой загрузки доходит до состояния', () async {
      final adapter = FakeHttpAdapter(
        (_) async => apiErrorResponse('INTERNAL_ERROR', 'Сервер прилёг', statusCode: 500),
      );
      final container = notesContainer(adapter);

      // Слушаем состояние, а не читаем future: контейнер отдаёт AsyncLoading
      // синхронно, и ошибку можно поймать только подпиской.
      final failure = Completer<Object>();
      container.listen<AsyncValue<NotesState>>(
        notesControllerProvider,
        (previous, next) {
          if (next.hasError && !failure.isCompleted) {
            failure.complete(next.error!);
          }
        },
        fireImmediately: true,
      );

      final Object error = await failure.future.timeout(const Duration(seconds: 5));

      expect(error, isA<ApiException>());
      expect((error as ApiException).message, 'Сервер прилёг');
    });

    test('успешная догрузка сбрасывает прошлую ошибку', () async {
      var failNext = false;
      final adapter = FakeHttpAdapter((options) async {
        final page = options.queryParameters['page'] as int;
        if (failNext) {
          return apiErrorResponse('INTERNAL_ERROR', 'Обрыв', statusCode: 500);
        }
        return jsonResponse(
          notesPageJson(
            <Map<String, dynamic>>[noteJson(id: 'p$page')],
            page: page,
            hasNext: true,
          ),
        );
      });
      final container = notesContainer(adapter);

      await container.read(notesControllerProvider.future);

      failNext = true;
      await container.read(notesControllerProvider.notifier).loadMore();
      expect(container.read(notesControllerProvider).value!.loadMoreError, isNotNull);

      failNext = false;
      await container.read(notesControllerProvider.notifier).loadMore();
      expect(container.read(notesControllerProvider).value!.loadMoreError, isNull);
    });
  });
}
