import 'package:flutter/foundation.dart';

/// Настройки подключения к бэкенду.
///
/// Базовый URL задаётся при сборке:
///
///     flutter run --dart-define=API_BASE_URL=https://notes.example.com/api/v1
///
/// Если не задан, адрес выводится из окружения:
///
/// * в браузере — из адреса самой страницы, поэтому веб-сборка работает и на
///   `localhost`, и на `127.0.0.1`, и за прокси: запросы уходят на тот же
///   источник, и CORS не участвует;
/// * на телефоне — `10.0.2.2`, то есть хост-машина с точки зрения
///   Android-эмулятора: в отладке клиент сразу видит локальный бэкенд.
class AppConfig {
  const AppConfig._();

  static const String _configuredBaseUrl =
      String.fromEnvironment('API_BASE_URL');

  static const String _emulatorBaseUrl = 'http://10.0.2.2:8080/api/v1';

  static String get apiBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }
    if (kIsWeb) {
      return Uri.base.resolve('/api/v1').toString();
    }
    return _emulatorBaseUrl;
  }

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);
}

