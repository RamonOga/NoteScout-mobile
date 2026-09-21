import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

/// Хранилище сессии.
///
/// Абстракция нужна ради тестов: боевая реализация обращается к Keychain
/// и Keystore, а в тестах подставляется память.
abstract interface class TokenStorage {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

/// Реализация поверх flutter_secure_storage.
///
/// На iOS это Keychain, на Android — Keystore. Обычные SharedPreferences
/// для токенов не годятся: они читаются любым приложением с root и попадают
/// в резервные копии.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _sessionKey = 'notescout.session';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // Данные повреждены или сохранены несовместимой версией приложения.
      // Молча чистим: пользователь просто войдёт заново.
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}

/// Хранилище в памяти — для тестов и предпросмотра.
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([this._session]);

  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
