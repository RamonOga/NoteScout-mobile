import 'package:flutter/foundation.dart';

import 'auth_session.dart';
import 'token_storage.dart';

/// Единственный источник правды о текущей сессии.
///
/// Наследуется от [ChangeNotifier] намеренно: этот же объект передаётся
/// в go_router как `refreshListenable`, поэтому смена сессии автоматически
/// пересчитывает правила доступа к маршрутам. Отдельного «состояния входа»
/// нигде не заводится — иначе оно рано или поздно разъедется с хранилищем.
class SessionStore extends ChangeNotifier {
  SessionStore(this._storage);

  final TokenStorage _storage;
  AuthSession? _session;

  AuthSession? get session => _session;

  bool get isSignedIn => _session != null;

  /// Читает сохранённую сессию. Вызывается один раз при запуске приложения,
  /// до первого кадра, чтобы роутер сразу знал, куда вести пользователя.
  Future<AuthSession?> load() async {
    _session = await _storage.read();
    notifyListeners();
    return _session;
  }

  Future<void> save(AuthSession session) async {
    _session = session;
    await _storage.write(session);
    notifyListeners();
  }

  Future<void> clear() async {
    _session = null;
    await _storage.clear();
    notifyListeners();
  }
}
