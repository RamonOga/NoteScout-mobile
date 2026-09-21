import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/notes/presentation/note_editor_page.dart';
import '../../features/notes/presentation/notes_page.dart';
import '../providers.dart';
import 'routes.dart';

/// Таблица маршрутов и правила доступа.
///
/// `refreshListenable` — это и есть [SessionStore]: как только сессия появилась
/// или пропала, go_router сам пересчитывает `redirect`. Отдельного «флага входа»
/// в приложении нет, поэтому состояние экранов и хранилища не могут разъехаться.
final routerProvider = Provider<GoRouter>((ref) {
  final sessionStore = ref.watch(sessionStoreProvider);

  return GoRouter(
    initialLocation: AppRoutes.notes,
    refreshListenable: sessionStore,
    redirect: (context, state) {
      final signedIn = sessionStore.isSignedIn;
      final location = state.matchedLocation;
      final onAuthPage =
          location == AppRoutes.login || location == AppRoutes.register;

      if (!signedIn) {
        return onAuthPage ? null : AppRoutes.login;
      }
      return onAuthPage ? AppRoutes.notes : null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: AppRoutes.notes,
        builder: (context, state) => const NotesPage(),
        routes: <RouteBase>[
          // Порядок важен: «new» должен стоять раньше «:id», иначе создание
          // записи уйдёт в маршрут редактирования с id = "new".
          GoRoute(
            path: 'new',
            builder: (context, state) => const NoteEditorPage(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => NoteEditorPage(
              noteId: state.pathParameters['id'],
            ),
          ),
        ],
      ),
    ],
  );
});
