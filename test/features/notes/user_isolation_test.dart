import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/core/models/user.dart';
import 'package:notescout_mobile/core/providers.dart';
import 'package:notescout_mobile/core/session/auth_session.dart';
import 'package:notescout_mobile/core/session/session_store.dart';
import 'package:notescout_mobile/core/session/token_storage.dart';
import 'package:notescout_mobile/features/notes/application/notes_controller.dart';
import 'package:notescout_mobile/features/notes/data/notes_api.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/notes_fixtures.dart';

AuthSession _sessionFor(String userId) => AuthSession(
      accessToken: 'access-$userId',
      refreshToken: 'refresh-$userId',
      user: User(
        id: userId,
        email: '$userId@example.com',
        displayName: userId,
        createdAt: DateTime.utc(2026, 9, 1),
      ),
    );

/// Регрессия на баг, который выглядел как утечка данных.
///
/// Состояние списка живёт в контейнере провайдеров весь сеанс приложения.
/// Пока список не был привязан к пользователю, после выхода и входа другим
/// аккаунтом на экране оставались записи предыдущего: провайдер не считал
/// нужным перезапрашивать данные.
void main() {
  test('после смены пользователя список перезапрашивается, а фильтры сбрасываются',
      () async {
    var responseTitle = 'Записи A';
    final adapter = FakeHttpAdapter(
      (_) async => jsonResponse(
        notesPageJson(<Map<String, dynamic>>[noteJson(title: responseTitle)]),
      ),
    );

    final store = SessionStore(InMemoryTokenStorage(_sessionFor('user-a')));
    await store.load();

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        notesApiProvider.overrideWithValue(NotesApi(apiClient: dioWith(adapter))),
      ],
    );
    addTearDown(container.dispose);

    // Пользователь A успел выбрать фильтр — он не должен переехать к B.
    container.read(notesQueryProvider.notifier).setText('док');
    final asUserA = await container.read(notesControllerProvider.future);
    expect(asUserA.notes.single.title, 'Записи A');

    // Подписка до смены сессии: она поймает пересборку списка.
    final reloaded = Completer<NotesState>();
    container.listen<AsyncValue<NotesState>>(
      notesControllerProvider,
      (previous, next) {
        final value = next.value;
        if (value != null &&
            value.notes.isNotEmpty &&
            value.notes.first.title == 'Записи B' &&
            !reloaded.isCompleted) {
          reloaded.complete(value);
        }
      },
      fireImmediately: true,
    );

    responseTitle = 'Записи B';
    await store.save(_sessionFor('user-b'));

    final asUserB = await reloaded.future.timeout(const Duration(seconds: 5));

    expect(asUserB.notes.single.title, 'Записи B');
    expect(container.read(notesQueryProvider).text, isEmpty,
        reason: 'фильтр прошлого пользователя не должен остаться');
    expect(adapter.requestedQueries.last.containsKey('q'), isFalse);
  });

  test('обновление того же пользователя не перезагружает список зря', () async {
    final adapter = FakeHttpAdapter(
      (_) async => jsonResponse(
        notesPageJson(<Map<String, dynamic>>[noteJson(title: 'Записи')]),
      ),
    );

    final store = SessionStore(InMemoryTokenStorage(_sessionFor('user-a')));
    await store.load();

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        notesApiProvider.overrideWithValue(NotesApi(apiClient: dioWith(adapter))),
      ],
    );
    addTearDown(container.dispose);

    await container.read(notesControllerProvider.future);
    final requestsBefore = adapter.requestedPaths.length;

    // Так выглядит обновление access-токена: сессия сохраняется заново,
    // но пользователь тот же.
    await store.save(_sessionFor('user-a'));
    await Future<void>.delayed(Duration.zero);

    expect(adapter.requestedPaths.length, requestsBefore,
        reason: 'смена токена не должна тянуть новый список');
  });
}
