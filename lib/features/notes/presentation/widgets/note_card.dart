import 'package:flutter/material.dart';

import '../../../../core/util/date_format.dart';
import '../../data/models.dart';

/// Карточка заметки в списке.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, this.onTap});

  final Note note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = note.preview;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    note.type == NoteType.link
                        ? Icons.link
                        : Icons.sticky_note_2_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (note.isArchived)
                    Icon(
                      Icons.archive_outlined,
                      size: 18,
                      color: theme.colorScheme.outline,
                    ),
                ],
              ),
              if (preview.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  preview,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (note.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: note.tags
                      .map(
                        (String tag) => Chip(
                          label: Text(tag),
                          labelStyle: theme.textTheme.labelSmall,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                formatNoteDate(note.updatedAt),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
