import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'common_widgets.dart';

class OperacionesScreen extends StatefulWidget {
  const OperacionesScreen({required this.api, this.isActive = true, super.key});

  final ApiService api;
  final bool isActive;

  @override
  State<OperacionesScreen> createState() => _OperacionesScreenState();
}

class _OperacionesScreenState extends State<OperacionesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _units = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OperacionesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<List<Map<String, dynamic>>>([
        widget.api.getList('viajes/tipos-carga/'),
        widget.api.getList('viajes/clientes/'),
        widget.api.getList('viajes/viajes/'),
        widget.api.getList('unidades/unidades/'),
      ]);
      if (!mounted) return;
      setState(() {
        _types = values[0];
        _clients = values[1];
        _trips = values[2];
        _units = values[3];
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

  void _showSaved(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _types.isEmpty && _trips.isEmpty) {
      return const LoadingView();
    }
    if (_error != null && _types.isEmpty && _trips.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Registrar cargas y movimientos de viaje.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar datos',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Cargas'),
              Tab(icon: Icon(Icons.swap_horiz), text: 'Salidas y entradas'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RegisterLoadForm(
                  api: widget.api,
                  types: _types,
                  clients: _clients,
                  trips: _trips,
                  units: _units,
                  onSaved: () => _showSaved('Carga registrada correctamente.'),
                ),
                _RegisterMovementForm(
                  api: widget.api,
                  trips: _trips,
                  units: _units,
                  onSaved: () =>
                      _showSaved('Movimiento registrado correctamente.'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterLoadForm extends StatefulWidget {
  const _RegisterLoadForm({
    required this.api,
    required this.types,
    required this.clients,
    required this.trips,
    required this.units,
    required this.onSaved,
  });

  final ApiService api;
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> units;
  final VoidCallback onSaved;

  @override
  State<_RegisterLoadForm> createState() => _RegisterLoadFormState();
}

class _RegisterLoadFormState extends State<_RegisterLoadForm> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _quantity = TextEditingController();
  final _unit = TextEditingController();
  final _weight = TextEditingController();
  final _document = TextEditingController();
  int? _typeId;
  int? _clientId;
  int? _tripId;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _selectedTrip => widget.trips
      .where((trip) => readInt(trip['id_viaje']) == _tripId)
      .firstOrNull;

  Map<String, dynamic>? get _selectedType => widget.types
      .where((type) => readInt(type['id_tipo_carga']) == _typeId)
      .firstOrNull;

  Map<String, dynamic>? get _selectedUnit {
    final unitId = _selectedTrip?['id_unidad'];
    return widget.units
        .where((unit) => unit['id_unidad']?.toString() == unitId?.toString())
        .firstOrNull;
  }

  String? _tripLoadValidationError() {
    final trip = _selectedTrip;
    if (trip == null) return null;

    final type = _selectedType;
    final unit = _selectedUnit;
    if (type == null || unit == null) {
      return 'No se pudieron verificar el tipo de carga y la unidad del viaje.';
    }

    final loadTypeName = _normalizeCompatibilityName(
      type['nombre']?.toString() ?? '',
    );
    final unitTypeName = _normalizeCompatibilityName(
      unit['tipo_nombre']?.toString() ?? '',
    );
    final isLiquidCargo =
        loadTypeName.contains('liquid') || loadTypeName.contains('combustible');
    final isTankTruck = unitTypeName.contains('cisterna');
    if (isLiquidCargo && !isTankTruck) {
      return 'Las cargas líquidas solo se pueden transportar en una cisterna.';
    }
    if (isTankTruck && !isLiquidCargo) {
      return 'Las cisternas solo se pueden asignar a cargas líquidas.';
    }

    final compatibleTypes = _parseCompatibleUnitTypes(
      type['unidades_compatibles']?.toString(),
    );
    final unitTypeId = unit['id_tipo_unidad']?.toString().trim();
    if (compatibleTypes.isNotEmpty &&
        (unitTypeId == null || !compatibleTypes.contains(unitTypeId))) {
      return 'Este tipo de carga no es compatible con la unidad '
          '${unit['placa'] ?? 'seleccionada'} (${unit['tipo_nombre'] ?? 'tipo sin indicar'}).';
    }

    final loadClientId = _clientId?.toString();
    final tripClientId = trip['id_cliente']?.toString();
    if (loadClientId != null &&
        tripClientId != null &&
        loadClientId != tripClientId) {
      return 'El cliente de la carga debe coincidir con el cliente del viaje.';
    }

    final rawWeight = _weight.text.trim();
    final weight = double.tryParse(rawWeight);
    final capacity = readDouble(unit['capacidad_ton']);
    if (rawWeight.isNotEmpty &&
        weight != null &&
        capacity != null &&
        weight > capacity) {
      return 'El peso de la carga supera la capacidad de la unidad '
          '(${capacity.toStringAsFixed(2)} t).';
    }
    return null;
  }

  String _normalizeCompatibilityName(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  Set<String> _parseCompatibleUnitTypes(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet();
      }
    } on FormatException {
      // Compatibility values may also be stored as comma/semicolon-separated IDs.
    }
    return raw
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(';', ',')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _unit.dispose();
    _weight.dispose();
    _document.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final tripValidationError = _tripLoadValidationError();
    if (tripValidationError != null) {
      setState(() => _error = tripValidationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.post('viajes/cargas/', {
        'descripcion': _description.text.trim(),
        'id_tipo_carga': _typeId,
        'id_cliente': _clientId,
        'id_viaje': _tripId,
        'cantidad': int.parse(_quantity.text.trim()),
        'unidad_medida': _unit.text.trim(),
        'peso_ton': _weight.text.trim().isEmpty ? null : _weight.text.trim(),
        'documento_ref': _document.text.trim(),
      });
      if (!mounted) return;
      _formKey.currentState!.reset();
      _description.clear();
      _quantity.clear();
      _unit.clear();
      _weight.clear();
      _document.clear();
      setState(() {
        _typeId = null;
        _clientId = null;
        _tripId = null;
        _saving = false;
      });
      widget.onSaved();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _saving = false;
        });
      }
    } on FormatException {
      if (mounted) {
        setState(() {
          _error = 'La cantidad debe ser un número entero válido.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Registrar una carga',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Descripción de la carga *',
                  ),
                  maxLength: 200,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Describe la carga.'
                      : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _typeId,
                  decoration: const InputDecoration(labelText: 'Tipo *'),
                  items: widget.types
                      .map(
                        (type) => DropdownMenuItem(
                          value: readInt(type['id_tipo_carga']),
                          child: Text(type['nombre']?.toString() ?? 'Tipo'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _typeId = value;
                    _error = null;
                  }),
                  validator: (value) =>
                      value == null ? 'Selecciona el tipo de carga.' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad *',
                        ),
                        validator: (value) {
                          final quantity = int.tryParse(value?.trim() ?? '');
                          return quantity == null ||
                                  quantity <= 0 ||
                                  quantity > 2147483647
                              ? 'Ingresa una cantidad positiva.'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        decoration: const InputDecoration(
                          labelText: 'Unidad de medida *',
                        ),
                        maxLength: 20,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Indica la unidad.'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Peso total en toneladas (opcional)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final input = value.trim();
                    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) {
                      return 'Usa un peso válido con máximo dos decimales.';
                    }
                    final weight = double.tryParse(input);
                    return weight == null ||
                            !weight.isFinite ||
                            weight <= 0 ||
                            weight > 99999999.99
                        ? 'Ingresa un peso válido.'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _clientId,
                  decoration: const InputDecoration(
                    labelText: 'Cliente (opcional)',
                  ),
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
                  onChanged: (value) => setState(() {
                    _clientId = value;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _tripId,
                  decoration: const InputDecoration(
                    labelText: 'Viaje (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Sin asignar'),
                    ),
                    ...widget.trips
                        .where((trip) => readInt(trip['id_estado_viaje']) == 1)
                        .map(
                          (trip) => DropdownMenuItem<int?>(
                            value: readInt(trip['id_viaje']),
                            child: Text(
                              '${trip['correlativo'] ?? 'Viaje'} · ${trip['unidad_placa'] ?? 'Unidad'}',
                            ),
                          ),
                        ),
                  ],
                  onChanged: (value) => setState(() {
                    _tripId = value;
                    _error = null;
                  }),
                ),
                if (_tripId != null &&
                    _typeId != null &&
                    _tripLoadValidationError() != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _tripLoadValidationError()!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: _document,
                  decoration: const InputDecoration(
                    labelText: 'Documento de referencia (opcional)',
                  ),
                  maxLength: 100,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar carga'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _RegisterMovementForm extends StatefulWidget {
  const _RegisterMovementForm({
    required this.api,
    required this.trips,
    required this.units,
    required this.onSaved,
  });

  final ApiService api;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> units;
  final VoidCallback onSaved;

  @override
  State<_RegisterMovementForm> createState() => _RegisterMovementFormState();
}

class _RegisterMovementFormState extends State<_RegisterMovementForm> {
  final _formKey = GlobalKey<FormState>();
  final _correlativo = TextEditingController();
  final _correlativoFocus = FocusNode();
  final _odometer = TextEditingController();
  final _fuel = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'SALIDA';
  int? _selectedTripId;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> get _availableTrips => widget.trips.where((trip) {
    final status = readInt(trip['id_estado_viaje']);
    return !readBool(trip['es_simulado']) &&
        (_type == 'SALIDA' ? status == 1 : status == 2);
  }).toList();

  Map<String, dynamic>? get _selectedTrip => _availableTrips
      .where((trip) => readInt(trip['id_viaje']) == _selectedTripId)
      .firstOrNull;

  Map<String, dynamic>? _unitForTrip(Map<String, dynamic> trip) => widget.units
      .where((unit) => readInt(unit['id_unidad']) == readInt(trip['id_unidad']))
      .firstOrNull;

  void _prefillUnitReadings(Map<String, dynamic> trip) {
    final unit = _unitForTrip(trip);
    _odometer.text = unit?['odometro_actual']?.toString() ?? '';
    _fuel.text = unit?['combustible_actual_gal']?.toString() ?? '';
  }

  @override
  void dispose() {
    _correlativo.dispose();
    _correlativoFocus.dispose();
    _odometer.dispose();
    _fuel.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final trip = _selectedTrip;
    if (trip == null) {
      setState(() => _error = 'Ingresa el correlativo de un viaje disponible.');
      return;
    }
    final locationId = readInt(
      trip[_type == 'SALIDA' ? 'id_origen' : 'id_destino'],
    );
    if (locationId <= 0) {
      setState(() => _error = 'El viaje no tiene un punto de ruta registrado.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.post('viajes/movimientos/', {
        'id_viaje': readInt(trip['id_viaje']),
        'id_unidad': readInt(trip['id_unidad']),
        'id_ubicacion': locationId,
        'tipo': _type,
        'odometro_km': int.parse(_odometer.text.trim()),
        'combustible_gal': _fuel.text.trim(),
        'observacion': _notes.text.trim(),
      });
      if (!mounted) return;
      _formKey.currentState!.reset();
      _correlativo.clear();
      _odometer.clear();
      _fuel.clear();
      _notes.clear();
      setState(() {
        _selectedTripId = null;
        _saving = false;
      });
      widget.onSaved();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _saving = false;
        });
      }
    } on FormatException {
      if (mounted) {
        setState(() {
          _error = 'Verifica que el odómetro sea un número entero.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Registrar salida o llegada',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'SALIDA',
                      icon: Icon(Icons.play_arrow),
                      label: Text('Salida'),
                    ),
                    ButtonSegment(
                      value: 'ENTRADA',
                      icon: Icon(Icons.flag_outlined),
                      label: Text('Entrada'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (selection) => setState(() {
                    _type = selection.first;
                    _selectedTripId = null;
                    _correlativo.clear();
                    _odometer.clear();
                    _fuel.clear();
                    _error = null;
                  }),
                ),
                const SizedBox(height: 12),
                RawAutocomplete<Map<String, dynamic>>(
                  textEditingController: _correlativo,
                  focusNode: _correlativoFocus,
                  displayStringForOption: (trip) =>
                      trip['correlativo']?.toString() ?? '',
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) return const [];
                    return _availableTrips.where(
                      (trip) => (trip['correlativo']?.toString() ?? '')
                          .toLowerCase()
                          .contains(query),
                    );
                  },
                  onSelected: (trip) => setState(() {
                    _selectedTripId = readInt(trip['id_viaje']);
                    _prefillUnitReadings(trip);
                    _error = null;
                  }),
                  fieldViewBuilder:
                      (
                        context,
                        controller,
                        focusNode,
                        onFieldSubmitted,
                      ) => TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Buscar correlativo del viaje *',
                          hintText: 'Ej. V-005',
                          helperText: _type == 'SALIDA'
                              ? 'Busca entre los viajes programados.'
                              : 'Busca entre los viajes en curso.',
                        ),
                        onChanged: (_) => setState(() {
                          _selectedTripId = null;
                          _odometer.clear();
                          _fuel.clear();
                          _error = null;
                        }),
                        onFieldSubmitted: (_) => onFieldSubmitted(),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa el correlativo del viaje.';
                          }
                          return _selectedTrip == null
                              ? _type == 'SALIDA'
                                    ? 'Selecciona un viaje programado de la lista.'
                                    : 'Selecciona un viaje en curso de la lista.'
                              : null;
                        },
                      ),
                  optionsViewBuilder: (context, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          children: options
                              .map(
                                (trip) => ListTile(
                                  title: Text(
                                    trip['correlativo']?.toString() ?? 'Viaje',
                                  ),
                                  subtitle: Text(
                                    '${trip['unidad_placa'] ?? 'Unidad'} · '
                                    '${trip['origen_nombre'] ?? 'Origen'} → '
                                    '${trip['destino_nombre'] ?? 'Destino'}',
                                  ),
                                  onTap: () => onSelected(trip),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_selectedTrip != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Unidad: ${_selectedTrip!['unidad_placa'] ?? '—'} · '
                    'Conductor: ${_selectedTrip!['conductor_nombre'] ?? '—'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ruta: ${_selectedTrip!['origen_nombre'] ?? 'Origen'} → '
                    '${_selectedTrip!['destino_nombre'] ?? 'Destino'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    _type == 'SALIDA'
                        ? 'Se registrará en: ${_selectedTrip!['origen_nombre'] ?? 'Origen del viaje'}'
                        : 'Se registrará en: ${_selectedTrip!['destino_nombre'] ?? 'Destino del viaje'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _odometer,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Odómetro (km) *',
                    helperText: 'Se carga la última lectura de la unidad.',
                  ),
                  validator: (value) {
                    final number = int.tryParse(value?.trim() ?? '');
                    return number == null || number < 0
                        ? 'Ingresa una lectura de odómetro válida.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fuel,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Combustible en el tanque (gal) *',
                    helperText: 'Se carga la última lectura de la unidad.',
                  ),
                  validator: (value) {
                    final number = double.tryParse(value?.trim() ?? '');
                    if (number == null || !number.isFinite || number < 0) {
                      return 'Ingresa una lectura de combustible válida.';
                    }
                    if (_type == 'SALIDA' && number <= 0) {
                      return 'La salida requiere combustible mayor que cero.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Observación (opcional)',
                  ),
                  maxLength: 255,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _type == 'SALIDA'
                        ? 'Registrar salida'
                        : 'Registrar entrada',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
