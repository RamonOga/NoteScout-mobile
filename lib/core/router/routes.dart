/// Пути маршрутов приложения.
///
/// Вынесены отдельно, чтобы экраны и таблица маршрутов не импортировали
/// друг друга ради одной строки.
class AppRoutes {
  const AppRoutes._();

  static const String login = '/login';
  static const String register = '/register';

  static const String notes = '/notes';

  /// Создание записи. Объявлен раньше `:id`, иначе «new» попадёт в параметр.
  static const String noteNew = '/notes/new';

  /// Редактирование: `/notes/<id>`.
  static const String noteEditPattern = '/notes/:id';

  static String noteEdit(String id) => '/notes/$id';
}
