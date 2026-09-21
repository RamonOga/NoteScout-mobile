import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notescout_mobile/core/providers.dart';
import 'package:notescout_mobile/core/session/token_storage.dart';
import 'package:notescout_mobile/features/auth/presentation/login_page.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  group('LoginPage', () {
    testWidgets('пустая форма показывает ошибки под обоими полями',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const LoginPage()));

      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pump();

      expect(find.text('Введите email'), findsOneWidget);
      expect(find.text('Введите пароль'), findsOneWidget);
    });

    testWidgets('некорректный email не проходит валидацию',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const LoginPage()));

      await tester.enterText(find.byType(TextFormField).first, 'не-email');
      await tester.enterText(find.byType(TextFormField).last, 'secret-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pump();

      expect(find.text('Некорректный email'), findsOneWidget);
    });

    testWidgets('есть переход на экран регистрации',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const LoginPage()));

      expect(find.text('Нет аккаунта? Зарегистрироваться'), findsOneWidget);
    });
  });
}
