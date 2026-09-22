import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/api_exception.dart';
import '../../data/attachment.dart';
import '../../data/attachments_api.dart';

/// Вложения заметки: список, загрузка, удаление и просмотр картинок.
///
/// Показывается только у сохранённой заметки: приложить файл к тому, чего ещё
/// нет, некуда — серверу нужен идентификатор заметки.
class AttachmentsSection extends ConsumerStatefulWidget {
  const AttachmentsSection({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends ConsumerState<AttachmentsSection> {
  List<Attachment> _items = const <Attachment>[];
  bool _loading = true;
  bool _busy = false;

  /// Доля отправленного при загрузке. null — загрузки нет.
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<Attachment> items =
          await ref.read(attachmentsApiProvider).list(widget.noteId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.displayMessage;
      });
    }
  }

  Future<void> _attach() async {
    final PlatformFile? file = await FilePicker.pickFile();
    if (file == null || !mounted) return;

    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });

    // Файл читается целиком в память: предел на сервере — мегабайты, и это
    // заметно проще потоковой передачи с ручной сборкой multipart.
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      // Причин много — нет доступа, файл удалили, диск отвалился. Разбирать
      // их по одной смысла нет: пользователю важно знать, что файл не прочитан.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = 'Не удалось прочитать файл';
      });
      return;
    }
    if (!mounted) return;

    try {
      final Attachment created = await ref.read(attachmentsApiProvider).upload(
            widget.noteId,
            fileName: file.name,
            bytes: bytes,
            contentType: contentTypeForFileName(file.name),
            onProgress: (int sent, int total) {
              if (!mounted || total <= 0) return;
              setState(() => _progress = sent / total);
            },
          );
      if (!mounted) return;
      setState(() {
        _items = <Attachment>[..._items, created];
        _busy = false;
        _progress = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = error.displayMessage;
      });
    }
  }

  Future<void> _delete(Attachment attachment) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(attachmentsApiProvider).delete(attachment.id);
      if (!mounted) return;
      setState(() {
        _items = _items
            .where((Attachment item) => item.id != attachment.id)
            .toList(growable: false);
        _busy = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.displayMessage;
      });
    }
  }

  /// Картинку показываем прямо здесь; остальное скачать можно, а открыть нечем.
  ///
  /// Публичной ссылки у файла нет — скачивание идёт через тот же клиент
  /// с заголовком авторизации, поэтому в `Image.network` адрес не подставить.
  Future<void> _preview(Attachment attachment) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    if (!attachment.isImage) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Просмотр таких файлов пока не поддерживается'),
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final List<int> bytes =
          await ref.read(attachmentsApiProvider).download(attachment.id);
      if (!mounted) return;
      setState(() => _busy = false);

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Image.memory(Uint8List.fromList(bytes)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(attachment.fileName, textAlign: TextAlign.center),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.displayMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Вложения', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: _busy ? null : _attach,
              icon: const Icon(Icons.attach_file, size: 18),
              label: const Text('Приложить'),
            ),
          ],
        ),
        if (_progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: LinearProgressIndicator(value: _progress),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Файлов нет', style: theme.textTheme.bodySmall),
          )
        else
          ..._items.map(
            (Attachment attachment) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                attachment.isImage
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
              ),
              title: Text(
                attachment.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(formatFileSize(attachment.sizeBytes)),
              onTap: _busy ? null : () => _preview(attachment),
              trailing: IconButton(
                onPressed: _busy ? null : () => _delete(attachment),
                icon: const Icon(Icons.close),
                tooltip: 'Удалить вложение',
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
