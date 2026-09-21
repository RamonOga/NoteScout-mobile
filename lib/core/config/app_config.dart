/// Настройки подключения к бэкенду.
///
/// Базовый URL задаётся при сборке:
///
///     flutter run --dart-define=API_BASE_URL=https://notes.example.com/api/v1
///
/// Значение по умолчанию — `10.0.2.2`: это адрес хост-машины с точки зрения
/// Android-эмулятора, поэтому в отладке клиент сразу видит локальный бэкенд.
/// Для iOS-симулятора нужен `localhost`, для устройства — адрес в сети.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);
}
