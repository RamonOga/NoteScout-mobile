import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/session/session_store.dart';
import '../data/auth_api.dart';

/// Сценарии аутентификации: то, что вызывают экраны.
///
/// Сервис не хранит состояние — источник правды один, [SessionStore].
class AuthService {
  AuthService({required this.api, required this.store});

  final AuthApi api;
  final SessionStore store;

  Future<void> signIn({required String email, required String password}) async {
    final session = await api.login(email: email, password: password);
    await store.save(session);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final session = await api.register(
      email: email,
      password: password,
      displayName: displayName,
    );
    await store.save(session);
  }

  /// Выход. Локальную сессию чистим в любом случае: если сервер недоступен,
  /// пользователь всё равно должен выйти из приложения, а refresh-токен
  /// истечёт сам.
  Future<void> signOut() async {
    final refreshToken = store.session?.refreshToken;
    if (refreshToken != null) {
      try {
        await api.logout(refreshToken);
      } on ApiException {
        // Молча: выход важнее успешного ответа сервера.
      }
    }
    await store.clear();
  }

  /// Подтягивает актуальные данные пользователя.
  ///
  /// Если запрос не удался из-за сети — сессию не трогаем: в приложении
  /// остаются данные из хранилища. Если сервер ответил 401, интерсептор уже
  /// попытался обновить токен и очистил сессию при неудаче.
  Future<void> refreshProfile() async {
    if (!store.isSignedIn) return;

    try {
      final user = await api.me();
      final current = store.session;
      if (current != null) {
        await store.save(current.copyWith(user: user));
      }
    } on ApiException {
      // Ничего не делаем: данные из хранилища остаются валидными для показа.
    }
  }
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(apiClient: ref.watch(apiClientProvider)),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    api: ref.watch(authApiProvider),
    store: ref.watch(sessionStoreProvider),
  ),
);
