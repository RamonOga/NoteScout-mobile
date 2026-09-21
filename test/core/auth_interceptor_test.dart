import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/core/network/auth_interceptor.dart';
import 'package:notescout_mobile/core/session/auth_session.dart';
import 'package:notescout_mobile/core/session/session_store.dart';
import 'package:notescout_mobile/core/session/token_storage.dart';

import '../support/fake_http_adapter.dart';

AuthSession _session({String access = 'old-access', String refresh = 'refresh-1'}) =>
    AuthSession.fromJson(
      tokenResponseJson(accessToken: access, refreshToken: refresh),
    );

/// Собирает основной клиент с интерсептором и отдельный клиент обновления.
({Dio apiClient, SessionStore store}) _buildWith({
  required FakeHttpAdapter apiAdapter,
  required FakeHttpAdapter refreshAdapter,
  AuthSession? initialSession,
}) {
  final store = SessionStore(InMemoryTokenStorage(initialSession));
  final refreshClient = dioWith(refreshAdapter);
  final apiClient = dioWith(apiAdapter);

  apiClient.interceptors.add(
    AuthInterceptor(
      refreshClient: refreshClient,
      retryClient: apiClient,
      store: store,
    ),
  );

  return (apiClient: apiClient, store: store);
}

void main() {
  group('AuthInterceptor', () {
    test('подставляет access-токен в заголовок', () async {
      final apiAdapter = FakeHttpAdapter((_) async => jsonResponse(userJson()));
      final built = _buildWith(
        apiAdapter: apiAdapter,
        refreshAdapter: FakeHttpAdapter(
          (_) async => jsonResponse(<String, dynamic>{}),
        ),
        initialSession: _session(access: 'token-x'),
      );
      await built.store.load();

      await built.apiClient.get<Map<String, dynamic>>('/users/me');

      expect(apiAdapter.authorizationHeaders.single, 'Bearer token-x');
    });

    test('при 401 обновляет токен и повторяет запрос', () async {
      var refreshCalls = 0;
      final refreshAdapter = FakeHttpAdapter((options) async {
        refreshCalls++;
        expect(options.path, '/auth/refresh');
        return jsonResponse(
          tokenResponseJson(accessToken: 'new-access', refreshToken: 'refresh-2'),
        );
      });

      final apiAdapter = FakeHttpAdapter((options) async {
        if (options.headers['Authorization'] == 'Bearer new-access') {
          return jsonResponse(userJson());
        }
        return apiErrorResponse(
          'UNAUTHORIZED',
          'Требуется авторизация',
          statusCode: 401,
        );
      });

      final built = _buildWith(
        apiAdapter: apiAdapter,
        refreshAdapter: refreshAdapter,
        initialSession: _session(),
      );
      await built.store.load();

      final response =
          await built.apiClient.get<Map<String, dynamic>>('/users/me');

      expect(response.statusCode, 200);
      expect(refreshCalls, 1);
      expect(built.store.session!.accessToken, 'new-access');
      // Запрос ушёл дважды: с истёкшим токеном и с обновлённым.
      expect(apiAdapter.requestedPaths, <String>['/users/me', '/users/me']);
      expect(
        apiAdapter.authorizationHeaders,
        <Object?>['Bearer old-access', 'Bearer new-access'],
      );
    });

    test('если обновление не удалось, сессия очищается и повтора нет', () async {
      final refreshAdapter = FakeHttpAdapter(
        (_) async =>
            apiErrorResponse('UNAUTHORIZED', 'Токен отозван', statusCode: 401),
      );
      final apiAdapter = FakeHttpAdapter(
        (_) async => apiErrorResponse(
          'UNAUTHORIZED',
          'Требуется авторизация',
          statusCode: 401,
        ),
      );

      final built = _buildWith(
        apiAdapter: apiAdapter,
        refreshAdapter: refreshAdapter,
        initialSession: _session(),
      );
      await built.store.load();

      await expectLater(
        built.apiClient.get<Map<String, dynamic>>('/users/me'),
        throwsA(isA<DioException>()),
      );

      expect(built.store.session, isNull, reason: 'сессия должна быть очищена');
      expect(apiAdapter.requestedPaths, <String>['/users/me']);
    });

    test('параллельные запросы обновляют токен один раз', () async {
      var refreshCalls = 0;
      final refreshAdapter = FakeHttpAdapter((_) async {
        refreshCalls++;
        // Задержка нужна, чтобы второй 401 успел прийти до завершения ротации.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return jsonResponse(
          tokenResponseJson(accessToken: 'new-access', refreshToken: 'refresh-2'),
        );
      });

      final apiAdapter = FakeHttpAdapter((options) async {
        if (options.headers['Authorization'] == 'Bearer new-access') {
          return jsonResponse(userJson());
        }
        return apiErrorResponse(
          'UNAUTHORIZED',
          'Требуется авторизация',
          statusCode: 401,
        );
      });

      final built = _buildWith(
        apiAdapter: apiAdapter,
        refreshAdapter: refreshAdapter,
        initialSession: _session(),
      );
      await built.store.load();

      await Future.wait(<Future<Response<Map<String, dynamic>>>>[
        built.apiClient.get<Map<String, dynamic>>('/users/me'),
        built.apiClient.get<Map<String, dynamic>>('/users/me'),
      ]);

      expect(refreshCalls, 1, reason: 'должна быть одна ротация, а не две');
    });

    test('запросы к /auth/* не повторяются после 401', () async {
      var refreshCalls = 0;
      final refreshAdapter = FakeHttpAdapter((_) async {
        refreshCalls++;
        return apiErrorResponse('UNAUTHORIZED', 'Отозван', statusCode: 401);
      });
      final apiAdapter = FakeHttpAdapter(
        (_) async => apiErrorResponse(
          'UNAUTHORIZED',
          'Неверный email или пароль',
          statusCode: 401,
        ),
      );

      final built = _buildWith(
        apiAdapter: apiAdapter,
        refreshAdapter: refreshAdapter,
        initialSession: _session(),
      );
      await built.store.load();

      await expectLater(
        built.apiClient.post<Map<String, dynamic>>('/auth/login'),
        throwsA(isA<DioException>()),
      );

      expect(refreshCalls, 0, reason: '401 на входе — это не истёкший токен');
      expect(apiAdapter.requestedPaths, <String>['/auth/login']);
    });
  });
}
