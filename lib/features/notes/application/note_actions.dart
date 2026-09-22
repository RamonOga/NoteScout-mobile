import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/notes_api.dart';
import '../data/notes_repository.dart';
import 'notes_controller.dart';

/// Изменяющие операции над заметками.
///
/// Отдельный слой нужен ради одного: после любого изменения список и счётчики
/// тегов должны перезагрузиться. Собранное в одном месте, это не забудется
/// при добавлении следующей операции.
///
/// Здесь же обновляется оффлайн-кеш. Именно здесь, а не по ответам сервера:
/// удалённая заметка просто исчезает из списка, и по ответу нельзя понять,
/// пропала она потому, что её удалили, или потому, что не попала в фильтр.
/// Если не убрать её из снимка, она вернётся в список при первом обрыве связи.
class NoteActions {
  NoteActions(this._ref);

  final Ref _ref;

  Future<Note> create(NoteDraft draft) async {
    final note = await _ref.read(notesApiProvider).create(draft);
    await _remember(note);
    _reload();
    return note;
  }

  Future<Note> update(String id, NoteDraft draft, {bool? archived}) async {
    final note = await _ref.read(notesApiProvider).update(id, draft, archived: archived);
    await _remember(note);
    _reload();
    return note;
  }

  Future<void> delete(String id) async {
    await _ref.read(notesApiProvider).delete(id);
    await _ref.read(notesRepositoryProvider).forgetNote(id);
    _reload();
  }

  /// Архивация отдельным запросом: форму при этом сохранять не нужно.
  Future<Note> setArchived(String id, bool archived) async {
    final note = await _ref.read(notesApiProvider).setArchived(id, archived);
    await _remember(note);
    _reload();
    return note;
  }

  Future<Note> restore(String id) async {
    final note = await _ref.read(notesApiProvider).restore(id);
    await _remember(note);
    _reload();
    return note;
  }

  Future<void> _remember(Note note) =>
      _ref.read(notesRepositoryProvider).rememberNote(note);

  void _reload() {
    _ref.invalidate(notesControllerProvider);
    // Счётчики заметок у тегов меняются вместе со списком.
    _ref.invalidate(tagsProvider);
  }
}

final noteActionsProvider = Provider<NoteActions>(NoteActions.new);
