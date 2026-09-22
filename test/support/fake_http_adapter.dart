import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Подменяет транспорт Dio: запросы никуда не уходят, ответы задаёт тест.
///
/// Так проверяется настоящая логика интерсепторов — подстановка заголовка,
/// обновление токена при 401, повтор запроса — без сети и без моков самого Dio.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;

  /// Пути в порядке обращения — по ним видно, был ли повтор.
  final List<String> requestedPaths = <String>[];

  /// Значение заголовка Authorization на каждом запросе.
  final List<Object?> authorizationHeaders = <Object?>[];

  /// Параметры строки запроса — по ним проверяется сборка фильтров.
  final List<Map<String, dynamic>> requestedQueries = <Map<String, dynamic>>[];

  /// Тела запросов (для POST и PATCH).
  final List<Object?> requestBodies = <Object?>[];

  /// Полные параметры запросов. Нужны там, где важно не только «куда» и «что»,
  /// но и как запрос настроен: например, что файл скачивается байтами,
  /// а не разбирается как JSON.
  final List<RequestOptions> requestOptions = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requestedPaths.add(options.path);
    authorizationHeaders.add(options.headers['Authorization']);
    requestedQueries.add(options.queryParameters);
    requestBodies.add(options.data);
    requestOptions.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Ответ с JSON-телом.
ResponseBody jsonResponse(Object body, {int statusCode = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

/// Ответ об ошибке в том формате, который отдаёт бэкенд.
ResponseBody apiErrorResponse(
  String code,
  String message, {
  required int statusCode,
}) =>
    jsonResponse(
      <String, dynamic>{'code': code, 'message': message},
      statusCode: statusCode,
    );

/// Тело успешной аутентификации, как его возвращает /auth/login и /auth/register.
Map<String, dynamic> tokenResponseJson({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
  String email = 'ivan@example.com',
  String displayName = 'Иван',
}) =>
    <String, dynamic>{
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'tokenType': 'Bearer',
      'expiresIn': 900,
      'user': userJson(email: email, displayName: displayName),
    };

Map<String, dynamic> userJson({
  String id = '0f8fad5b-d9cb-469f-a165-70867728950e',
  String email = 'ivan@example.com',
  String displayName = 'Иван',
}) =>
    <String, dynamic>{
      'id': id,
      'email': email,
      'displayName': displayName,
      'createdAt': '2025-06-01T12:00:00Z',
    };

Dio dioWith(FakeHttpAdapter adapter, {String baseUrl = 'http://localhost/api/v1'}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.httpClientAdapter = adapter;
  return dio;
}
