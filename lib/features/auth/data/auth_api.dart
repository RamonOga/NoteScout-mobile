import 'package:dio/dio.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/models/user.dart';
import '../../../core/session/auth_session.dart';

/// Вызовы эндпоинтов аутентификации.
///
/// Здесь же DioException превращается в ApiException: выше, в сервисах
/// и виджетах, с Dio никто не работает.
///
/// Ротация токена сюда не входит намеренно — ею занимается AuthInterceptor,
/// потому что обновление нужно любому запросу, а не только входу.
class AuthApi {
  AuthApi({required this.apiClient});

  final Dio apiClient;

  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
  }) =>
      _guard(() async {
        final response = await apiClient.post<Map<String, dynamic>>(
          '/auth/register',
          data: <String, dynamic>{
            'email': email,
            'password': password,
            'displayName': displayName,
          },
        );
        return AuthSession.fromJson(response.data!);
      });

  Future<AuthSession> login({
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final response = await apiClient.post<Map<String, dynamic>>(
          '/auth/login',
          data: <String, dynamic>{'email': email, 'password': password},
        );
        return AuthSession.fromJson(response.data!);
      });

  /// Отзыв refresh-токена. Идемпотентен на стороне сервера.
  Future<void> logout(String refreshToken) => _guard(() async {
        await apiClient.post<void>(
          '/auth/logout',
          data: <String, dynamic>{'refreshToken': refreshToken},
        );
      });

  Future<User> me() => _guard(() async {
        final response = await apiClient.get<Map<String, dynamic>>('/users/me');
        return User.fromJson(response.data!);
      });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
