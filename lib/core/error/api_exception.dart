import 'package:dio/dio.dart';

/// Одно нарушение валидации, пришедшее от бэкенда.
class FieldViolation {
  const FieldViolation({required this.field, required this.message});

  final String field;
  final String message;

  factory FieldViolation.fromJson(Map<String, dynamic> json) => FieldViolation(
        field: json['field'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );

  @override
  String toString() => '$field: $message';
}

/// Ошибка обращения к API в том виде, в каком её удобно показывать и разбирать.
///
/// Бэкенд отдаёт единый формат:
/// `{"code": "...", "message": "...", "details": [{"field": "...", "message": "..."}]}`.
/// Код (`code`) предназначен для логики, сообщение — для пользователя.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.details = const <FieldViolation>[],
    this.statusCode,
  });

  final String code;
  final String message;
  final List<FieldViolation> details;
  final int? statusCode;

  /// Ошибка сети или таймаут: запрос до сервера не дошёл.
  static const String networkCode = 'NETWORK_ERROR';
  static const String unknownCode = 'UNKNOWN';

  bool get isNetworkFailure => code == networkCode;
  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409;
  bool get isValidationFailure => code == 'VALIDATION_ERROR';

  /// Текст для показа пользователю: если есть нарушения по полям, показываем их.
  String get displayMessage {
    if (details.isEmpty) return message;
    return details.map((violation) => violation.message).join('\n');
  }

  factory ApiException.network() => const ApiException(
        code: networkCode,
        message: 'Нет связи с сервером. Проверьте подключение к сети.',
      );

  factory ApiException.fromDio(DioException error) {
    final response = error.response;

    // Ответа нет — значит запрос не дошёл: таймаут, обрыв, неверный адрес.
    if (response == null) {
      return ApiException.network();
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      final rawDetails = data['details'];
      final details = rawDetails is List
          ? rawDetails
              .whereType<Map<String, dynamic>>()
              .map(FieldViolation.fromJson)
              .toList(growable: false)
          : const <FieldViolation>[];

      return ApiException(
        code: data['code'] as String? ?? unknownCode,
        message: data['message'] as String? ?? _fallbackMessage(response.statusCode),
        details: details,
        statusCode: response.statusCode,
      );
    }

    return ApiException(
      code: unknownCode,
      message: _fallbackMessage(response.statusCode),
      statusCode: response.statusCode,
    );
  }

  static String _fallbackMessage(int? statusCode) => switch (statusCode) {
        400 => 'Некорректный запрос',
        401 => 'Требуется вход',
        403 => 'Доступ запрещён',
        404 => 'Не найдено',
        409 => 'Конфликт данных',
        429 => 'Слишком много запросов, попробуйте позже',
        _ => 'Не удалось выполнить запрос',
      };

  @override
  String toString() => 'ApiException($code, status=$statusCode): $message';
}

/// Превращает DioException в ApiException.
///
/// Выше этого слоя — в сервисах и виджетах — с Dio никто не работает: они
/// видят только ApiException с кодом и готовым сообщением для пользователя.
Future<T> guardApi<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DioException catch (error) {
    throw ApiException.fromDio(error);
  }
}
