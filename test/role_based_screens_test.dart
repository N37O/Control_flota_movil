import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistema_flota/screens/conductores_screen.dart';
import 'package:sistema_flota/screens/home_shell.dart';
import 'package:sistema_flota/screens/unidades_screen.dart';
import 'package:sistema_flota/screens/viajes_screen.dart';
import 'package:sistema_flota/services/api_service.dart';

ApiService _api({List<Map<String, dynamic>>? trips}) => ApiService(
  baseUrl: 'https://fleet.example/api',
  client: MockClient((request) async {
    final path = request.url.path;
    final dynamic results;
    if (path.endsWith('/unidades/unidades/')) {
      results = [
        {
          'id_unidad': 1,
          'placa': 'TEST-001',
          'id_tipo_unidad': 1,
          'id_estado_unidad': 1,
          'id_conductor': 1,
          'capacidad_ton': '10.00',
          'capacidad_tanque_gal': '80.00',
          'combustible_actual_gal': '38.50',
          'odometro_actual': 12345,
          'activo': true,
          'conductor_nombre': 'Conductora de prueba',
          'estado_nombre': 'DISPONIBLE',
        },
      ];
    } else if (path.endsWith('/unidades/tipos/')) {
      results = [
        {'id_tipo_unidad': 1, 'nombre': 'Camión'},
      ];
    } else if (path.endsWith('/unidades/estados/')) {
      results = [
        {'id_estado_unidad': 1, 'nombre': 'DISPONIBLE'},
      ];
    } else if (path.endsWith('/unidades/conductores/')) {
      results = [
        {
          'id_conductor': 1,
          'nombre': 'Conductora de prueba',
          'dui': '12345678-9',
          'licencia': '87654321-0',
          'tipo_licencia': 'Pesado',
          'telefono': '70000000',
          'activo': true,
        },
      ];
    } else if (path.endsWith('/viajes/viajes/')) {
      results =
          trips ??
          [
            {
              'id_viaje': 5,
              'correlativo': 'V-005',
              'id_estado_viaje': 1,
              'id_unidad': 1,
              'unidad_placa': 'TEST-001',
              'conductor_nombre': 'Conductora de prueba',
              'origen_nombre': 'San Salvador',
              'destino_nombre': 'Santa Ana',
            },
          ];
    } else if (path.endsWith('/viajes/ubicaciones/')) {
      results = [
        {
          'id_ubicacion': 1,
          'nombre': 'San Salvador',
          'latitud': '13.692900',
          'longitud': '-89.218200',
          'activo': true,
        },
        {
          'id_ubicacion': 2,
          'nombre': 'Santa Ana',
          'latitud': '13.994200',
          'longitud': '-89.559700',
          'activo': true,
        },
      ];
    } else {
      results = <dynamic>[];
    }
    return http.Response(
      jsonEncode({'count': results.length, 'next': null, 'results': results}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  testWidgets('operator navigation exposes operations without administration', (
    tester,
  ) async {
    final api = _api();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          api: api,
          user: {'nombre': 'Operador', 'rol_nombre': 'OPERADOR'},
          roleVerified: true,
          roleVerificationError: null,
          onVerifyRole: () async {},
          onLogout: () async {},
          onSessionExpired: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operaciones'), findsOneWidget);
    expect(find.text('Conductores'), findsNothing);
    expect(find.text('Reportes'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets('operations reloads trips when opened after trips change', (
    tester,
  ) async {
    final trips = [
      {
        'id_viaje': 5,
        'correlativo': 'V-005',
        'id_estado_viaje': 1,
        'id_unidad': 1,
        'unidad_placa': 'TEST-001',
        'conductor_nombre': 'Conductora de prueba',
        'origen_nombre': 'San Salvador',
        'destino_nombre': 'Santa Ana',
      },
    ];
    final api = _api(trips: trips);
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          api: api,
          user: {'nombre': 'Operador', 'rol_nombre': 'OPERADOR'},
          roleVerified: true,
          roleVerificationError: null,
          onVerifyRole: () async {},
          onLogout: () async {},
          onSessionExpired: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Viajes').last);
    await tester.pumpAndSettle();
    trips.add({
      'id_viaje': 6,
      'correlativo': 'V-006',
      'id_estado_viaje': 1,
      'id_unidad': 1,
      'id_origen': 1,
      'id_destino': 2,
      'unidad_placa': 'TEST-002',
      'conductor_nombre': 'Otro conductor',
      'origen_nombre': 'San Salvador',
      'destino_nombre': 'Santa Ana',
    });
    trips.add({
      'id_viaje': 7,
      'correlativo': 'V-007',
      'id_estado_viaje': 2,
      'id_unidad': 1,
      'id_origen': 1,
      'id_destino': 2,
      'unidad_placa': 'TEST-003',
      'conductor_nombre': 'Conductora de prueba',
      'origen_nombre': 'San Salvador',
      'destino_nombre': 'Santa Ana',
    });

    await tester.tap(find.text('Operaciones').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salidas y entradas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, ' v-006 ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('V-006').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Unidad: TEST-002 · Conductor: Otro conductor'),
      findsOneWidget,
    );
    expect(find.text('Se registrará en: San Salvador'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller
          ?.text,
      '12345',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller
          ?.text,
      '38.50',
    );

    await tester.tap(find.text('Entrada'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'V-007');
    await tester.pumpAndSettle();
    await tester.tap(find.text('V-007').last);
    await tester.pumpAndSettle();

    expect(find.text('Se registrará en: Santa Ana'), findsOneWidget);
    expect(find.text('Busca entre los viajes en curso.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller
          ?.text,
      '12345',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller
          ?.text,
      '38.50',
    );
  });

  testWidgets('supervisor navigation exposes consultation and reports only', (
    tester,
  ) async {
    final api = _api();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          api: api,
          user: {'nombre': 'Supervisor', 'rol_nombre': 'SUPERVISOR'},
          roleVerified: true,
          roleVerificationError: null,
          onVerifyRole: () async {},
          onLogout: () async {},
          onSessionExpired: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Operaciones'), findsNothing);
    expect(find.text('Conductores'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets('operator can register units and refuels, but not edit units', (
    tester,
  ) async {
    final api = _api();
    await tester.pumpWidget(
      MaterialApp(
        home: UnidadesScreen(api: api, isAdmin: false, canRegister: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TEST-001'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Recarga'), findsOneWidget);
    api.dispose();
  });

  testWidgets('operator sees drivers but no create, edit, or delete actions', (
    tester,
  ) async {
    final api = _api();
    await tester.pumpWidget(
      MaterialApp(home: ConductoresScreen(api: api, isAdmin: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conductora de prueba'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    api.dispose();
  });

  testWidgets('operator can register trips but not update or cancel them', (
    tester,
  ) async {
    final api = _api();
    await tester.pumpWidget(
      MaterialApp(
        home: ViajesScreen(api: api, isAdmin: false, canRegister: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('V-005'), findsOneWidget);
    expect(find.text('San Salvador → Santa Ana'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    api.dispose();
  });
}
