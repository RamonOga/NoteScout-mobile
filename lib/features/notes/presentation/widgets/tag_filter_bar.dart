import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/notes_controller.dart';
import '../../data/models.dart';
import '../../data/notes_repository.dart';

/// Панель фильтров: теги, архив и режим совпадения по тегам.
class TagFilterBar extends ConsumerWidget {
  const TagFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(notesQueryProvider);
    final controller = ref.read(notesQueryProvider.notifier);
    final tags = ref.watch(tagsProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        tags.when(
          loading: () => const SizedBox(height: 40),
          // Ошибка загрузки тегов не должна ломать экран: список заметок
          // продолжает работать, просто без панели тегов.
          error: (_, _) => const SizedBox.shrink(),
          data: (List<Tag> items) {
            if (items.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final tag = items[index];
                  final selected = query.tags.contains(tag.name);
                  return FilterChip(
                    label: Text('${tag.name} · ${tag.noteCount}'),
                    selected: selected,
                    onSelected: (_) => controller.toggleTag(tag.name),
                  );
                },
              ),
            );
          },
        ),
        if (query.tags.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: <Widget>[
                Text('Совпадение:', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                SegmentedButton<TagsMode>(
                  segments: TagsMode.values
                      .map(
                        (TagsMode mode) => ButtonSegment<TagsMode>(
                          value: mode,
                          label: Text(mode.label),
                        ),
                      )
                      .toList(growable: false),
                  selected: <TagsMode>{query.mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<TagsMode> selection) =>
                      controller.setMode(selection.first),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilterChip(
                label: const Text('Архив'),
                selected: query.includeArchived,
                onSelected: controller.setIncludeArchived,
              ),
              FilterChip(
                label: const Text('Только ссылки'),
                selected: query.type == NoteType.link,
                onSelected: (bool selected) =>
                    controller.setType(selected ? NoteType.link : null),
              ),
              if (query.hasFilters)
                TextButton.icon(
                  onPressed: controller.clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Сбросить'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
