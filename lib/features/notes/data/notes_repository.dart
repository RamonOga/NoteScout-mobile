import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/models/page_result.dart';
import '../../../core/providers.dart';
import 'models.dart';
import 'notes_api.dart';
import 'notes_cache.dart';
import 'notes_cache_store_platform.dart';

/// Результат чтения списка вместе с признаком, откуда пришли данные.
///
/// Признак нужен экрану: показывать старое как свежее нельзя, об оффлайне
/// пользователь должен знать.
class NotesListResult {
  const NotesListResult({required this.page, required this.fromCache});

  final PageResult<Note> page;
  final bool fromCache;
}

/// Отбор заметок из снимка по тем же правилам, что применяет сервер.
///
/// Полнотекстовый поиск здесь проще серверного: там `tsquery` со стеммингом,
/// тут — подстрока без учёта регистра. Поэтому в оффлайне запрос «документац»
/// найдёт «документация», а «документации» может не найти. Это осознанное
/// упрощение: воспроизводить стемминг на клиенте — отдельная большая работа.
List<Note> matchNotes(Iterable<Note> notes, NotesQuery query) {
  final String text = query.text.trim().toLowerCase();
  final Set<String> wanted = query.tags.map((String tag) => tag.toLowerCase()).toSet();

  final List<Note> matched = notes.where((Note note) {
    // Режимы взаимоисключающие, как и на сервере: в корзине только удалённые,
    // вне неё — только живые.
    if (query.deletedOnly != note.isDeleted) return false;

    if (query.type != null && note.type != query.type) return false;
    // В корзине архив не учитывается: удалённую заметку нужно вернуть
    // независимо от того, лежала ли она в архиве.
    if (!query.deletedOnly && !query.includeArchived && note.isArchived) return false;

    if (wanted.isNotEmpty) {
      final Set<String> noteTags =
          note.tags.map((String tag) => tag.toLowerCase()).toSet();
      final bool hit = query.mode == TagsMode.all
          ? wanted.every(noteTags.contains)
          : wanted.any(noteTags.contains);
      if (!hit) return false;
    }

    if (text.isNotEmpty) {
      final String haystack =
          '${note.title}\n${note.content ?? ''}\n${note.url ?? ''}'.toLowerCase();
      if (!haystack.contains(text)) return false;
    }
    return true;
  }).toList(growable: false);

  // Сервер сортирует по релевантности, а при равной релевантности — по времени
  // изменения. Без полнотекстового ранжирования остаётся вторая часть.
  return matched
    ..sort((Note a, Note b) => b.updatedAt.compareTo(a.updatedAt));
}

/// Чтение заметок с оффлайн-кешем.
///
/// Сеть — всегда первый источник: кеш нужен ровно там, где сети нет. Поэтому
/// кеш не «ускоряет» загрузку и не подменяет ответы сервера, а только
/// подстраховывает обрыв связи.
class NotesRepository {
  NotesRepository({required this.api, this.cache});

  final NotesApi api;
  final NotesCache? cache;

  Future<NotesListResult> list({required NotesQuery query, int page = 0}) async {
    try {
      final PageResult<Note> result = await api.list(query: query, page: page);
      await _remember(result.items);
      return NotesListResult(page: result, fromCache: false);
    } on ApiException catch (error) {
      final NotesListResult? offline =
          await _fromCache(query: query, page: page, error: error);
      if (offline == null) rethrow;
      return offline;
    }
  }

  /// Заметка для редактора. Оффлайн отдаём из снимка, чтобы открыть и
  /// прочитать запись без сети было можно. Сохранить её оффлайн всё равно
  /// не выйдет — запись только онлайн.
  Future<Note> get(String id) async {
    try {
      final Note note = await api.get(id);
      await _remember(<Note>[note]);
      return note;
    } on ApiException catch (error) {
      if (!error.isNetworkFailure) rethrow;
      final NotesSnapshot? snapshot = await cache?.load();
      final Note? cached = snapshot?.notes
          .where((Note note) => note.id == id)
          .firstOrNull;
      if (cached == null) rethrow;
      return cached;
    }
  }

