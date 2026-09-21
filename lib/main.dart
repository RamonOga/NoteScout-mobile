import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/session/session_store.dart';
import 'core/session/token_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Сессию читаем до первого кадра: иначе роутер успел бы показать экран входа
  // уже авторизованному пользователю, и экран мигнул бы.
  final sessionStore = SessionStore(SecureTokenStorage());
  await sessionStore.load();

  runApp(
    ProviderScope(
      // Тип элемента — Override; он не экспортируется из flutter_riverpod,
      // поэтому список задаётся без явного аргумента типа.
      overrides: [
        sessionStoreProvider.overrideWithValue(sessionStore),
      ],
      child: const NoteScoutApp(),
    ),
  );
}
