import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/providers.dart';
import 'attachment.dart';

/// Вызовы эндпоинтов вложений.
///
/// Размер файла здесь не проверяется: предел задан настройками сервера и может
/// быть изменён без выпуска приложения. Придумывать свой предел — значит
/// запрещать загрузку, которую сервер бы принял.
class AttachmentsApi {
  AttachmentsApi({required this.apiClient});

  final Dio apiClient;

  Future<List<Attachment>> list(String noteId) => guardApi(() async {
        final response = await apiClient.get<List<dynamic>>(
          '/notes/$noteId/attachments',
        );
        return (response.data ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(Attachment.fromJson)
            .toList(growable: false);
      });

  /// Загружает файл. [onProgress] получает отправленные и всего байт —
  /// на медленной связи без этого непонятно, идёт загрузка или повисла.
  Future<Attachment> upload(
    String noteId, {
    required String fileName,
    required List<int> bytes,
    String? contentType,
    void Function(int sent, int total)? onProgress,
  }) =>
      guardApi(() async {
        final form = FormData.fromMap(<String, dynamic>{
          'file': MultipartFile.fromBytes(
            bytes,
            filename: fileName,
            contentType:
                contentType == null ? null : DioMediaType.parse(contentType),
          ),
        });

        final response = await apiClient.post<Map<String, dynamic>>(
          '/notes/$noteId/attachments',
          data: form,
          onSendProgress: onProgress,
        );
        return Attachment.fromJson(response.data!);
      });

  /// Скачивает файл целиком в память.
  ///
  /// Именно через этот клиент, а не по прямой ссылке: у файла нет публичного
  /// адреса, скачивание требует заголовка Authorization. Поэтому картинку
  /// нельзя отдать в `Image.network` — только в `Image.memory`.
  Future<List<int>> download(
    String id, {
    void Function(int received, int total)? onProgress,
  }) =>
      guardApi(() async {
        final response = await apiClient.get<List<int>>(
          '/attachments/$id/content',
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: onProgress,
        );
        return response.data ?? const <int>[];
      });

  Future<void> delete(String id) => guardApi(() async {
        await apiClient.delete<void>('/attachments/$id');
      });

  Future<AttachmentUsage> usage() => guardApi(() async {
        final response = await apiClient.get<Map<String, dynamic>>(
          '/attachments/usage',
        );
        return AttachmentUsage.fromJson(response.data!);
      });
}

final attachmentsApiProvider = Provider<AttachmentsApi>(
  (Ref ref) => AttachmentsApi(apiClient: ref.watch(apiClientProvider)),
);
