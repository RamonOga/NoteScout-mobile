import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/models/page_result.dart';
import '../../../core/providers.dart';
import 'models.dart';

/// Вызовы эндпоинтов заметок и тегов.
///
/// Ошибки превращаются в ApiException здесь же, поэтому выше по стеку
/// с Dio никто не работает.
class NotesApi {
  NotesApi({required this.apiClient});

  final Dio apiClient;

  /// Сколько записей запрашиваем за раз.
  static const int pageSize = 20;

  Future<PageResult<Note>> list({
    required NotesQuery query,
    int page = 0,
  }) =>
      guardApi(() async {
        final response = await apiClient.get<Map<String, dynamic>>(
          '/notes',
          queryParameters: <String, dynamic>{
            'page': page,
            'size': pageSize,
            if (query.text.trim().isNotEmpty) 'q': query.text.trim(),
            // Список уходит повторяющимися параметрами: ?tag=работа&tag=java
            if (query.tags.isNotEmpty) 'tag': query.tags.toList(growable: false),
            // Режим имеет смысл только когда тегов больше одного.
            if (query.tags.length > 1) 'tagsMode': query.mode.apiValue,
            if (query.includeArchived) 'includeArchived': true,
            // Null-aware элемент: поле уходит только если тип выбран.
            'type': ?query.type?.apiValue,
          },
        );
        return PageResult.fromJson(response.data!, Note.fromJson);
      });

  Future<Note> get(String id) => guardApi(() async {
        final response = await apiClient.get<Map<String, dynamic>>('/notes/$id');
        return Note.fromJson(response.data!);
      });

  Future<Note> create(NoteDraft draft) => guardApi(() async {
        final response = await apiClient.post<Map<String, dynamic>>(
          '/notes',
          data: draft.toJson(),
        );
        return Note.fromJson(response.data!);
      });

  /// Частичное обновление. Поля, которых нет в [draft], всё равно уходят:
  /// редактор всегда знает состояние целиком, и так снимается вопрос
  /// «а что будет, если поле не прислать».
  Future<Note> update(String id, NoteDraft draft, {bool? archived}) =>
      guardApi(() async {
        final response = await apiClient.patch<Map<String, dynamic>>(
          '/notes/$id',
          data: <String, dynamic>{
            ...draft.toJson(),
            'archived': ?archived,
          },
        );
        return Note.fromJson(response.data!);
      });

  Future<void> delete(String id) => guardApi(() async {
        await apiClient.delete<void>('/notes/$id');
      });

  /// Отправляет и возвращает из архива, не трогая остальные поля.
  Future<Note> setArchived(String id, bool archived) => guardApi(() async {
        final response = await apiClient.patch<Map<String, dynamic>>(
          '/notes/$id',
          data: <String, dynamic>{'archived': archived},
        );
        return Note.fromJson(response.data!);
      });

  Future<Note> restore(String id) => guardApi(() async {
        final response =
            await apiClient.post<Map<String, dynamic>>('/notes/$id/restore');
        return Note.fromJson(response.data!);
      });

  Future<List<Tag>> tags() => guardApi(() async {
        final response = await apiClient.get<List<dynamic>>('/tags');
        return (response.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Tag.fromJson)
            .toList(growable: false);
      });
}

final notesApiProvider = Provider<NotesApi>(
  (ref) => NotesApi(apiClient: ref.watch(apiClientProvider)),
);

/// Теги пользователя для панели фильтров.
///
/// FutureProvider, а не вечный кеш: после создания или удаления заметки
/// счётчики меняются, и список перезапрашивается через invalidate.
final tagsProvider = FutureProvider<List<Tag>>(
  (ref) => ref.watch(notesApiProvider).tags(),
);
