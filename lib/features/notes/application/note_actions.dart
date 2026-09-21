import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/notes_api.dart';
import 'notes_controller.dart';

/// Изменяющие операции над заметками.
///
/// Отдельный слой нужен ради одного: после любого изменения список и счётчики
/// тегов должны перезагрузиться. Собранное в одном месте, это не забудется
/// при добавлении следующей операции.
class NoteActions {
  NoteActions(this._ref);

  final Ref _ref;

  Future<Note> create(NoteDraft draft) async {
    final note = await _ref.read(notesApiProvider).create(draft);
    _reload();
    return note;
  }

  Future<Note> update(String id, NoteDraft draft, {bool? archived}) async {
    final note = await _ref.read(notesApiProvider).update(id, draft, archived: archived);
    _reload();
    return note;
  }

  Future<void> delete(String id) async {
    await _ref.read(notesApiProvider).delete(id);
    _reload();
  }

  /// Архивация отдельным запросом: форму при этом сохранять не нужно.
  Future<Note> setArchived(String id, bool archived) async {
    final note = await _ref.read(notesApiProvider).setArchived(id, archived);
    _reload();
    return note;
  }

  Future<Note> restore(String id) async {
    final note = await _ref.read(notesApiProvider).restore(id);
    _reload();
    return note;
  }

  void _reload() {
    _ref.invalidate(notesControllerProvider);
    // Счётчики заметок у тегов меняются вместе со списком.
    _ref.invalidate(tagsProvider);
  }
}

final noteActionsProvider = Provider<NoteActions>(NoteActions.new);
