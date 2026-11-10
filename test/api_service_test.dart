import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistema_flota/services/api_service.dart';

void main() {
  test('explains the physical phone API address after a timeout', () async {
    final api = ApiService(
      baseUrl: 'http://10.0.2.2:8000/api',
      client: MockClient((request) async {
        throw TimeoutException('request timed out');
      }),
    );
    addTearDown(api.dispose);

    await expectLater(
      api.login('operator', 'password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('La API tardó demasiado'),
            contains('teléfono físico'),
            contains('0.0.0.0:8000'),
          ),
        ),
      ),
    );
  });

  test('uploads driver license photos as multipart form data', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'fleet-license-test',
    );
    final image = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}licencia.jpg',
    );
    await image.writeAsString('license image');
    http.Request? sentRequest;
    final api = ApiService(
      baseUrl: 'https://fleet.example/api',
      accessToken: 'access-token',
      client: MockClient((request) async {
        expect(request, isA<http.Request>());
        sentRequest = request;
        return http.Response(
          jsonEncode({'id_conductor': 9}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    try {
      await api.postMultipart(
        'unidades/conductores/',
        {'nombre': 'Conductora de prueba', 'dui': '12345678-9', 'activo': true},
        fileField: 'licencia_imagen',
        filePath: image.path,
      );

      expect(sentRequest?.method, 'POST');
      expect(
        sentRequest?.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(sentRequest?.body, contains('name="nombre"'));
      expect(sentRequest?.body, contains('Conductora de prueba'));
      expect(sentRequest?.body, contains('name="activo"'));
      expect(sentRequest?.body, contains('true'));
      expect(sentRequest?.body, contains('name="licencia_imagen"'));
      expect(sentRequest?.body, contains('filename="licencia.jpg"'));
      expect(sentRequest?.body, contains('license image'));
      expect(sentRequest?.headers['Authorization'], 'Bearer access-token');
    } finally {
      api.dispose();
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('refreshes JWT and reads every API result page', () async {
    final authorizationHeaders = <String?>[];
    var pageOneRequests = 0;
    String? persistedAccess;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/usuarios/token/refresh/')) {
        return http.Response(
          jsonEncode({'access': 'fresh-access', 'refresh': 'rotated-refresh'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      authorizationHeaders.add(request.headers['Authorization']);
      if (request.url.queryParameters['page'] == '2') {
        return http.Response(
          jsonEncode({
            'next': null,
            'results': [
              {'id_unidad': 2},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      pageOneRequests++;
      if (request.headers['Authorization'] == 'Bearer old-access') {
        return http.Response('{}', 401);
      }
      return http.Response(
        jsonEncode({
          'next': 'https://fleet.example/api/unidades/unidades/?page=2',
          'results': [
            {'id_unidad': 1},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiService(
      baseUrl: 'https://fleet.example/api',
      accessToken: 'old-access',
      refreshToken: 'current-refresh',
      client: client,
      onTokenUpdate: (access, refresh) async {
        persistedAccess = access;
      },
    );

    final units = await api.getList('unidades/unidades/');

    expect(units.map((unit) => unit['id_unidad']), [1, 2]);
    expect(pageOneRequests, 2);
    expect(authorizationHeaders, [
      'Bearer old-access',
      'Bearer fresh-access',
      'Bearer fresh-access',
    ]);
    expect(persistedAccess, 'fresh-access');
    expect(api.refreshToken, 'rotated-refresh');
    api.dispose();
  });
}
