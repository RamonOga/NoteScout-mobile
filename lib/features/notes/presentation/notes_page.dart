import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_service.dart';

/// Заглушка после входа.
///
/// Список заметок, редактор и поиск по тегам появятся следующим шагом;
/// сейчас экран нужен, чтобы проверить весь путь авторизации целиком:
/// вход → хранение сессии → выход.
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);

    await ref.read(authServiceProvider).signOut();
    // Экран уничтожит роутер: сессия очищена, refreshListenable сработал.
  }

  @override
  Widget build(BuildContext context) {
    final sessionStore = ref.watch(sessionStoreProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NoteScout'),
        actions: <Widget>[
          IconButton(
            onPressed: _signingOut ? null : _signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: sessionStore,
        builder: (context, _) {
          final user = sessionStore.session?.user;

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.check_circle_outline,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user == null ? 'Вы вошли' : 'Здравствуйте, ${user.displayName}',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user?.email ?? '',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Авторизация работает.\nСписок заметок, теги и поиск — следующий шаг.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
