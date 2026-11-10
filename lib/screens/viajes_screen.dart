import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import 'common_widgets.dart';

String _formatRoutePoint(LatLng? point) => point == null
    ? 'Sin seleccionar'
    : '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';

bool _sameRoutePoint(LatLng first, LatLng second) =>
    first.latitude.toStringAsFixed(6) == second.latitude.toStringAsFixed(6) &&
    first.longitude.toStringAsFixed(6) == second.longitude.toStringAsFixed(6);

class ViajesScreen extends StatefulWidget {
  const ViajesScreen({
    required this.api,
    required this.isAdmin,
    this.canRegister = false,
    super.key,
  });

  final ApiService api;
  final bool isAdmin;
  final bool canRegister;

  @override
  State<ViajesScreen> createState() => _ViajesScreenState();
}

class _ViajesScreenState extends State<ViajesScreen> {
  bool _loading = true;
  String? _error;
  int? _statusFilter;
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _clients = [];
  late final Timer _refreshTimer;
  bool _refreshingTrips = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshTrips()),
    );
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait<List<Map<String, dynamic>>>([
        widget.api.getList('viajes/viajes/'),
        widget.api.getList('unidades/unidades/'),
        widget.api.getList('viajes/ubicaciones/'),
        widget.api.getList('viajes/clientes/'),
      ]);
      if (!mounted) return;
      setState(() {
        _trips = data[0];
        _units = data[1];
        _locations = data[2];
        _clients = data[3];
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshTrips() async {
    if (!mounted || _loading || _refreshingTrips) return;
    _refreshingTrips = true;
    try {
      final trips = await widget.api.getList('viajes/viajes/');
      if (mounted) {
        setState(() {
          _trips = trips;
          _error = null;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _refreshingTrips = false;
    }
  }

  Future<void> _showRoute(Map<String, dynamic> trip) async {
    try {
      final viajeId = trip['id_viaje'];

      final detalle = await widget.api.getMap(
        'viajes/viajes/$viajeId/',
      );

      final encodedRoute =
          detalle['polyline_ruta']?.toString().trim() ?? '';

      if (encodedRoute.isEmpty) {
        _showError('Este viaje no tiene una ruta guardada.');
        return;
      }

      late final List<LatLng> points;

      try {
      points = _decodeRoutePolyline(encodedRoute);
      } on FormatException {
        _showError('La ruta guardada no tiene un formato válido.');
        return;
      }

      if (points.length < 2) {
        _showError('La ruta guardada está incompleta.');
        return;
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _TripRouteDialog(
          trip: detalle,
          points: points,
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showError('No se pudo cargar la ruta del viaje.');
      }
      debugPrint('Error cargando ruta: $error');
    }
  }

  Future<void> _edit([Map<String, dynamic>? trip]) async {
    if (trip == null
        ? !(widget.isAdmin || widget.canRegister)
        : !widget.isAdmin) {
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _TripFormDialog(
        api: widget.api,
        trip: trip,
        existingTrips: _trips,
        units: _availableUnits(trip),
        locations: _locations
            .where((location) => readBool(location['activo'], fallback: true))
            .toList(),
        clients: _clients
            .where((client) => readBool(client['activo'], fallback: true))
            .toList(),
      ),
    );
    if (result == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              trip == null ? 'Viaje creado.' : 'Viaje actualizado.',
            ),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _availableUnits(Map<String, dynamic>? editing) {
    final reservedIds = _trips
        .where(
          (trip) =>
              readInt(trip['id_estado_viaje']) == 1 ||
              readInt(trip['id_estado_viaje']) == 2,
        )
        .where((trip) => trip['id_viaje'] != editing?['id_viaje'])
        .map((trip) => trip['id_unidad']?.toString())
        .whereType<String>()
        .toSet();
    return _units.where((unit) {
      final assigned = unit['id_conductor'] != null;
      final available = !reservedIds.contains(unit['id_unidad'].toString());
      return readBool(unit['activo'], fallback: true) && assigned && available;
    }).toList();
  }

  Future<void> _delete(Map<String, dynamic> trip) async {
    if (!widget.isAdmin) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar viaje'),
        content: Text(
          '¿Eliminar el viaje ${trip['correlativo']}? Un viaje en curso no se puede eliminar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB42318),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.delete('viajes/viajes/${trip['id_viaje']}/');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Viaje eliminado.')));
      }
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _cancel(Map<String, dynamic> trip) async {
    if (!widget.isAdmin) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar viaje'),
        content: Text('¿Cancelar el viaje ${trip['correlativo']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar viaje'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.post(
        'viajes/viajes/${trip['id_viaje']}/cambiar-estado/',
        {'estado': 'CANCELADO'},
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFB42318),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _trips.isEmpty) return const LoadingView();
    if (_error != null && _trips.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    final visible = _trips.where((trip) {
      return _statusFilter == null ||
          readInt(trip['id_estado_viaje']) == _statusFilter;
    }).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.isAdmin || widget.canRegister
          ? FloatingActionButton.extended(
              onPressed: _availableUnits(null).isEmpty || _locations.length < 2
                  ? null
                  : () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo viaje'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filter('Todos', null),
                  _filter('Programados', 1),
                  _filter('En curso', 2),
                  _filter('Completados', 3),
                  _filter('Cancelados', 4),
                ],
              ),
            ),
            if (_availableUnits(null).isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Para programar un viaje, debe haber una unidad activa disponible con conductor asignado.',
                  style: TextStyle(color: Color(0xFF8B5C00), fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const EmptyView(message: 'No se encontraron viajes.')
            else
              ...visible.map(
                (trip) => _TripCard(
                  trip: trip,
                  onRoute: () => _showRoute(trip),
                  onEdit:
                      widget.isAdmin && readInt(trip['id_estado_viaje']) == 1
                      ? () => _edit(trip)
                      : null,
                  onCancel:
                      widget.isAdmin && readInt(trip['id_estado_viaje']) == 1
                      ? () => _cancel(trip)
                      : null,
                  onDelete:
                      widget.isAdmin && readInt(trip['id_estado_viaje']) != 2
                      ? () => _delete(trip)
                      : null,
                ),
              ),
            if (_error != null) ErrorBanner(message: _error!),
          ],
        ),
      ),
    );
  }

  Widget _filter(String label, int? status) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ChoiceChip(
      label: Text(label),
      selected: _statusFilter == status,
      onSelected: (_) => setState(() => _statusFilter = status),
    ),
  );
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.onRoute,
    required this.onEdit,
    required this.onCancel,
    required this.onDelete,
  });

  final Map<String, dynamic> trip;
  final VoidCallback onRoute;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final status = readInt(trip['id_estado_viaje']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trip['correlativo']?.toString() ?? 'Viaje',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                StatusChip(
                  label: tripStatus(status),
                  color: tripStatusColor(status),
                ),
                if (onEdit != null || onCancel != null || onDelete != null)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit?.call();
                      if (value == 'cancel') onCancel?.call();
                      if (value == 'delete') onDelete?.call();
                    },
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar'),
                        ),
                      if (onCancel != null)
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancelar viaje'),
                        ),
                      if (onDelete != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Eliminar'),
                        ),
                    ],
                  ),
              ],
            ),
            Text(
              '${trip['origen_nombre'] ?? 'Origen'} → ${trip['destino_nombre'] ?? 'Destino'}',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 5),
            Text(
              'Unidad ${trip['unidad_placa'] ?? '—'} · ${trip['conductor_nombre'] ?? 'Conductor asignado'}',
              style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 12),
            ),
            if (trip['fecha_programada'] != null)
              Text(
                'Salida: ${formatDate(trip['fecha_programada'])}',
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
              ),
            if (readBool(trip['es_simulado'])) ...[
              const SizedBox(height: 4),
              Text(
                status == 2
                    ? 'Recorrido simulado · '
                          '${((readDouble(trip['progreso_simulado']) ?? 0).clamp(0.0, 1.0) * 100).round()}% completado'
                    : 'Estado generado por simulación de horario y ruta',
                style: const TextStyle(color: Color(0xFF087E8B), fontSize: 12),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRoute,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Ver mapa'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripFormDialog extends StatefulWidget {
  const _TripFormDialog({
    required this.api,
    required this.existingTrips,
    required this.units,
    required this.locations,
    required this.clients,
    this.trip,
  });

  final ApiService api;
  final List<Map<String, dynamic>> existingTrips;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> locations;
  final List<Map<String, dynamic>> clients;
  final Map<String, dynamic>? trip;

  @override
  State<_TripFormDialog> createState() => _TripFormDialogState();
}

class _TripFormDialogState extends State<_TripFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _departureFieldKey = GlobalKey<FormFieldState<DateTime>>();
  final _arrivalFieldKey = GlobalKey<FormFieldState<DateTime>>();
  late final _correlativo = TextEditingController(
    text: widget.trip?['correlativo']?.toString(),
  );
  late final _distance = TextEditingController(
    text: widget.trip?['distancia_km']?.toString(),
  );
  late final _notes = TextEditingController(
    text: widget.trip?['observaciones']?.toString(),
  );
  int? _unitId;
  int? _originId;
  int? _destinationId;
  LatLng? _originPoint;
  LatLng? _destinationPoint;
  int? _clientId;
  DateTime? _departure;
  DateTime? _arrival;
  String? _polyline;
  int? _routeDurationSeconds;
  bool _routeLoading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    _unitId = _toInt(trip?['id_unidad']);
    _originId = _toInt(trip?['id_origen']);
    _destinationId = _toInt(trip?['id_destino']);
    _originPoint = _pointForLocation(_originId);
    _destinationPoint = _pointForLocation(_destinationId);
    _clientId = _toInt(trip?['id_cliente']);
    _departure = DateTime.tryParse(trip?['fecha_programada']?.toString() ?? '');
    _arrival = DateTime.tryParse(trip?['fecha_llegada_est']?.toString() ?? '');
    _polyline = trip?['polyline_ruta']?.toString();
    if (_departure != null && _arrival != null) {
      _routeDurationSeconds = _arrival!.difference(_departure!).inSeconds;
    }
  }

  int? _toInt(dynamic value) =>
      value == null ? null : int.tryParse(value.toString());

  LatLng? _pointForLocation(int? id) {
    final location = widget.locations
        .where((item) => readInt(item['id_ubicacion']) == id)
        .firstOrNull;
    final latitude = readDouble(location?['latitud']);
    final longitude = readDouble(location?['longitud']);
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  LatLng? _pointFromMap(Map<String, dynamic> location) {
    final latitude = readDouble(location['latitud']);
    final longitude = readDouble(location['longitud']);
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  bool _samePoint(LatLng first, LatLng second) =>
      _sameRoutePoint(first, second);

  Future<void> _selectRoutePoints() async {
    final points = await showDialog<List<LatLng>>(
      context: context,
      builder: (context) => _RoutePointPickerDialog(
        origin: _originPoint,
        destination: _destinationPoint,
        initialCenter:
            _originPoint ??
            _destinationPoint ??
            _pointFromMap(widget.locations.firstOrNull ?? const {}) ??
            const LatLng(13.6929, -89.2182),
      ),
    );
    if (points == null || !mounted) return;
    final origin = points[0];
    final destination = points[1];
    setState(() {
      _originPoint = origin;
      _destinationPoint = destination;
      _originId = _findLocationId(origin);
      _destinationId = _findLocationId(destination);
      _polyline = null;
      _distance.clear();
      _arrival = null;
      _error = null;
    });
    _arrivalFieldKey.currentState?.didChange(null);
  }

  int? _findLocationId(LatLng point) {
    final location = widget.locations.where((item) {
      final savedPoint = _pointFromMap(item);
      return savedPoint != null && _samePoint(savedPoint, point);
    }).firstOrNull;
    return location == null ? null : readInt(location['id_ubicacion']);
  }

  Future<int> _saveLocation(LatLng point, int? selectedId) async {
    if (selectedId != null) return selectedId;
    final matchingId = _findLocationId(point);
    if (matchingId != null) return matchingId;

    final latitude = point.latitude.toStringAsFixed(6);
    final longitude = point.longitude.toStringAsFixed(6);
    final response = await widget.api.post('viajes/ubicaciones/', {
      'nombre': 'Punto $latitude, $longitude',
      'departamento': 'Mapa',
      'direccion': 'Punto seleccionado en el mapa',
      'latitud': latitude,
      'longitud': longitude,
      'activo': true,
    });
    if (response is! Map<String, dynamic>) {
      throw const ApiException(
        'La API no devolvió la ubicación seleccionada en el mapa.',
      );
    }
    final id = readInt(response['id_ubicacion']);
    if (id <= 0) {
      throw const ApiException(
        'La API no devolvió un identificador válido para la ubicación.',
      );
    }
    return id;
  }

  String _formatDateTime(DateTime value) =>
      '${formatDate(value.toIso8601String())} · '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _correlativo.dispose();
    _distance.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _requiredPositive(String? value) {
    final input = (value ?? '').trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) {
      return 'La distancia debe tener hasta dos decimales.';
    }
    final number = double.tryParse(input);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Ingresa una distancia mayor que cero.';
    }
    if (number > 999999.99) {
      return 'La distancia supera el máximo permitido.';
    }
    return null;
  }

  String? _validateCorrelativo(String? value) {
    final correlativo = (value ?? '').trim();
    if (correlativo.isEmpty) return 'El correlativo es obligatorio.';
    if (correlativo.length > 20) return 'Máximo 20 caracteres.';
    final currentId = widget.trip?['id_viaje']?.toString();
    final duplicate = widget.existingTrips.any(
      (trip) =>
          trip['id_viaje']?.toString() != currentId &&
          trip['correlativo']?.toString().trim().toLowerCase() ==
              correlativo.toLowerCase(),
    );
    return duplicate ? 'Este correlativo ya está registrado.' : null;
  }

  Future<void> _pickDateTime({
    required bool departure,
    required FormFieldState<DateTime> field,
  }) async {
    final current = departure
        ? (_departure ?? DateTime.now().add(const Duration(hours: 1)))
        : (_arrival ??
              (_departure ?? DateTime.now()).add(const Duration(hours: 2)));
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (departure) {
        _departure = selected;
        if (_routeDurationSeconds != null) {
          _arrival = selected.add(Duration(seconds: _routeDurationSeconds!));
        }
      } else {
        _arrival = selected;
        if (_departure != null) {
          _routeDurationSeconds = selected.difference(_departure!).inSeconds;
        }
      }
    });
    field.didChange(selected);
    if (departure && _arrival != null) {
      _arrivalFieldKey.currentState?.didChange(_arrival);
    }
  }

  Future<void> _calculateRoute() async {
    final origin = _originPoint ?? _pointForLocation(_originId);
    final destination = _destinationPoint ?? _pointForLocation(_destinationId);
    if (origin == null ||
        destination == null ||
        _samePoint(origin, destination)) {
      setState(() => _error = 'Selecciona un origen y destino distintos.');
      return;
    }

    setState(() {
      _routeLoading = true;
      _error = null;
    });
    try {
      final coordinates =
          '${origin.longitude.toStringAsFixed(6)},${origin.latitude.toStringAsFixed(6)};'
          '${destination.longitude.toStringAsFixed(6)},${destination.latitude.toStringAsFixed(6)}';
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/$coordinates',
        {'overview': 'full', 'geometries': 'polyline'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ApiException(
          'El servicio de rutas no respondió correctamente.',
        );
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body['code'] != 'Ok' ||
          body['routes'] is! List ||
          (body['routes'] as List).isEmpty) {
        throw const ApiException(
          'No se encontró una ruta vial entre las ubicaciones.',
        );
      }
      final route = (body['routes'] as List).first;
      if (route is! Map<String, dynamic> ||
          route['geometry'] is! String ||
          route['distance'] is! num ||
          route['duration'] is! num) {
        throw const ApiException(
          'El servicio de rutas devolvió datos incompletos.',
        );
      }
      final distanceKm = (route['distance'] as num) / 1000;
      final durationSeconds = (route['duration'] as num).round();
      _decodeRoutePolyline(route['geometry'] as String);
      if (!distanceKm.isFinite || distanceKm <= 0 || durationSeconds <= 0) {
        throw const ApiException(
          'El servicio de rutas devolvió una distancia inválida.',
        );
      }
      if (!mounted) return;
      setState(() {
        _polyline = route['geometry'] as String;
        _distance.text = distanceKm.toStringAsFixed(2);
        _routeDurationSeconds = durationSeconds;
        _departure ??= DateTime.now().add(const Duration(hours: 1));
        _arrival = _departure!.add(Duration(seconds: durationSeconds));
        _routeLoading = false;
      });
      _departureFieldKey.currentState?.didChange(_departure);
      _arrivalFieldKey.currentState?.didChange(_arrival);
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'El cálculo de ruta tardó demasiado. Intenta de nuevo.';
          _routeLoading = false;
        });
      }
    } on http.ClientException {
      if (mounted) {
        setState(() {
          _error = 'No se pudo conectar con el servicio de rutas.';
          _routeLoading = false;
        });
      }
    } on FormatException {
      if (mounted) {
        setState(() {
          _error = 'El servicio de rutas devolvió una respuesta inválida.';
          _routeLoading = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _routeLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final origin = _originPoint ?? _pointForLocation(_originId);
    final destination = _destinationPoint ?? _pointForLocation(_destinationId);
    if (origin == null || destination == null) {
      setState(() => _error = 'Selecciona el origen y destino en el mapa.');
      return;
    }
    if (_samePoint(origin, destination)) {
      setState(() => _error = 'El origen y destino deben ser distintos.');
      return;
    }
    if (_departure == null || _arrival == null) {
      setState(
        () => _error =
            'Selecciona la salida y calcula la ruta para definir la llegada estimada.',
      );
      return;
    }
    if (_arrival!.isBefore(_departure!)) {
      setState(
        () => _error = 'La llegada estimada debe ser posterior a la salida.',
      );
      return;
    }
    if (_polyline == null || _polyline!.isEmpty) {
      setState(
        () => _error = 'Calcula una ruta vial antes de guardar el viaje.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final originId = await _saveLocation(origin, _originId);
      final destinationId = await _saveLocation(destination, _destinationId);
      final body = <String, dynamic>{
        'correlativo': _correlativo.text.trim(),
        'id_unidad': _unitId,
        'id_conductor': widget.units
            .where((unit) => readInt(unit['id_unidad']) == _unitId)
            .firstOrNull?['id_conductor'],
        'id_origen': originId,
        'id_destino': destinationId,
        'id_cliente': _clientId,
        'distancia_km': _distance.text.trim(),
        'polyline_ruta': _polyline,
        'fecha_programada': _departure!.toIso8601String(),
        'fecha_llegada_est': _arrival!.toIso8601String(),
        'observaciones': _notes.text.trim(),
      };
      if (widget.trip == null) {
        await widget.api.post('viajes/viajes/', body);
      } else {
        await widget.api.patch(
          'viajes/viajes/${widget.trip!['id_viaje']}/',
          body,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.trip == null ? 'Programar viaje' : 'Editar viaje'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _correlativo,
                decoration: const InputDecoration(labelText: 'Correlativo *'),
                maxLength: 20,
                validator: _validateCorrelativo,
              ),
              const SizedBox(height: 12),
              _TripDropdown(
                label: 'Unidad *',
                value: _unitId,
                items: widget.units,
                idKey: 'id_unidad',
                title: (unit) =>
                    '${unit['placa']} · ${unit['conductor_nombre'] ?? 'Conductor asignado'}',
                onChanged: (value) => setState(() => _unitId = value),
                validator: (value) =>
                    value == null ? 'Selecciona una unidad disponible.' : null,
              ),
              const SizedBox(height: 12),
              _TripDropdown(
                label: 'Origen guardado',
                value: _originId,
                items: widget.locations,
                idKey: 'id_ubicacion',
                title: (location) =>
                    '${location['nombre']}${location['departamento'] == null || location['departamento'] == '' ? '' : ', ${location['departamento']}'}',
                onChanged: (value) {
                  setState(() {
                    _originId = value;
                    _originPoint = _pointForLocation(value);
                    _polyline = null;
                    _distance.clear();
                    _arrival = null;
                  });
                  _arrivalFieldKey.currentState?.didChange(null);
                },
                validator: (_) {
                  if (_originPoint == null) return 'Selecciona el origen.';
                  if (_destinationPoint != null &&
                      _samePoint(_originPoint!, _destinationPoint!)) {
                    return 'El origen y el destino no pueden ser iguales.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _TripDropdown(
                label: 'Destino guardado',
                value: _destinationId,
                items: widget.locations,
                idKey: 'id_ubicacion',
                title: (location) =>
                    '${location['nombre']}${location['departamento'] == null || location['departamento'] == '' ? '' : ', ${location['departamento']}'}',
                onChanged: (value) {
                  setState(() {
                    _destinationId = value;
                    _destinationPoint = _pointForLocation(value);
                    _polyline = null;
                    _distance.clear();
                    _arrival = null;
                  });
                  _arrivalFieldKey.currentState?.didChange(null);
                },
                validator: (_) {
                  if (_destinationPoint == null) {
                    return 'Selecciona el destino.';
                  }
                  if (_originPoint != null &&
                      _samePoint(_originPoint!, _destinationPoint!)) {
                    return 'El origen y el destino no pueden ser iguales.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving || _routeLoading
                      ? null
                      : _selectRoutePoints,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Elegir puntos exactos en el mapa'),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: Text(
                  'Origen: ${_formatRoutePoint(_originPoint)}',
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Destino: ${_formatRoutePoint(_destinationPoint)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: _clientId,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Sin cliente'),
                  ),
                  ...widget.clients.map(
                    (client) => DropdownMenuItem<int?>(
                      value: readInt(client['id_cliente']),
                      child: Text(client['nombre']?.toString() ?? 'Cliente'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _clientId = value),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Planificación',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              FormField<DateTime>(
                key: _departureFieldKey,
                initialValue: _departure,
                validator: (value) => value == null
                    ? 'La fecha programada de salida es obligatoria.'
                    : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving || _routeLoading
                          ? null
                          : () => _pickDateTime(departure: true, field: field),
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        _departure == null
                            ? 'Elegir fecha de salida *'
                            : 'Salida: ${_formatDateTime(_departure!)}',
                      ),
                    ),
                    if (field.hasError)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              FormField<DateTime>(
                key: _arrivalFieldKey,
                initialValue: _arrival,
                validator: (value) {
                  if (value == null) {
                    return 'Calcula una ruta vial para definir la llegada estimada.';
                  }
                  if (_departure != null && value.isBefore(_departure!)) {
                    return 'La llegada estimada no puede ser anterior a la salida.';
                  }
                  return null;
                },
                builder: (field) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _arrival == null
                              ? 'Llegada estimada: sin calcular'
                              : 'Llegada estimada: ${_formatDateTime(_arrival!)}',
                        ),
                      ),
                      if (field.hasError)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 4),
                          child: Text(
                            field.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _saving || _routeLoading ? null : _calculateRoute,
                  icon: _routeLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.alt_route),
                  label: Text(
                    _routeLoading
                        ? 'Calculando…'
                        : 'Calcular ruta vial y llegada',
                  ),
                ),
              ),
              if (_polyline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF16805D),
                      size: 18,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${_distance.text} km · Llegada estimada ${_arrival == null ? '' : formatDate(_arrival!.toIso8601String())}',
                        style: const TextStyle(color: Color(0xFF16805D)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 190,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _TripRouteMap(
                      points: _decodeRoutePolyline(_polyline!),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _distance,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Distancia de ruta (km) *',
                  helperText: 'Se completa al calcular una ruta vial.',
                ),
                validator: _requiredPositive,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Observaciones'),
              ),
              if (_error != null) ErrorBanner(message: _error!),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving || _routeLoading
            ? null
            : () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _saving || _routeLoading ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Guardar viaje'),
      ),
    ],
  );
}

class _TripDropdown extends StatelessWidget {
  const _TripDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.idKey,
    required this.title,
    required this.onChanged,
    required this.validator,
  });

  final String label;
  final int? value;
  final List<Map<String, dynamic>> items;
  final String idKey;
  final String Function(Map<String, dynamic>) title;
  final ValueChanged<int?> onChanged;
  final FormFieldValidator<int?> validator;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: items
        .map(
          (item) => DropdownMenuItem<int>(
            value: readInt(item[idKey]),
            child: Text(title(item), overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: onChanged,
    validator: validator,
  );
}

List<LatLng> _decodeRoutePolyline(String encoded) {
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  int readCoordinate() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (index >= encoded.length) {
        throw const FormatException('Ruta incompleta.');
      }
      final byte = encoded.codeUnitAt(index++) - 63;
      if (byte < 0 || byte > 63) {
        throw const FormatException('Ruta inválida.');
      }
      result |= (byte & 0x1f) << shift;
      shift += 5;
      if (shift > 30) throw const FormatException('Ruta inválida.');
      if (byte < 0x20) break;
    }
    return result.isOdd ? ~(result >> 1) : result >> 1;
  }

  final points = <LatLng>[];
  while (index < encoded.length) {
    latitude += readCoordinate();
    longitude += readCoordinate();
    if (latitude.abs() > 9000000 || longitude.abs() > 18000000) {
      throw const FormatException('Coordenadas fuera del mapa.');
    }
    points.add(LatLng(latitude / 100000, longitude / 100000));
  }
  if (points.length < 2) {
    throw const FormatException('La ruta necesita al menos dos puntos.');
  }
  return points;
}

class _TripRouteMap extends StatelessWidget {
  const _TripRouteMap({required this.points, this.progress});

  final List<LatLng> points;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final movingPoint = progress == null
        ? null
        : _pointAlongRoute(points, progress!);
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(36),
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.sistemaflota.sistema_flota',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: const Color(0xFF087E8B),
              strokeWidth: 5,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: points.first,
              width: 36,
              height: 36,
              child: const Icon(
                Icons.trip_origin,
                color: Color(0xFF16805D),
                size: 30,
              ),
            ),
            Marker(
              point: points.last,
              width: 36,
              height: 36,
              child: const Icon(
                Icons.location_on,
                color: Color(0xFFB42318),
                size: 34,
              ),
            ),
            if (movingPoint != null)
              Marker(
                point: movingPoint,
                width: 42,
                height: 42,
                child: const Icon(
                  Icons.local_shipping,
                  color: Color(0xFF13243A),
                  size: 32,
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}

class _RoutePointPickerDialog extends StatefulWidget {
  const _RoutePointPickerDialog({
    required this.origin,
    required this.destination,
    required this.initialCenter,
  });

  final LatLng? origin;
  final LatLng? destination;
  final LatLng initialCenter;

  @override
  State<_RoutePointPickerDialog> createState() =>
      _RoutePointPickerDialogState();
}

class _RoutePointPickerDialogState extends State<_RoutePointPickerDialog> {
  late LatLng? _origin = widget.origin;
  late LatLng? _destination = widget.destination;
  late bool _selectingOrigin =
      widget.origin == null || widget.destination != null;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Elegir inicio y destino'),
        actions: [
          IconButton(
            tooltip: 'Cerrar mapa',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.trip_origin),
                    label: Text('Inicio'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.location_on_outlined),
                    label: Text('Destino'),
                  ),
                ],
                selected: {_selectingOrigin},
                onSelectionChanged: (selection) =>
                    setState(() => _selectingOrigin = selection.first),
              ),
              const SizedBox(height: 8),
              Text(
                _selectingOrigin
                    ? 'Paso 1 de 2: toca el mapa para marcar el inicio.'
                    : 'Paso 2 de 2: toca el mapa para marcar el destino.',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Inicio: ${_formatRoutePoint(_origin)}\n'
                'Destino: ${_formatRoutePoint(_destination)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: widget.initialCenter,
                      initialZoom: 13,
                      onTap: (_, point) {
                        setState(() {
                          if (_selectingOrigin) {
                            _origin = point;
                            _selectingOrigin = false;
                          } else {
                            _destination = point;
                          }
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.sistemaflota.sistema_flota',
                      ),
                      MarkerLayer(
                        markers: [
                          if (_origin != null)
                            Marker(
                              point: _origin!,
                              width: 76,
                              height: 62,
                              child: const _RoutePointMarker(
                                label: 'INICIO',
                                icon: Icons.trip_origin,
                                color: Color(0xFF16805D),
                              ),
                            ),
                          if (_destination != null)
                            Marker(
                              point: _destination!,
                              width: 84,
                              height: 66,
                              child: const _RoutePointMarker(
                                label: 'DESTINO',
                                icon: Icons.location_on,
                                color: Color(0xFFB42318),
                              ),
                            ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    _origin == null ||
                        _destination == null ||
                        _sameRoutePoint(_origin!, _destination!)
                    ? null
                    : () => Navigator.pop(context, [_origin!, _destination!]),
                icon: const Icon(Icons.check),
                label: const Text('Usar ruta'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RoutePointMarker extends StatelessWidget {
  const _RoutePointMarker({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      Icon(icon, color: color, size: 30),
    ],
  );
}

class _TripRouteDialog extends StatefulWidget {
  const _TripRouteDialog({required this.trip, required this.points});

  final Map<String, dynamic> trip;
  final List<LatLng> points;

  @override
  State<_TripRouteDialog> createState() => _TripRouteDialogState();
}

class _TripRouteDialogState extends State<_TripRouteDialog> {
  Timer? _progressTimer;
  double _progress = 0;

  bool get _isActiveSimulation =>
      readBool(widget.trip['es_simulado']) &&
      readInt(widget.trip['id_estado_viaje']) == 2;

  @override
  void initState() {
    super.initState();
    if (_isActiveSimulation) {
      _updateProgress();
      _progressTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _updateProgress(),
      );
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _updateProgress() {
    final departure = DateTime.tryParse(
      widget.trip['fecha_salida']?.toString() ?? '',
    );
    final arrival = DateTime.tryParse(
      widget.trip['fecha_llegada_est']?.toString() ?? '',
    );
    if (departure == null || arrival == null || !arrival.isAfter(departure)) {
      return;
    }
    final duration = arrival.difference(departure).inMilliseconds;
    final elapsed = DateTime.now().difference(departure).inMilliseconds;
    final progress = (elapsed / duration).clamp(0.0, 1.0).toDouble();
    if (mounted) setState(() => _progress = progress);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 620,
      height: 520,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ruta ${widget.trip['correlativo'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar mapa',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              '${widget.trip['origen_nombre'] ?? 'Origen'} → '
              '${widget.trip['destino_nombre'] ?? 'Destino'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.trip['distancia_km'] ?? '—'} km · '
              '${readBool(widget.trip['es_simulado']) ? 'Simulación de recorrido' : 'Ruta vial'}',
              style: TextStyle(color: Colors.blueGrey.shade700),
            ),
            if (_isActiveSimulation) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Text('Avance simulado: ${(_progress * 100).round()}%'),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _TripRouteMap(
                  points: widget.points,
                  progress: _isActiveSimulation ? _progress : null,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

LatLng _pointAlongRoute(List<LatLng> points, double progress) {
  final segmentLengths = <double>[];
  var totalLength = 0.0;
  for (var index = 0; index < points.length - 1; index++) {
    final length = _distanceBetween(points[index], points[index + 1]);
    segmentLengths.add(length);
    totalLength += length;
  }
  if (totalLength == 0) return points.first;

  var remaining = totalLength * progress.clamp(0.0, 1.0);
  for (var index = 0; index < segmentLengths.length; index++) {
    final segmentLength = segmentLengths[index];
    if (remaining <= segmentLength || index == segmentLengths.length - 1) {
      final fraction = segmentLength == 0 ? 0.0 : remaining / segmentLength;
      final start = points[index];
      final end = points[index + 1];
      return LatLng(
        start.latitude + (end.latitude - start.latitude) * fraction,
        start.longitude + (end.longitude - start.longitude) * fraction,
      );
    }
    remaining -= segmentLength;
  }
  return points.last;
}

double _distanceBetween(LatLng start, LatLng end) {
  const earthRadiusMeters = 6371000.0;
  final startLatitude = start.latitude * math.pi / 180;
  final endLatitude = end.latitude * math.pi / 180;
  final latitudeDelta = (end.latitude - start.latitude) * math.pi / 180;
  final longitudeDelta = (end.longitude - start.longitude) * math.pi / 180;
  final halfChord =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(startLatitude) *
          math.cos(endLatitude) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(halfChord)));
}
