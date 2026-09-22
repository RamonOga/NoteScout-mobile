import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'notes_cache.dart';

/// Файловое хранилище снимка: по файлу на пользователя.
///
/// Отдельный файл на пользователя, а не один общий, — это и есть защита от
/// показа чужих заметок из кеша: после смены аккаунта читается другой файл,
/// и старые данные физически не могут попасть в новый список.
class FileNotesCacheStore implements NotesCacheStore {
  FileNotesCacheStore({required this.directory, required this.userId});

  final Directory directory;
  final String userId;

  /// Разделитель задан явно: path_provider отдаёт каталог с прямыми слэшами
  /// на всех поддерживаемых платформах, и тянуть пакет `path` ради join
  /// здесь не за чем.
  File get file => File('${directory.path}/notes-cache-$userId.json');

  @override
  Future<String?> read() async {
    final File target = file;
    if (!await target.exists()) return null;
    return target.readAsString();
  }

  @override
  Future<void> write(String content) async {
    final File target = file;
    await target.parent.create(recursive: true);
    // Пишем во временный файл и переименовываем: обрыв записи не оставит на
    // месте снимка обрубок, из которого потом ничего не прочитать.
    final File tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }

  @override
  Future<void> clear() async {
    final File target = file;
    if (await target.exists()) await target.delete();
  }
}

/// Создаёт файловое хранилище в каталоге приложения.
///
/// Возвращает null, если каталог недоступен. Кеш — вспомогательная вещь:
/// без него приложение обязано работать, поэтому недоступность каталога
/// означает «оффлайна не будет», а не отказ списка заметок. На практике это
/// происходит в тестах, где платформенного канала нет вовсе, и на платформах,
/// где path_provider не поддерживается.
Future<NotesCacheStore?> createNotesCacheStore(String userId) async {
  try {
    final Directory directory = await getApplicationDocumentsDirectory();
    return FileNotesCacheStore(directory: directory, userId: userId);
  } catch (_) {
    return null;
  }
}
