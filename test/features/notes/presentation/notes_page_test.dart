import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/core/providers.dart';
import 'package:notescout_mobile/core/session/token_storage.dart';
import 'package:notescout_mobile/features/notes/data/notes_api.dart';
import 'package:notescout_mobile/features/notes/presentation/notes_page.dart';

import '../../../support/fake_http_adapter.dart';
import '../../../support/notes_fixtures.dart';

/// Панель фильтров запрашивает теги отдельно, поэтому отвечаем по пути.
Future<ResponseBody> Function(RequestOptions) _responder({
  required List<Map<String, dynamic>> notes,
  bool hasNext = false,
  bool failNotes = false,
  List<Map<String, dynamic>> tags = const <Map<String, dynamic>>[],
}) {
  return (RequestOptions options) async {
    if (options.path == '/tags') {
      return jsonResponse(tags);
    }
    if (failNotes) {
      return apiErrorResponse('INTERNAL_ERROR', 'Сервер прилёг', statusCode: 500);
    }
    return jsonResponse(notesPageJson(notes, hasNext: hasNext));
  };
}

/// Ответы для проверки корзины: содержимое зависит от режима, а на
/// восстановление приходит одиночная заметка, а не страница.
Future<ResponseBody> Function(RequestOptions) _trashResponder() {
  return (RequestOptions options) async {
    if (options.path == '/tags') {
      return jsonResponse(<Map<String, dynamic>>[]);
    }
    if (options.path.endsWith('/restore')) {
      return jsonResponse(noteJson(id: 'd', title: 'Удалённая'));
    }
    final deletedOnly = options.queryParameters['deletedOnly'] == true;
    return jsonResponse(
      notesPageJson(
        <Map<String, dynamic>>[
          deletedOnly
              ? noteJson(
                  id: 'd',
                  title: 'Удалённая',
                  deletedAt: '2026-09-04T10:00:00Z',
                )
              : noteJson(id: 'a', title: 'Активная'),
        ],
      ),
    );
  };
}

Widget _wrap(FakeHttpAdapter adapter, Widget child) => ProviderScope(
      overrides: [
        notesApiProvider.overrideWithValue(NotesApi(apiClient: dioWith(adapter))),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  group('NotesPage', () {
    testWidgets('показывает список заметок', (WidgetTester tester) async {
      final adapter = FakeHttpAdapter(
        _responder(
          notes: <Map<String, dynamic>>[
            noteJson(id: 'a', title: 'Документация Spring', tags: <String>['java']),
            noteJson(id: 'b', title: 'Рецепт борща'),
          ],
        ),
      );

      await tester.pumpWidget(_wrap(adapter, const NotesPage()));
      await tester.pumpAndSettle();

      expect(find.text('Документация Spring'), findsOneWidget);
      expect(find.text('Рецепт борща'), findsOneWidget);
      // Тег показан на карточке.
      expect(find.text('java'), findsOneWidget);
    });

    testWidgets('пустой список подсказывает создать запись',
        (WidgetTester tester) async {
      final adapter = FakeHttpAdapter(
        _responder(notes: <Map<String, dynamic>>[]),
      );

      await tester.pumpWidget(_wrap(adapter, const NotesPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Записей пока нет'), findsOneWidget);
      expect(find.text('Создать запись'), findsOneWidget);
    });

    testWidgets('ошибка загрузки предлагает повторить',
        (WidgetTester tester) async {
      final adapter = FakeHttpAdapter(_responder(notes: const [], failNotes: true));

      await tester.pumpWidget(_wrap(adapter, const NotesPage()));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось загрузить записи'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
    });

    testWidgets('фильтр по тегу появляется из ответа сервера',
        (WidgetTester tester) async {
      final adapter = FakeHttpAdapter(
        _responder(
          notes: <Map<String, dynamic>>[noteJson(title: 'Заметка')],
          tags: <Map<String, dynamic>>[
            <String, dynamic>{'id': 't1', 'name': 'работа', 'noteCount': 3},
          ],
        ),
      );

      await tester.pumpWidget(_wrap(adapter, const NotesPage()));
      await tester.pumpAndSettle();

      expect(find.text('работа · 3'), findsOneWidget);
    });

    testWidgets('корзина запрашивается отдельно и даёт восстановить запись',
        (WidgetTester tester) async {
      final adapter = FakeHttpAdapter(_trashResponder());

      await tester.pumpWidget(_wrap(adapter, const NotesPage()));
      await tester.pumpAndSettle();

      expect(find.text('Активная'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await tester.tap(find.text('Удалённые'));
      await tester.pumpAndSettle();

      // Список перезапрошен в режиме корзины, и в нём кнопка восстановления.
      expect(adapter.requestedQueries.last['deletedOnly'], isTrue);
      expect(find.text('Удалённая'), findsOneWidget);
      expect(find.text('Восстановить'), findsOneWidget);
      expect(find.textContaining('Удалено'), findsOneWidget);

      // Создавать в корзине нечего: новая запись туда не попадёт.
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.text('Восстановить'));
      await tester.pumpAndSettle();

      expect(adapter.requestedPaths, contains('/notes/d/restore'));
    });
  });
}
