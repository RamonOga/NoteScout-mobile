import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../auth/application/auth_service.dart';
import '../application/notes_controller.dart';
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
      floatingActionButton: FloatingActionButton.extended(
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
              data: (NotesState state) => _buildList(state, query.hasFilters),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(NotesState state, bool filtersActive) {
    if (state.isEmpty) {
      return _EmptyState(
        filtersActive: filtersActive,
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
  const _EmptyState({required this.filtersActive, required this.onCreate});

  final bool filtersActive;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = filtersActive
        ? 'Ничего не найдено.\nПопробуйте изменить запрос или снять фильтры.'
        : 'Записей пока нет.\nСоздайте первую — заметку или ссылку.';

    return ListView(
      // ListView, а не Center: иначе на экране не работает pull-to-refresh.
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 48),
        Icon(
          filtersActive ? Icons.search_off : Icons.sticky_note_2_outlined,
          size: 56,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        if (!filtersActive) ...<Widget>[
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
