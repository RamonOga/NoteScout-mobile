import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/router/routes.dart';
import '../application/note_actions.dart';
import '../data/models.dart';
import '../data/notes_api.dart';

/// Создание и редактирование записи.
///
/// Без `noteId` — создание. С ним — редактирование: запись подтягивается
/// с сервера, чтобы экран одинаково работал и при переходе из списка,
/// и при открытии по прямой ссылке.
class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, this.noteId});

  final String? noteId;

  bool get isEditing => noteId != null;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  /// Ограничения совпадают с серверными, чтобы не ловить 400 на пустом месте.
  static const int _maxTitleLength = 255;
  static const int _maxTagLength = 64;
  static const int _maxTags = 20;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _urlController = TextEditingController();
  final _tagController = TextEditingController();

  NoteType _type = NoteType.text;
  List<String> _tags = <String>[];
  Note? _note;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _urlController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final note = await ref.read(notesApiProvider).get(widget.noteId!);
      if (!mounted) return;

      _titleController.text = note.title;
      _contentController.text = note.content ?? '';
      _urlController.text = note.url ?? '';

      setState(() {
        _note = note;
        _type = note.type;
        _tags = List<String>.from(note.tags);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.displayMessage;
        _loading = false;
      });
    }
  }

  NoteDraft _draft() => NoteDraft(
        title: _titleController.text.trim(),
        type: _type,
        content: _contentController.text.trim(),
        // Для заметки ссылку не отправляем: поле не должно оставаться
        // от прежнего типа записи.
        url: _type == NoteType.link ? _urlController.text.trim() : null,
        tags: _tags,
      );

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final actions = ref.read(noteActionsProvider);
      if (widget.isEditing) {
        await actions.update(widget.noteId!, _draft());
      } else {
        await actions.create(_draft());
      }
      if (mounted) context.go(AppRoutes.notes);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.displayMessage;
          _saving = false;
        });
      }
    }
  }

  Future<void> _setArchived(bool archived) async {
    setState(() => _saving = true);
    try {
      await ref.read(noteActionsProvider).setArchived(widget.noteId!, archived);
      if (mounted) context.go(AppRoutes.notes);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.displayMessage;
          _saving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: const Text(
          'Запись исчезнет из списка, но останется в базе — её можно будет '
          'восстановить.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(noteActionsProvider).delete(widget.noteId!);
      if (mounted) context.go(AppRoutes.notes);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.displayMessage;
          _saving = false;
        });
      }
    }
  }

  void _addTag() {
    final raw = _tagController.text.trim();
    if (raw.isEmpty) return;

    if (raw.length > _maxTagLength) {
      setState(() => _error = 'Тег длиннее $_maxTagLength символов');
      return;
    }
    if (_tags.length >= _maxTags) {
      setState(() => _error = 'Не больше $_maxTags тегов на запись');
      return;
    }

    // Бэкенд приводит регистр к нижнему, поэтому «Работа» и «работа» —
    // один тег. Проверяем это здесь же, чтобы не плодить дубли в интерфейсе.
    final normalized = raw.toLowerCase();
    if (_tags.any((String tag) => tag.toLowerCase() == normalized)) {
      _tagController.clear();
      return;
    }

    setState(() {
      _tags = <String>[..._tags, raw];
      _tagController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isArchived = _note?.isArchived ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Редактирование' : 'Новая запись'),
        actions: <Widget>[
          if (widget.isEditing)
            PopupMenuButton<String>(
              enabled: !_saving,
              onSelected: (String value) {
                if (value == 'archive') _setArchived(!isArchived);
                if (value == 'delete') _delete();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'archive',
                  child: Text(isArchived ? 'Вернуть из архива' : 'В архив'),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Удалить'),
                ),
              ],
            ),
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: 'Сохранить',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SegmentedButton<NoteType>(
              segments: NoteType.values
                  .map(
                    (NoteType type) => ButtonSegment<NoteType>(
                      value: type,
                      label: Text(type.label),
                      icon: Icon(
                        type == NoteType.link ? Icons.link : Icons.notes,
                      ),
                    ),
                  )
                  .toList(growable: false),
              selected: <NoteType>{_type},
              showSelectedIcon: false,
              onSelectionChanged: _saving
                  ? null
                  : (Set<NoteType> selection) =>
                      setState(() => _type = selection.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              enabled: !_saving,
              maxLength: _maxTitleLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Заголовок',
                counterText: '',
              ),
              validator: (String? value) =>
                  (value == null || value.trim().isEmpty)
                      ? 'Заголовок обязателен'
                      : null,
            ),
            if (_type == NoteType.link) ...<Widget>[
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Ссылка',
                  hintText: 'https://example.com',
                  prefixIcon: Icon(Icons.link),
                ),
                validator: _validateUrl,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _contentController,
              enabled: !_saving,
              minLines: 5,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Текст',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            Text('Теги', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_tags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags
                    .map(
                      (String tag) => InputChip(
                        label: Text(tag),
                        onDeleted: _saving
                            ? null
                            : () => setState(
                                  () => _tags = _tags
                                      .where((String item) => item != tag)
                                      .toList(growable: false),
                                ),
                      ),
                    )
                    .toList(growable: false),
              ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    enabled: !_saving,
                    maxLength: _maxTagLength,
                    decoration: const InputDecoration(
                      labelText: 'Новый тег',
                      counterText: '',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: IconButton.filledTonal(
                    onPressed: _saving ? null : _addTag,
                    icon: const Icon(Icons.add),
                    tooltip: 'Добавить тег',
                  ),
                ),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              _ErrorBanner(message: _error!),
            ],
          ],
        ),
      ),
    );
  }

  static String? _validateUrl(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty) return 'Для ссылки нужен адрес';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Адрес должен начинаться с http:// или https://';
    }
    if (uri.host.isEmpty) return 'В адресе нет домена';
    return null;
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
