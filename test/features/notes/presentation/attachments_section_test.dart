import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/features/notes/data/attachments_api.dart';
import 'package:notescout_mobile/features/notes/presentation/widgets/attachments_section.dart';

import '../../../support/fake_http_adapter.dart';
import '../../../support/notes_fixtures.dart';

Widget _wrap(FakeHttpAdapter adapter) => ProviderScope(
      overrides: [
        attachmentsApiProvider
            .overrideWithValue(AttachmentsApi(apiClient: dioWith(adapter))),
      ],
      child: const MaterialApp(
        home: Scaffold(body: AttachmentsSection(noteId: 'note-1')),
      ),
    );

void main() {
  group('AttachmentsSection', () {
    testWidgets('показывает список файлов с размерами',
        (WidgetTester tester) async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(<Map<String, dynamic>>[
          attachmentJson(id: 'a', fileName: 'фото.jpg', contentType: 'image/jpeg', sizeBytes: 2048),
          attachmentJson(id: 'b', fileName: 'документ.pdf', contentType: 'application/pdf', sizeBytes: 1024),
        ]),
      );

      await tester.pumpWidget(_wrap(adapter));
      await tester.pumpAndSettle();

      expect(find.text('фото.jpg'), findsOneWidget);
      expect(find.text('документ.pdf'), findsOneWidget);
      expect(find.text('2 КБ'), findsOneWidget);
      expect(find.text('1 КБ'), findsOneWidget);
      expect(adapter.requestedPaths.single, '/notes/note-1/attachments');
    });

    testWidgets('пустой список говорит об этом, а не молчит',
        (WidgetTester tester) async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(<Map<String, dynamic>>[]),
      );

      await tester.pumpWidget(_wrap(adapter));
      await tester.pumpAndSettle();

      expect(find.text('Файлов нет'), findsOneWidget);
      expect(find.text('Приложить'), findsOneWidget);
    });

    testWidgets('удаление убирает файл из списка',
        (WidgetTester tester) async {
      final adapter = FakeHttpAdapter((options) async {
        if (options.method == 'DELETE') {
          return jsonResponse(<String, dynamic>{});
        }
        return jsonResponse(<Map<String, dynamic>>[
          attachmentJson(id: 'a', fileName: 'лишний.txt'),
        ]);
      });

      await tester.pumpWidget(_wrap(adapter));
      await tester.pumpAndSettle();
      expect(find.text('лишний.txt'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(adapter.requestedPaths.last, '/attachments/a');
      expect(find.text('лишний.txt'), findsNothing);
    });

    testWidgets('у не-картинки просмотр честно не обещается',
        (WidgetTester tester) async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(<Map<String, dynamic>>[
          attachmentJson(id: 'a', fileName: 'документ.pdf', contentType: 'application/pdf'),
        ]),
      );

      await tester.pumpWidget(_wrap(adapter));
      await tester.pumpAndSettle();

      await tester.tap(find.text('документ.pdf'));
      await tester.pumpAndSettle();

      // Скачивать нечего: открыть такой файл приложение пока не умеет,
      // и делать вид, что умеет, не нужно.
      expect(find.textContaining('не поддерживается'), findsOneWidget);
      expect(adapter.requestedPaths, hasLength(1));
    });
  });
}
