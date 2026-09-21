import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/core/error/api_exception.dart';

void main() {
  group('ApiException.fromDio', () {
    test('разбирает единый формат ошибки бэкенда', () {
      final request = RequestOptions(path: '/notes');
      final error = DioException(
        requestOptions: request,
        response: Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 400,
          data: <String, dynamic>{
            'code': 'VALIDATION_ERROR',
            'message': 'Запрос не прошёл валидацию',
            'details': <Map<String, dynamic>>[
              <String, dynamic>{
                'field': 'email',
                'message': 'Некорректный email',
              },
              <String, dynamic>{
                'field': 'password',
                'message': 'Пароль должен быть от 8 до 128 символов',
              },
            ],
          },
        ),
      );

      final exception = ApiException.fromDio(error);

      expect(exception.code, 'VALIDATION_ERROR');
      expect(exception.statusCode, 400);
      expect(exception.isValidationFailure, isTrue);
      expect(exception.details, hasLength(2));
      expect(exception.details.first.field, 'email');
      // Пользователю показываем нарушения по полям, а не общее сообщение.
      expect(exception.displayMessage, contains('Некорректный email'));
      expect(exception.displayMessage, contains('от 8 до 128'));
    });

    test('без тела ответа сообщает о проблеме с сетью', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/notes'),
        type: DioExceptionType.connectionError,
      );

      final exception = ApiException.fromDio(error);

      expect(exception.isNetworkFailure, isTrue);
      expect(exception.statusCode, isNull);
      expect(exception.displayMessage, contains('Нет связи'));
    });

    test('для незнакомого тела подставляет сообщение по коду ответа', () {
      final request = RequestOptions(path: '/notes');
      final error = DioException(
        requestOptions: request,
        response: Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 401,
          data: <String, dynamic>{'unexpected': 'shape'},
        ),
      );

      final exception = ApiException.fromDio(error);

      expect(exception.code, 'UNKNOWN');
      expect(exception.isUnauthorized, isTrue);
      expect(exception.displayMessage, 'Требуется вход');
    });
  });
}
