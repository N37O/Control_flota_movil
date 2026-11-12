import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistema_flota/screens/login_screen.dart';
import 'package:sistema_flota/screens/unidades_screen.dart';
import 'package:sistema_flota/screens/viajes_screen.dart';
import 'package:sistema_flota/services/api_service.dart';

ApiService _api({
  int tripStatus = 1,
  String? currentFuel,
  String tankCapacity = '80.00',
}) => ApiService(
  baseUrl: 'https://fleet.example/api',
  client: MockClient((request) async {
    final path = request.url.path;
    final List<Map<String, dynamic>> results;
    if (path.endsWith('/unidades/unidades/')) {
      results = [
        {
          'id_unidad': 1,
          'placa': 'TEST-001',
          'id_tipo_unidad': 1,
          'id_estado_unidad': 1,
          'id_conductor': 1,
          'capacidad_ton': '10.00',
          'capacidad_tanque_gal': tankCapacity,
          'combustible_actual_gal': currentFuel,
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
    } else if (path.endsWith('/viajes/viajes/')) {
      results = [
        {
          'id_viaje': 5,
          'correlativo': 'V-005',
          'id_estado_viaje': tripStatus,
          'id_unidad': 1,
          'unidad_placa': 'TEST-001',
          'conductor_nombre': 'Conductora de prueba',
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
      results = [];
    }

    return http.Response(
      jsonEncode({'count': results.length, 'next': null, 'results': results}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  testWidgets('login requires the same minimum lengths as the web form', (
    tester,
  ) async {
    final api = _api();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(api: api, onLogin: (_) async {}),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ab');
    await tester.enterText(fields.at(1), '12345');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(
      find.text('El usuario debe tener al menos 3 caracteres.'),
      findsOneWidget,
    );
    expect(
      find.text('La contraseña debe tener al menos 6 caracteres.'),
      findsOneWidget,
    );
  });

  testWidgets('unit form prevents duplicate plates and invalid precision', (
    tester,
  ) async {
    final api = _api();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UnidadesScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test-001');
    await tester.enterText(fields.at(1), 'UNIT-002');
    await tester.enterText(fields.at(2), '10.123');
    await tester.enterText(fields.at(3), '80');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Esta placa ya está registrada.'), findsOneWidget);
    expect(
      find.text('Usa un número mayor que cero con hasta dos decimales.'),
      findsOneWidget,
    );
  });

  testWidgets('unit form requires all web-required fields', (tester) async {
    final api = _api();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UnidadesScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('La placa es obligatoria.'), findsOneWidget);
    expect(find.text('El código interno es obligatorio.'), findsOneWidget);
    expect(find.text('Selecciona un tipo de unidad.'), findsOneWidget);
    expect(find.text('Selecciona un estado.'), findsOneWidget);
    expect(
      find.text('Usa un número mayor que cero con hasta dos decimales.'),
      findsNWidgets(2),
    );
  });

  testWidgets('refuel validates tank capacity and decimal precision', (
    tester,
  ) async {
    final api = _api();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UnidadesScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recarga'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST-001').last);
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '81');
    await tester.enterText(fields.at(1), '82');
    await tester.enterText(fields.at(2), '1.2345');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No puede superar la capacidad del tanque (80.00 gal).'),
      findsNWidgets(2),
    );
    expect(
      find.text('Usa un número mayor que cero con hasta 3 decimales.'),
      findsOneWidget,
    );
  });

  testWidgets('new unit displays no reading and requires first tank level', (
    tester,
  ) async {
    final api = _api();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UnidadesScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin lectura'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Recarga'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST-001').last);
    await tester.pumpAndSettle();

    expect(find.text('Nivel final del tanque (gal) *'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '20');
    await tester.enterText(find.byType(TextFormField).at(2), '4.50');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'La primera recarga requiere indicar el nivel final real del tanque.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('refuel cannot exceed the remaining tank capacity', (
    tester,
  ) async {
    final api = _api(currentFuel: '30.00', tankCapacity: '60.00');
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UnidadesScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recarga'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST-001').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '60');
    await tester.enterText(find.byType(TextFormField).at(1), '1');
    await tester.enterText(find.byType(TextFormField).at(2), '4');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('La unidad ya tiene 30.00 gal; solo puede cargar'),
      findsOneWidget,
    );
    expect(
      find.text('Nivel registrado: 30.00 gal · Espacio disponible: 30.00 gal'),
      findsOneWidget,
    );
  });

  testWidgets('trip form rejects an existing correlativo', (tester) async {
    final api = _api(tripStatus: 3);
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ViajesScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'V-005');
    await tester.tap(find.text('Guardar viaje'));
    await tester.pumpAndSettle();

    expect(find.text('Este correlativo ya está registrado.'), findsOneWidget);
  });

  testWidgets('trip form requires all web-required planning fields', (
    tester,
  ) async {
    final api = _api(tripStatus: 3);
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ViajesScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar viaje'));
    await tester.pumpAndSettle();

    expect(find.text('El correlativo es obligatorio.'), findsOneWidget);
    expect(find.text('Selecciona una unidad disponible.'), findsOneWidget);
    expect(find.text('Selecciona el origen.'), findsOneWidget);
    expect(find.text('Selecciona el destino.'), findsOneWidget);
    expect(
      find.text('La fecha programada de salida es obligatoria.'),
      findsOneWidget,
    );
    expect(
      find.text('Calcula una ruta vial para definir la llegada estimada.'),
      findsOneWidget,
    );
    expect(
      find.text('La distancia debe tener hasta dos decimales.'),
      findsOneWidget,
    );
  });

  testWidgets('trip form rejects identical origin and destination', (
    tester,
  ) async {
    final api = _api(tripStatus: 3);
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ViajesScreen(api: api, isAdmin: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final locationDropdowns = find.byType(DropdownButtonFormField<int>);
    await tester.tap(locationDropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('San Salvador').last);
    await tester.pumpAndSettle();
    await tester.tap(locationDropdowns.at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('San Salvador').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar viaje'));
    await tester.pumpAndSettle();

    expect(
      find.text('El origen y el destino no pueden ser iguales.'),
      findsNWidgets(2),
    );
  });
}
