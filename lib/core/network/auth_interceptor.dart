import 'package:dio/dio.dart';

import '../session/auth_session.dart';
import '../session/session_store.dart';

/// Подставляет access-токен и обновляет его при 401.
///
/// Логика обновления собрана в одном месте, а не расползается по репозиториям
/// экранов: любой запрос, получивший 401, прозрачно повторяется с новым токеном.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.refreshClient,
    required this.retryClient,
    required this.store,
  });

  /// Пометка «этот запрос уже повторяли» — защита от бесконечного цикла.
  static const String _retriedFlag = 'notescout.retried';

  static const String _refreshPath = '/auth/refresh';

  /// Клиент без интерсепторов: им выполняется сама ротация токена.
  final Dio refreshClient;

  /// Клиент, через который повторяется исходный запрос.
  final Dio retryClient;

  final SessionStore store;

  Future<bool>? _refreshInFlight;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = store.session?.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;

    // Обновление токена само может получить 401 — повторять его бессмысленно.
    // Запросы к /auth/* не повторяем ещё и потому, что их 401 означает
    // неверные учётные данные, а не истёкший access-токен.
    final isAuthEndpoint = options.path.startsWith('/auth/');
    final alreadyRetried = options.extra[_retriedFlag] == true;

    if (err.response?.statusCode != 401 || isAuthEndpoint || alreadyRetried) {
      handler.next(err);
      return;
    }

    final refreshed = await _refreshOnce();
    if (!refreshed) {
      handler.next(err);
      return;
    }

    try {
      final session = store.session;
      if (session != null) {
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
      options.extra[_retriedFlag] = true;
      final response = await retryClient.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Обновляет токен ровно один раз, даже если 401 пришёл сразу от нескольких
  /// параллельных запросов: остальные ждут тот же Future, а не шлют свои.
  /// Без этого пачка одновременных запросов устроила бы гонку ротаций,
  /// и часть токенов была бы отозвана как «украденные».
  Future<bool> _refreshOnce() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _performRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _performRefresh() async {
    final current = store.session;
    if (current == null) return false;

    try {
      final response = await refreshClient.post<Map<String, dynamic>>(
        _refreshPath,
        data: <String, dynamic>{'refreshToken': current.refreshToken},
      );

      final data = response.data;
      if (data == null) return false;

      await store.save(AuthSession.fromJson(data));
      return true;
    } on DioException {
      // Токен отозван, просрочен или уже был использован — сессия кончилась.
      await store.clear();
      return false;
    }
  }
}
