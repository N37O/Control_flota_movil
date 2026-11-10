import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_flota/main.dart';
import 'package:sistema_flota/services/api_service.dart';

void main() {
  testWidgets('hides API settings on the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = ApiService(baseUrl: 'http://10.0.2.2:8000/api');

    await tester.pumpWidget(
      FlotaApp(api: api, preferences: preferences, initialUser: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sistema de Flota'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Usuario'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Dirección de la API'), findsNothing);
    expect(find.text('Emulador'), findsNothing);
    expect(find.text('Teléfono USB'), findsNothing);
    expect(find.text('Teléfono Wi-Fi'), findsNothing);

    api.dispose();
  });

  testWidgets('denies administrator mobile login and clears its tokens', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = ApiService(
      baseUrl: 'https://fleet.example/api',
      onTokenUpdate: (access, refresh) async {
        if (access == null || refresh == null) {
          await preferences.remove('access_token');
          await preferences.remove('refresh_token');
        } else {
          await preferences.setString('access_token', access);
          await preferences.setString('refresh_token', refresh);
        }
      },
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'access': 'administrator-access-token',
            'refresh': 'administrator-refresh-token',
            'usuario': {
              'nombre': 'Administradora',
              'rol_nombre': 'ADMINISTRADOR',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.dispose);

    await tester.pumpWidget(
      FlotaApp(api: api, preferences: preferences, initialUser: null),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'El rol administrador no puede acceder desde la aplicación móvil. '
        'Usa el panel web.',
      ),
      findsOneWidget,
    );
    expect(find.text('Resumen de flota'), findsNothing);
    expect(api.accessToken, isNull);
    expect(api.refreshToken, isNull);
    expect(preferences.getString('access_token'), isNull);
    expect(preferences.getString('refresh_token'), isNull);
  });

  testWidgets('blocks a stored administrator session before showing modules', (
    tester,
  ) async {
    final user = {'nombre': 'Administradora', 'rol_nombre': 'ADMINISTRADOR'};
    SharedPreferences.setMockInitialValues({
      'access_token': 'existing-access-token',
      'refresh_token': 'existing-refresh-token',
      'user_data': jsonEncode(user),
    });
    final preferences = await SharedPreferences.getInstance();
    final api = ApiService(
      baseUrl: 'https://fleet.example/api',
      accessToken: 'existing-access-token',
      refreshToken: 'existing-refresh-token',
      onTokenUpdate: (access, refresh) async {
        if (access == null || refresh == null) {
          await preferences.remove('access_token');
          await preferences.remove('refresh_token');
        }
      },
      client: MockClient((_) async {
        return http.Response(
          jsonEncode(user),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.dispose);

    await tester.pumpWidget(
      FlotaApp(api: api, preferences: preferences, initialUser: user),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resumen de flota'), findsNothing);
    expect(
      find.text(
        'El rol administrador no puede acceder desde la aplicación móvil. '
        'Usa el panel web.',
      ),
      findsOneWidget,
    );
    expect(api.accessToken, isNull);
    expect(preferences.getString('access_token'), isNull);
    expect(preferences.getString('refresh_token'), isNull);
    expect(preferences.getString('user_data'), isNull);
  });
}
