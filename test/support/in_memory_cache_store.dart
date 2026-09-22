import 'package:notescout_mobile/features/notes/data/notes_cache.dart';

/// Хранилище снимка в памяти.
///
/// Тесты оффлайна не должны трогать файловую систему: тогда они не зависят
/// ни от платформы, ни от прав на каталог, ни от состояния между запусками.
class InMemoryCacheStore implements NotesCacheStore {
  InMemoryCacheStore({this.content});

  String? content;
  int writes = 0;
  int clears = 0;

  @override
  Future<String?> read() async => content;

  @override
  Future<void> write(String value) async {
    content = value;
    writes++;
  }

  @override
  Future<void> clear() async {
    content = null;
    clears++;
  }
}
