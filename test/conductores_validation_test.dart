import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistema_flota/screens/conductores_screen.dart';
import 'package:sistema_flota/services/api_service.dart';

void main() {
  testWidgets('creates a driver and refreshes the list after saving', (
    tester,
  ) async {
    final requests = <http.Request>[];
    var driverName = '';
    final api = ApiService(
      baseUrl: 'https://fleet.example/api',
      accessToken: 'driver-access-token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          driverName = data['nombre'] as String;
          return http.Response(
            jsonEncode({'id_conductor': 9, ...data}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'count': driverName.isEmpty ? 0 : 1,
            'next': null,
            'results': driverName.isEmpty
                ? []
                : [
                    {'id_conductor': 9, 'nombre': driverName, 'activo': true},
                  ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ConductoresScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Conductor Nuevo');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(requests.where((request) => request.method == 'POST'), hasLength(1));
    expect(
      requests.every(
        (request) =>
            request.headers['Authorization'] == 'Bearer driver-access-token',
      ),
      isTrue,
    );
    expect(find.text('Conductor Nuevo'), findsOneWidget);
    expect(find.text('Conductor creado correctamente.'), findsOneWidget);
  });

  testWidgets('updates a driver and refreshes the list after saving', (
    tester,
  ) async {
    final requests = <http.Request>[];
    var driverName = 'Conductora existente';
    final api = ApiService(
      baseUrl: 'https://fleet.example/api',
      accessToken: 'driver-access-token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'PATCH') {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          driverName = data['nombre'] as String;
          return http.Response(
            jsonEncode({'id_conductor': 1, ...data}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'count': 1,
            'next': null,
            'results': [
              {
                'id_conductor': 1,
                'nombre': driverName,
                'dui': '',
                'licencia': '',
                'tipo_licencia': 'Pesado',
                'telefono': '',
                'activo': true,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ConductoresScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Conductora Editada',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request.method == 'PATCH'),
      hasLength(1),
    );
    expect(
      requests.every(
        (request) =>
            request.headers['Authorization'] == 'Bearer driver-access-token',
      ),
      isTrue,
    );
    expect(find.text('Conductora Editada'), findsOneWidget);
    expect(find.text('Conductor actualizado correctamente.'), findsOneWidget);
  });

  testWidgets('driver form validates web rules and offers camera and gallery', (
    tester,
  ) async {
    final api = ApiService(
      baseUrl: 'https://fleet.example/api',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'count': 1,
            'next': null,
            'results': [
              {
                'id_conductor': 1,
                'nombre': 'Conductora existente',
                'dui': '12345678-9',
                'licencia': '87654321-0',
                'tipo_licencia': 'Pesado',
                'telefono': '71234567',
                'activo': true,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ConductoresScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Cámara'), findsOneWidget);
    expect(find.text('Galería'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Al');
    await tester.enterText(fields.at(1), '12345678-9');
    await tester.enterText(fields.at(2), '87654321-0');
    await tester.enterText(fields.at(4), '1234567');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('El nombre debe tener al menos 3 caracteres.'),
      findsOneWidget,
    );
    expect(find.text('Este número ya está registrado.'), findsNWidgets(2));
    expect(find.text('Escribe un teléfono de 8 o 9 dígitos.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