  Future<List<Tag>> tags() async {
    try {
      final List<Tag> tags = await api.tags();
      await cache?.update((NotesSnapshot snapshot) => snapshot.withTags(tags));
      return tags;
    } on ApiException catch (error) {
      if (!error.isNetworkFailure) rethrow;
      final NotesSnapshot? snapshot = await cache?.load();
      if (snapshot == null || snapshot.tags.isEmpty) rethrow;
      return snapshot.tags;
    }
  }

  // Изменяющие операции: кеш обновляется здесь, а не сам по себе.
  //
  // Удаление и восстановление иначе не отследить: список приходит без
  // изменённой заметки, и из ответа сервера нельзя понять, пропала она
  // потому, что её удалили, или потому, что не попала в фильтр.
  Future<void> rememberNote(Note note) async =>
      cache?.update((NotesSnapshot snapshot) => snapshot.withNotes(<Note>[note]));

  Future<void> forgetNote(String id) async =>
      cache?.update((NotesSnapshot snapshot) => snapshot.withoutNote(id));

  Future<void> clear() async => cache?.clear();

  Future<void> _remember(List<Note> notes) async {
    if (notes.isEmpty) return;
    await cache?.update((NotesSnapshot snapshot) => snapshot.withNotes(notes));
  }

  Future<NotesListResult?> _fromCache({
    required NotesQuery query,
    required int page,
    required ApiException error,
  }) async {
    // Только отсутствие связи: ошибка сервера — не повод показывать старое
    // и делать вид, что всё в порядке.
    if (!error.isNetworkFailure) return null;

    final NotesSnapshot? snapshot = await cache?.load();
    if (snapshot == null || snapshot.notes.isEmpty) return null;

    final List<Note> matched = matchNotes(snapshot.notes, query);
    const int size = NotesApi.pageSize;
    final int start = page * size;
    final List<Note> items = start >= matched.length
        ? const <Note>[]
        : matched.sublist(start, (start + size).clamp(0, matched.length));

    return NotesListResult(
      page: PageResult<Note>(
        items: items,
        page: page,
        size: size,
        totalElements: matched.length,
        totalPages: (matched.length / size).ceil(),
        hasNext: start + items.length < matched.length,
      ),
      fromCache: true,
    );
  }
}

/// Кеш текущего пользователя.
///
/// Зависит от идентификатора пользователя намеренно: смена аккаунта меняет
/// и файл снимка, поэтому чужие заметки не могут попасть в список — они лежат
/// в другом файле и просто не читаются.
final notesCacheProvider = Provider<NotesCache?>((Ref ref) {
  final String? userId = ref.watch(currentUserIdProvider);

  // Выход из аккаунта и его смена: снимок прежнего пользователя стираем.
  // Слушаем здесь, а не в SessionStore и не в AuthService: сессия не должна
  // знать про заметки, а аутентификация — тем более. Без этого тексты заметок
  // оставались бы лежать в каталоге приложения после выхода.
  ref.listen<String?>(currentUserIdProvider, (String? previous, String? next) {
    if (previous == null || previous == next) return;
    unawaited(
      createNotesCacheStore(previous).then(
        (NotesCacheStore? store) => store?.clear(),
      ),
    );
  });

  if (userId == null) return null;
  return NotesCache(createNotesCacheStore(userId));
});

final notesRepositoryProvider = Provider<NotesRepository>(
  (Ref ref) => NotesRepository(
    api: ref.watch(notesApiProvider),
    cache: ref.watch(notesCacheProvider),
  ),
);

/// Теги пользователя для панели фильтров.
///
/// FutureProvider, а не вечный кеш: после создания или удаления заметки
/// счётчики меняются, и список перезапрашивается через invalidate.
///
/// Живёт здесь, а не рядом с API, потому что оффлайн-откат — это уже забота
/// репозитория: без сети панель тегов должна показывать последние известные,
/// иначе она пропадёт вместе со связью.
final tagsProvider = FutureProvider<List<Tag>>((Ref ref) {
  // Теги тоже принадлежат пользователю — при смене аккаунта их нужно
  // запросить заново, иначе на панели останутся чужие.
  ref.watch(currentUserIdProvider);
  return ref.watch(notesRepositoryProvider).tags();
});
