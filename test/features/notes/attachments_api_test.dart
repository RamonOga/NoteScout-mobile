import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/features/notes/data/attachment.dart';
import 'package:notescout_mobile/features/notes/data/attachments_api.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/notes_fixtures.dart';

void main() {
  group('Attachment', () {
    test('разбирает ответ сервера', () {
      final Attachment attachment = Attachment.fromJson(
        attachmentJson(fileName: 'фото.jpg', contentType: 'image/jpeg', sizeBytes: 2048),
      );

      expect(attachment.fileName, 'фото.jpg');
      expect(attachment.sizeBytes, 2048);
      expect(attachment.isImage, isTrue);
    });

    test('не-картинка картинкой не считается', () {
      final Attachment attachment =
          Attachment.fromJson(attachmentJson(contentType: 'application/pdf'));

      expect(attachment.isImage, isFalse);
    });

    test('без content-type считает файл двоичным, а не картинкой', () {
      final Map<String, dynamic> json = attachmentJson()..remove('contentType');

      final Attachment attachment = Attachment.fromJson(json);

      expect(attachment.contentType, 'application/octet-stream');
      expect(attachment.isImage, isFalse);
    });
  });

  group('formatFileSize', () {
    test('байты, килобайты и мегабайты', () {
      expect(formatFileSize(512), '512 Б');
      expect(formatFileSize(2048), '2 КБ');
      expect(formatFileSize(2 * 1024 * 1024), '2.0 МБ');
    });
  });

  group('contentTypeForFileName', () {
    test('картинки опознаются по расширению в любом регистре', () {
      expect(contentTypeForFileName('фото.JPG'), 'image/jpeg');
      expect(contentTypeForFileName('снимок.png'), 'image/png');
    });

    test('неизвестное расширение не выдумывает тип', () {
      // Лучше отдать решение серверу, чем подставить неверный тип.
      expect(contentTypeForFileName('архив.rar'), isNull);
      expect(contentTypeForFileName('без-расширения'), isNull);
      expect(contentTypeForFileName('точка.'), isNull);
    });
  });

  group('AttachmentsApi', () {
    test('список вложений читается по пути заметки', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(<Map<String, dynamic>>[
          attachmentJson(id: 'a', fileName: 'первый.txt'),
          attachmentJson(id: 'b', fileName: 'второй.txt'),
        ]),
      );

      final List<Attachment> items =
          await AttachmentsApi(apiClient: dioWith(adapter)).list('note-1');

      expect(adapter.requestedPaths.single, '/notes/note-1/attachments');
      expect(items.map((Attachment a) => a.fileName), <String>['первый.txt', 'второй.txt']);
    });

    test('загрузка уходит multipart с именем и типом файла', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(attachmentJson(fileName: 'фото.jpg')),
      );

      await AttachmentsApi(apiClient: dioWith(adapter)).upload(
        'note-1',
        fileName: 'фото.jpg',
        bytes: <int>[1, 2, 3, 4],
        contentType: 'image/jpeg',
      );

      expect(adapter.requestedPaths.single, '/notes/note-1/attachments');

      final Object? body = adapter.requestBodies.single;
      expect(body, isA<FormData>());

      final FormData form = body! as FormData;
      expect(form.files, hasLength(1));
      // Поле называется file — так его ждёт контроллер на сервере.
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'фото.jpg');
      expect(form.files.single.value.length, 4);
      expect(form.files.single.value.contentType.toString(), contains('image/jpeg'));
    });

    test('скачивание запрашивает байты, а не JSON', () async {
      final adapter = FakeHttpAdapter(
        (_) async => ResponseBody.fromString(
          'abc',
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/octet-stream'],
          },
        ),
      );

      final List<int> bytes =
          await AttachmentsApi(apiClient: dioWith(adapter)).download('att-1');

      expect(adapter.requestedPaths.single, '/attachments/att-1/content');
      expect(bytes, <int>[97, 98, 99]);
      expect(adapter.requestOptions.single.responseType, ResponseType.bytes);
    });

    test('удаление идёт на путь вложения', () async {
      final adapter = FakeHttpAdapter((_) async => jsonResponse(<String, dynamic>{}));

      await AttachmentsApi(apiClient: dioWith(adapter)).delete('att-1');

      expect(adapter.requestedPaths.single, '/attachments/att-1');
    });

    test('занятое место разбирается из ответа', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(<String, dynamic>{
          'usedBytes': 3072,
          'limitBytes': 1073741824,
        }),
      );

      final AttachmentUsage usage =
          await AttachmentsApi(apiClient: dioWith(adapter)).usage();

      expect(adapter.requestedPaths.single, '/attachments/usage');
      expect(usage.usedBytes, 3072);
      expect(usage.limitBytes, 1073741824);
    });
  });
}
