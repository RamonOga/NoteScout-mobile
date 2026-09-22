/// Файл, приложенный к заметке.
///
/// Самого файла здесь нет: только описание. Байты запрашиваются отдельно,
/// потому что список вложений не должен тянуть за собой мегабайты.
class Attachment {
  const Attachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final DateTime createdAt;

  /// Картинку можно показать прямо в приложении, остальное — нет.
  bool get isImage => contentType.startsWith('image/');

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        contentType:
            json['contentType'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  bool operator ==(Object other) => other is Attachment && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Attachment($id, $fileName)';
}

/// Сколько места занято вложениями и каков предел.
class AttachmentUsage {
  const AttachmentUsage({required this.usedBytes, required this.limitBytes});

  final int usedBytes;
  final int limitBytes;

  factory AttachmentUsage.fromJson(Map<String, dynamic> json) => AttachmentUsage(
        usedBytes: (json['usedBytes'] as num?)?.toInt() ?? 0,
        limitBytes: (json['limitBytes'] as num?)?.toInt() ?? 0,
      );
}

/// Размер файла по-человечески.
///
/// Без пакета intl: нужен один формат, и только для размера.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}

/// Content-Type по имени файла.
///
/// Выборщик файлов тип не отдаёт, а без него сервер сохранит
/// `application/octet-stream` — и загруженную картинку нельзя будет показать
/// в приложении: она перестанет опознаваться как изображение. Поэтому тип
/// выводится из расширения, а неизвестные расширения остаются как есть —
/// сервер подставит значение по умолчанию.
String? contentTypeForFileName(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;

  return switch (fileName.substring(dot + 1).toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'bmp' => 'image/bmp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'md' => 'text/markdown',
    'json' => 'application/json',
    'zip' => 'application/zip',
    _ => null,
  };
}
