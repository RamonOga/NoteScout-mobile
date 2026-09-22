import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../auth/application/auth_service.dart';
import '../application/note_actions.dart';
import '../application/notes_controller.dart';
import '../data/models.dart';
import 'widgets/note_card.dart';
import 'widgets/tag_filter_bar.dart';

/// Список заметок с поиском, фильтром по тегам и подгрузкой страниц.
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  /// Насколько заранее начинать догрузку следующей страницы.
  static const double _loadMoreThreshold = 300;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      ref.read(notesControllerProvider.notifier).loadMore();
    }
  }

  /// Запрос уходит не на каждое нажатие: пока пользователь печатает,
  /// предыдущие ответы всё равно устаревают.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(notesQueryProvider.notifier).setText(value);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(notesQueryProvider.notifier).setText('');
  }

  /// Возвращает заметку из корзины. Список обновится сам: NoteActions после
  /// изменения инвалидирует и список, и счётчики тегов.
  Future<void> _restore(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(noteActionsProvider).restore(id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Заметка восстановлена')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.displayMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(notesQueryProvider);
    final notes = ref.watch(notesControllerProvider);
    final refreshError = notes.value?.refreshError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NoteScout'),
        actions: <Widget>[
          IconButton(
            onPressed: () => ref.read(authServiceProvider).signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
          ),
        ],
      ),
      // В корзине создавать нечего: новая запись туда не попадёт и появится
      // только после выхода из корзины.
      floatingActionButton: query.deletedOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go(AppRoutes.noteNew),
              icon: const Icon(Icons.add),
              label: const Text('Запись'),
            ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск по заголовку и тексту',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Очистить',
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          const TagFilterBar(),
          // Тонкая полоса вместо подмены списка: при смене фильтра старые
          // результаты остаются на экране, пока грузятся новые.
          if (notes.isLoading && notes.hasValue)
            const LinearProgressIndicator(minHeight: 2),
          if (refreshError != null)
            _RefreshErrorBanner(
              message: refreshError,
              onRetry: () =>
                  ref.read(notesControllerProvider.notifier).refresh(),
            ),
          Expanded(
            child: notes.when(
              // Не сбрасываем список в спиннер при смене фильтра или поиска.
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, _) => _ErrorState(
                message: error.toString(),
                onRetry: () =>
                    ref.read(notesControllerProvider.notifier).refresh(),
              ),
              data: (NotesState state) => _buildList(state, query),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(NotesState state, NotesQuery query) {
    if (state.isEmpty) {
      return _EmptyState(
        query: query,
        onCreate: () => context.go(AppRoutes.noteNew),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(notesControllerProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: state.notes.length + (state.hasNext ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= state.notes.length) {
            return _LoadMoreTile(
              error: state.loadMoreError,
              onRetry: () => ref.read(notesControllerProvider.notifier).loadMore(),
            );
          }

          final note = state.notes[index];

          // В корзине карточка не открывается в редакторе: GET /notes/{id} для
          // удалённой записи отвечает 404, и переход вёл бы в экран ошибки.
          if (query.deletedOnly) {
            return NoteCard(note: note, onRestore: () => _restore(note.id));
          }

          return NoteCard(
            note: note,
            onTap: () => context.go(AppRoutes.noteEdit(note.id)),
          );
        },
      ),
    );
  }
}

/// Баннер поверх списка: обновление не удалось, но данные остались на экране.
class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreTile extends StatelessWidget {  const _LoadMoreTile({this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query, required this.onCreate});

  final NotesQuery query;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searched = query.text.trim().isNotEmpty;

    final String message;
    if (query.deletedOnly) {
      message = searched
          ? 'В корзине ничего не найдено.'
          : 'Корзина пуста.\nУдалённые записи можно восстановить отсюда.';
    } else if (query.hasFilters) {
      message = 'Ничего не найдено.\nПопробуйте изменить запрос или снять фильтры.';
    } else {
      message = 'Записей пока нет.\nСоздайте первую — заметку или ссылку.';
    }

    // Кнопка «Создать» уместна только в пустом основном списке: в корзине и при
    // активных фильтрах она предлагает действие не по ситуации.
    final showCreate = !query.deletedOnly && !query.hasFilters;

    return ListView(
      // ListView, а не Center: иначе на экране не работает pull-to-refresh.
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 48),
        Icon(
          query.deletedOnly
              ? Icons.delete_outline
              : (query.hasFilters ? Icons.search_off : Icons.sticky_note_2_outlined),
          size: 56,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        if (showCreate) ...<Widget>[
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Создать запись'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 48),
        Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'Не удалось загрузить записи',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
        ),
      ],
    );
  }
}
