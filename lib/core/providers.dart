import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'network/auth_interceptor.dart';
import 'session/session_store.dart';
import 'session/token_storage.dart';

Dio _createClient() => Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        sendTimeout: AppConfig.sendTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );

/// Клиент без интерсепторов: вход, регистрация и обновление токена.
///
/// Обновление идёт мимо основного клиента намеренно — иначе 401 от самого
/// /auth/refresh запускал бы новый цикл обновления.
final refreshClientProvider = Provider<Dio>((ref) => _createClient());

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);

/// Переопределяется в `main()` готовым экземпляром с уже прочитанной сессией.
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(ref.watch(tokenStorageProvider)),
);

/// Основной клиент приложения.
final apiClientProvider = Provider<Dio>((ref) {
  final client = _createClient();
  client.interceptors.add(
    AuthInterceptor(
      refreshClient: ref.watch(refreshClientProvider),
      retryClient: client,
      store: ref.watch(sessionStoreProvider),
    ),
  );
  return client;
});
