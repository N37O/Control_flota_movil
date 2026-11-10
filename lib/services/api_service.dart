import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

typedef TokenUpdate = Future<void> Function(String? access, String? refresh);

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiService {
  ApiService({
    required String baseUrl,
    this.accessToken,
    this.refreshToken,
    this.onTokenUpdate,
    this.onSessionExpired,
    http.Client? client,
  }) : _baseUrl = _normalizeBaseUrl(baseUrl),
       _client = client ?? http.Client();

  String _baseUrl;
  String? accessToken;
  String? refreshToken;
  final TokenUpdate? onTokenUpdate;
  Future<void> Function()? onSessionExpired;
  final http.Client _client;

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String value) {
    _baseUrl = _normalizeBaseUrl(value);
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw const ApiException('Indica la dirección de la API.');
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ApiException('La dirección de la API no es válida.');
    }
    return normalized;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await _request(
      'usuarios/login/',
      method: 'POST',
      body: {'usuario': username, 'password': password},
      authenticated: false,
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException(
        'La API devolvió una respuesta de acceso no válida.',
      );
    }
    final access = data['access'];
    final refresh = data['refresh'];
    if (access is! String || refresh is! String) {
      throw const ApiException(
        'La respuesta de acceso no contiene los tokens necesarios.',
      );
    }
    accessToken = access;
    refreshToken = refresh;
    await onTokenUpdate?.call(access, refresh);
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getList(String path) async {
    final List<Map<String, dynamic>> results = [];
    String? next = _uriFor(path).toString();
    var pageCount = 0;

    while (next != null) {
      if (++pageCount > 50) {
        throw const ApiException('La API devolvió demasiadas páginas.');
      }
      final response = await _requestUri(Uri.parse(next));
      if (response is List) {
        results.addAll(response.whereType<Map>().map(_toStringKeyMap));
        next = null;
      } else if (response is Map<String, dynamic>) {
        final pageResults = response['results'];
        if (pageResults is List) {
          results.addAll(pageResults.whereType<Map>().map(_toStringKeyMap));
        }
        final nextValue = response['next'];
        next = nextValue is String && nextValue.isNotEmpty ? nextValue : null;
      } else {
        throw const ApiException(
          'El formato de la lista recibida no es válido.',
        );
      }
    }
    return results;
  }

  Map<String, dynamic> _toStringKeyMap(Map value) =>
      value.map((key, dynamic item) => MapEntry(key.toString(), item));

  Future<Map<String, dynamic>> getMap(String path) async {
    final data = await _request(path);
    if (data is! Map<String, dynamic>) {
      throw const ApiException('La API devolvió una respuesta no válida.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _request(path, method: 'POST', body: body);

  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _request(path, method: 'PATCH', body: body);

  Future<dynamic> postMultipart(
    String path,
    Map<String, dynamic> fields, {
    required String fileField,
    required String filePath,
  }) => _requestMultipart(
    path,
    method: 'POST',
    fields: fields,
    fileField: fileField,
    filePath: filePath,
  );

  Future<dynamic> patchMultipart(
    String path,
    Map<String, dynamic> fields, {
    required String fileField,
    required String filePath,
  }) => _requestMultipart(
    path,
    method: 'PATCH',
    fields: fields,
    fileField: fileField,
    filePath: filePath,
  );

  Future<dynamic> delete(String path) => _request(path, method: 'DELETE');

  Uri _uriFor(String path) {
    final cleanPath = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$_baseUrl/$cleanPath');
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) => _requestUri(
    _uriFor(path),
    method: method,
    body: body,
    authenticated: authenticated,
  );

  Future<dynamic> _requestMultipart(
    String path, {
    required String method,
    required Map<String, dynamic> fields,
    required String fileField,
    required String filePath,
    bool retry = true,
  }) async {
    final request = http.MultipartRequest(method, _uriFor(path))
      ..headers['Accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    request.fields.addAll(
      fields.map((key, value) => MapEntry(key, value?.toString() ?? '')),
    );

    http.Response response;
    try {
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
      response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 20)),
      );
    } on http.ClientException {
      throw ApiException(_connectionErrorMessage(_uriFor(path)));
    } on TimeoutException {
      throw ApiException(
        'La API tardó demasiado en responder. ${_connectionErrorMessage(_uriFor(path))}',
      );
    } on FileSystemException {
      throw const ApiException('No se pudo leer la foto seleccionada.');
    }

    if (response.statusCode == 401 && retry) {
      if (refreshToken != null && await _refreshAccessToken()) {
        return _requestMultipart(
          path,
          method: method,
          fields: fields,
          fileField: fileField,
          filePath: filePath,
          retry: false,
        );
      }
      await logout();
      await onSessionExpired?.call();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 204 || response.body.isEmpty) return null;

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException(
        'La API devolvió una respuesta que no es JSON válido.',
      );
    }
  }

  Future<dynamic> _requestUri(
    Uri uri, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retry = true,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (authenticated && accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await _client
              .post(
                uri,
                headers: headers,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(const Duration(seconds: 20));
        case 'PATCH':
          response = await _client
              .patch(
                uri,
                headers: headers,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(const Duration(seconds: 20));
        case 'DELETE':
          response = await _client
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
        default:
          response = await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
      }
    } on http.ClientException {
      throw ApiException(_connectionErrorMessage(uri));
    } on TimeoutException {
      throw ApiException(
        'La API tardó demasiado en responder. ${_connectionErrorMessage(uri)}',
      );
    }

    if (response.statusCode == 401 && authenticated && retry) {
      if (refreshToken != null && await _refreshAccessToken()) {
        return _requestUri(
          uri,
          method: method,
          body: body,
          authenticated: authenticated,
          retry: false,
        );
      }
      await logout();
      await onSessionExpired?.call();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 204 || response.body.isEmpty) return null;

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException(
        'La API devolvió una respuesta que no es JSON válido.',
      );
    }
  }

  Future<bool> _refreshAccessToken() async {
    final currentRefresh = refreshToken;
    if (currentRefresh == null) return false;

    http.Response response;
    try {
      response = await _client
          .post(
            _uriFor('usuarios/token/refresh/'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'refresh': currentRefresh}),
          )
          .timeout(const Duration(seconds: 20));
    } on http.ClientException {
      return false;
    } on TimeoutException {
      return false;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> || data['access'] is! String) {
        return false;
      }
      accessToken = data['access'] as String;
      refreshToken = data['refresh'] is String
          ? data['refresh'] as String
          : currentRefresh;
      await onTokenUpdate?.call(accessToken, refreshToken);
      return true;
    } on FormatException {
      return false;
    }
  }

  String _errorMessage(http.Response response) {
    if (response.statusCode == 401) {
      return 'La sesión expiró. Inicia sesión de nuevo.';
    }
    if (response.statusCode == 403) {
      return 'No tienes permiso para realizar esta acción.';
    }
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map) {
        final detail = data['detail'] ?? data['error'];
        if (detail != null) return detail.toString();
        return data.entries
            .map((entry) => '${entry.key}: ${_formatError(entry.value)}')
            .join('\n');
      }
      if (data is List) return data.map(_formatError).join('\n');
    } on FormatException {
      return 'Error ${response.statusCode} al comunicarse con la API.';
    }
    return 'Error ${response.statusCode} al comunicarse con la API.';
  }

  String _connectionErrorMessage(Uri uri) {
    if (uri.host == '10.0.2.2') {
      return 'Verifica que la API esté activa. En un teléfono físico, cambia '
          '10.0.2.2 por la IP local del equipo y ejecuta Django en 0.0.0.0:8000.';
    }
    return 'Verifica la dirección de la API, que el servidor esté activo y '
        'que el teléfono y el equipo estén en la misma red.';
  }

  String _formatError(dynamic value) {
    if (value is List) return value.map(_formatError).join(', ');
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${_formatError(entry.value)}')
          .join(', ');
    }
    return value.toString();
  }

  Future<void> logout() async {
    accessToken = null;
    refreshToken = null;
    await onTokenUpdate?.call(null, null);
  }

  void dispose() => _client.close();
}
