import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/core/session/auth_session.dart';
import 'package:notescout_mobile/core/session/session_store.dart';
import 'package:notescout_mobile/core/session/token_storage.dart';

import '../support/fake_http_adapter.dart';

AuthSession _session({String access = 'access-1', String refresh = 'refresh-1'}) =>
    AuthSession.fromJson(
      tokenResponseJson(accessToken: access, refreshToken: refresh),
    );

void main() {
  group('SessionStore', () {
    test('после загрузки возвращает сохранённую сессию', () async {
      final storage = InMemoryTokenStorage(_session());
      final store = SessionStore(storage);

      final restored = await store.load();

      expect(restored, isNotNull);
      expect(restored!.user.email, 'ivan@example.com');
      expect(store.isSignedIn, isTrue);
    });

    test('без сохранённой сессии состояние — «не вошёл»', () async {
      final store = SessionStore(InMemoryTokenStorage());

      await store.load();

      expect(store.session, isNull);
      expect(store.isSignedIn, isFalse);
    });

    test('save и clear уведомляют слушателей', () async {
      final store = SessionStore(InMemoryTokenStorage());
      var notifications = 0;
      store.addListener(() => notifications++);

      await store.save(_session());
      expect(store.isSignedIn, isTrue);

      await store.clear();
      expect(store.isSignedIn, isFalse);

      // load() тоже уведомляет, поэтому здесь проверяем только save и clear.
      expect(notifications, 2);
    });

    test('сессия переживает пересоздание store поверх того же хранилища', () async {
      final storage = InMemoryTokenStorage();

      await SessionStore(storage).save(_session(access: 'token-a'));
      final restored = await SessionStore(storage).load();

      expect(restored!.accessToken, 'token-a');
    });
  });
}
