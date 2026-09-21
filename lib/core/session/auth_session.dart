import '../models/user.dart';

/// Активная сессия: пара токенов и данные пользователя.
///
/// Хранится целиком в защищённом хранилище, чтобы при запуске не ждать ответа
/// сети ради имени пользователя.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  /// Короткоживущий токен (15 минут): уходит в заголовке Authorization.
  final String accessToken;

  /// Долгоживущий токен (30 дней): меняется на новую пару через /auth/refresh.
  final String refreshToken;

  final User user;

  AuthSession copyWith({String? accessToken, String? refreshToken, User? user}) =>
      AuthSession(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        user: user ?? this.user,
      );

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'user': user.toJson(),
      };
}
