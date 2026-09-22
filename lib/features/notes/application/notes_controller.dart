import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/providers.dart';
import '../data/models.dart';
import '../data/notes_repository.dart';

/// Состояние фильтров списка.
///
/// Отдельный провайдер, а не поле внутри списка: список пересобирается сам,
/// когда фильтр меняется, и ему не нужно знать, кто и почему его поменял.
class NotesQueryController extends Notifier<NotesQuery> {
  @override
  NotesQuery build() {
    // Фильтры относились к прошлому аккаунту и после смены пользователя
    // запросто оставили бы новый список пустым — сбрасываем их вместе с ним.
    ref.watch(currentUserIdProvider);
    return const NotesQuery();
  }

  void setText(String value) {
    if (state.text == value) return;
    state = state.copyWith(text: value);
  }

  void toggleTag(String tag) {
    final next = Set<String>.from(state.tags);
    if (!next.remove(tag)) {
      next.add(tag);
    }
    state = state.copyWith(tags: next);
  }

  void setMode(TagsMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
  }

  void setIncludeArchived(bool value) {
    if (state.includeArchived == value) return;
    state = state.copyWith(includeArchived: value);
  }

  /// Вход в корзину и выход из неё.
  ///
  /// Сбрасывает теги и архив: в корзине архив бэкенд не учитывает, а счётчики
  /// тегов относятся к активным записям — оставленные включёнными, они выглядели
  /// бы как работающие фильтры, ничего не фильтруя. Строка поиска сохраняется:
  /// искать по корзине — осмысленное действие.
  void setDeletedOnly(bool value) {
    if (state.deletedOnly == value) return;
    state = NotesQuery(
      text: state.text,
      mode: state.mode,
      type: state.type,
      deletedOnly: value,
    );
  }

  void setType(NoteType? type) {
    if (state.type == type) return;
    state = state.copyWith(type: type);
  }

  /// Снимает всё, кроме строки поиска: её пользователь стирает сам.
  void clearFilters() => state = state.withoutFilters();
}

final notesQueryProvider =
    NotifierProvider<NotesQueryController, NotesQuery>(NotesQueryController.new);

/// Загруженные страницы заметок.
class NotesState {
  const NotesState({
    required this.notes,
    required this.page,
    required this.hasNext,
    this.totalElements = 0,
    this.loadingMore = false,
    this.offline = false,
    this.loadMoreError,
    this.refreshError,
  });

  final List<Note> notes;
  final int page;
  final bool hasNext;
  final int totalElements;
  final bool loadingMore;

  /// Данные пришли из оффлайн-кеша: связи нет, показано последнее известное.
  final bool offline;

  /// Ошибка догрузки следующей страницы. Список при этом остаётся на экране —
  /// терять уже загруженное из-за обрыва связи незачем.
  final String? loadMoreError;

  /// Ошибка обновления списка. Тоже не стирает данные: пользователь видит
  /// баннер поверх того, что уже загружено.
  final String? refreshError;

  bool get isEmpty => notes.isEmpty;

  NotesState copyWith({
    List<Note>? notes,
    int? page,
    bool? hasNext,
    int? totalElements,
    bool? loadingMore,
    bool? offline,
    String? loadMoreError,
    String? refreshError,
    bool clearLoadMoreError = false,
    bool clearRefreshError = false,
  }) =>
      NotesState(
        notes: notes ?? this.notes,
        page: page ?? this.page,
        hasNext: hasNext ?? this.hasNext,
        totalElements: totalElements ?? this.totalElements,
        loadingMore: loadingMore ?? this.loadingMore,
        offline: offline ?? this.offline,
        loadMoreError:
            clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
        refreshError:
            clearRefreshError ? null : (refreshError ?? this.refreshError),
      );
}

class NotesController extends AsyncNotifier<NotesState> {
  @override
  Future<NotesState> build() async {
    // Записи принадлежат пользователю, и состояние провайдера живёт весь сеанс
    // приложения. Без этой зависимости после выхода и входа другим аккаунтом
    // на экране остались бы чужие записи: список просто не стал бы
    // перезапрашивать. Ошибка была настоящей и выглядела как утечка данных.
    ref.watch(currentUserIdProvider);

    // watch: смена фильтра пересобирает список автоматически.
    final query = ref.watch(notesQueryProvider);
    final result = await ref.watch(notesRepositoryProvider).list(query: query);
    return _stateFrom(result);
  }

  /// Полная перезагрузка — pull-to-refresh и после изменений.
  ///
  /// Ошибку не выбрасываем наружу: иначе уже загруженный список сменился бы
  /// красным экраном. Если данных ещё нет, показать ошибку больше нечем —
  /// тогда переводим состояние в AsyncError.
  Future<void> refresh() async {
    final query = ref.read(notesQueryProvider);
    final current = state.value;

    try {
      final result = await ref.read(notesRepositoryProvider).list(query: query);
      state = AsyncData(_stateFrom(result));
    } on ApiException catch (error) {
      if (current == null) {
        state = AsyncError<NotesState>(error, StackTrace.current);
        return;
      }
      state = AsyncData(
        current.copyWith(
          refreshError: error.displayMessage,
          clearLoadMoreError: true,
        ),
      );
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasNext || current.loadingMore) return;

    state = AsyncData(
      current.copyWith(
        loadingMore: true,
        clearLoadMoreError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final query = ref.read(notesQueryProvider);
      final result = await ref
          .read(notesRepositoryProvider)
          .list(query: query, page: current.page + 1);

      state = AsyncData(
        current.copyWith(
          notes: <Note>[...current.notes, ...result.page.items],
          page: result.page.page,
          hasNext: result.page.hasNext,
          totalElements: result.page.totalElements,
          loadingMore: false,
          // Догрузка удалась, значит связь есть: снимаем пометку оффлайна,
          // даже если первые страницы пришли из кеша.
          offline: result.fromCache,
          clearLoadMoreError: true,
          clearRefreshError: true,
        ),
      );
    } on ApiException catch (error) {
      state = AsyncData(
        current.copyWith(
          loadingMore: false,
          loadMoreError: error.displayMessage,
        ),
      );
    }
  }

  NotesState _stateFrom(NotesListResult result) => NotesState(
        notes: result.page.items,
        page: result.page.page,
        hasNext: result.page.hasNext,
        totalElements: result.page.totalElements,
        offline: result.fromCache,
      );
}

final notesControllerProvider =
    AsyncNotifierProvider<NotesController, NotesState>(NotesController.new);
