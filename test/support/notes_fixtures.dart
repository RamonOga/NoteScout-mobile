import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/features/notes/data/notes_api.dart';

import 'fake_http_adapter.dart';

/// Заметка в том виде, в каком её отдаёт бэкенд.
Map<String, dynamic> noteJson({
  String id = '11111111-1111-1111-1111-111111111111',
  String type = 'TEXT',
  String title = 'Заметка',
  String? content,
  String? url,
  List<String> tags = const <String>[],
  String? archivedAt,
  String? deletedAt,
}) =>
    <String, dynamic>{
      'id': id,
      'type': type,
      'title': title,
      'tags': tags,
      'createdAt': '2026-09-01T10:00:00Z',
      'updatedAt': '2026-09-02T10:00:00Z',
      // null-поля бэкенд не присылает вовсе (non_null inclusion), поэтому
      // и здесь их не кладём — тест должен видеть ту же форму ответа.
      // Null-aware элементы опускают запись, если значение null.
      'content': ?content,
      'url': ?url,
      'archivedAt': ?archivedAt,
      'deletedAt': ?deletedAt,
    };

/// Вложение в том виде, в каком его отдаёт бэкенд.
Map<String, dynamic> attachmentJson({
  String id = '22222222-2222-2222-2222-222222222222',
  String fileName = 'файл.txt',
  String contentType = 'text/plain',
  int sizeBytes = 1024,
  String createdAt = '2026-09-10T10:00:00Z',
}) =>
    <String, dynamic>{
      'id': id,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'createdAt': createdAt,
    };

/// Страница списка заметок.
Map<String, dynamic> notesPageJson(
  List<Map<String, dynamic>> notes, {
  int page = 0,
  int size = 20,
  bool hasNext = false,
}) =>
    <String, dynamic>{
      'items': notes,
      'page': page,
      'size': size,
      'totalElements': notes.length,
      'totalPages': hasNext ? page + 2 : page + 1,
      'hasNext': hasNext,
    };

/// Контейнер Riverpod с подменённым транспортом заметок.
///
/// Api и контроллер проверяются вместе: подменяется только сеть, поэтому
/// в тесте участвует настоящая сборка запроса и настоящее состояние.
ProviderContainer notesContainer(FakeHttpAdapter adapter) {
  final container = ProviderContainer(
    // Тип элемента — Override; из flutter_riverpod он не экспортируется,
    // поэтому список задаётся без явного аргумента типа.
    overrides: [
      notesApiProvider.overrideWithValue(NotesApi(apiClient: dioWith(adapter))),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
