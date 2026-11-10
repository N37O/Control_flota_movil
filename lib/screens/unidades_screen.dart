import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'common_widgets.dart';

const double _estimatedKmPerGallon = 8;

class UnidadesScreen extends StatefulWidget {
  const UnidadesScreen({
    required this.api,
    required this.isAdmin,
    this.canRegister = false,
    super.key,
  });

  final ApiService api;
  final bool isAdmin;
  final bool canRegister;

  @override
  State<UnidadesScreen> createState() => _UnidadesScreenState();
}

class _UnidadesScreenState extends State<UnidadesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _states = [];
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _trips = [];
  late final Timer _refreshTimer;
  bool _refreshingFuelEstimates = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshFuelEstimates()),
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
        widget.api.getList('unidades/unidades/'),
        widget.api.getList('unidades/tipos/'),
        widget.api.getList('unidades/estados/'),
        widget.api.getList('unidades/conductores/'),
        widget.api.getList('viajes/viajes/'),
      ]);
      if (!mounted) return;
      setState(() {
        _units = data[0];
        _types = data[1];
        _states = data[2];
        _drivers = data[3];
        _trips = data[4];
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

  Future<void> _refreshFuelEstimates() async {
    if (!mounted || _loading || _refreshingFuelEstimates) return;
    _refreshingFuelEstimates = true;
    try {
      final values = await Future.wait<List<Map<String, dynamic>>>([
        widget.api.getList('unidades/unidades/'),
        widget.api.getList('viajes/viajes/'),
      ]);
      if (mounted) {
        setState(() {
          _units = values[0];
          _trips = values[1];
          _error = null;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _refreshingFuelEstimates = false;
    }
  }

  Future<void> _edit([Map<String, dynamic>? unit]) async {
    if (unit == null
        ? !(widget.isAdmin || widget.canRegister)
        : !widget.isAdmin) {
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _UnitFormDialog(
        api: widget.api,
        unit: unit,
        units: _units,
        types: _types,
        states: _states,
        drivers: _availableDrivers(unit),
      ),
    );
    if (result == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              unit == null ? 'Unidad creada.' : 'Unidad actualizada.',
            ),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _availableDrivers(Map<String, dynamic>? unit) {
    final assignedElsewhere = _units
        .where((item) => item['id_unidad'] != unit?['id_unidad'])
        .map((item) => item['id_conductor']?.toString())
        .whereType<String>()
        .toSet();
    return _drivers.where((driver) {
      final isCurrentDriver = driver['id_conductor'] == unit?['id_conductor'];
      return (readBool(driver['activo'], fallback: true) || isCurrentDriver) &&
          (!assignedElsewhere.contains(driver['id_conductor'].toString()) ||
              isCurrentDriver);
    }).toList();
  }

  Future<void> _delete(Map<String, dynamic> unit) async {
    if (!widget.isAdmin) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar unidad'),
        content: Text(
          '¿Eliminar la unidad ${unit['placa']}? Si tiene viajes u otros registros asociados, la API puede impedirlo.',
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
      await widget.api.delete('unidades/unidades/${unit['id_unidad']}/');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unidad eliminada.')));
      }
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> unit) async {
    if (!widget.isAdmin) return;
    try {
      await widget.api.patch('unidades/unidades/${unit['id_unidad']}/', {
        'activo': !readBool(unit['activo'], fallback: true),
      });
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _registerRefuel() async {
    if (!widget.isAdmin && !widget.canRegister) return;
    final active = _units
        .where((unit) => readBool(unit['activo'], fallback: true))
        .toList();
    if (active.isEmpty) {
      _showError('No hay unidades activas para registrar una recarga.');
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _RefuelDialog(
        api: widget.api,
        units: active,
        trips: _trips
            .where(
              (trip) =>
                  [1, 2].contains(readInt(trip['id_estado_viaje'])) &&
                  active.any(
                    (unit) =>
                        unit['id_unidad'].toString() ==
                        trip['id_unidad']?.toString(),
                  ),
            )
            .toList(),
      ),
    );
    if (result == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recarga registrada correctamente.')),
        );
      }
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
    if (_loading && _units.isEmpty) return const LoadingView();
    if (_error != null && _units.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    final active = _units
        .where((unit) => readBool(unit['activo'], fallback: true))
        .length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.isAdmin || widget.canRegister
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva unidad'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$active activas · ${_units.length} en total',
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  ),
                ),
                if (widget.isAdmin || widget.canRegister)
                  FilledButton.tonalIcon(
                    onPressed: _registerRefuel,
                    icon: const Icon(
                      Icons.local_gas_station_outlined,
                      size: 19,
                    ),
                    label: const Text('Recarga'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_units.isEmpty)
              const EmptyView(message: 'No se encontraron unidades.')
            else
              ..._units.map(
                (unit) => _UnitCard(
                  unit: unit,
                  trips: _trips
                      .where(
                        (trip) =>
                            trip['id_unidad']?.toString() ==
                            unit['id_unidad']?.toString(),
                      )
                      .toList(),
                  isAdmin: widget.isAdmin,
                  onEdit: widget.isAdmin ? () => _edit(unit) : null,
                  onDelete: widget.isAdmin ? () => _delete(unit) : null,
                  onToggleActive: widget.isAdmin
                      ? () => _toggleActive(unit)
                      : null,
                ),
              ),
            if (_error != null) ErrorBanner(message: _error!),
          ],
        ),
      ),
    );
  }
}

double _estimatedFuelUsed(
  Map<String, dynamic> unit,
  List<Map<String, dynamic>> trips,
) {
  final recordedFuel = readDouble(unit['combustible_actual_gal']);
  final lastReading = DateTime.tryParse(
    unit['fecha_combustible_actual']?.toString() ?? '',
  );
  var used = 0.0;
  for (final trip in trips) {
    final status = readInt(trip['id_estado_viaje']);
    if (!readBool(trip['es_simulado']) || (status != 2 && status != 3)) {
      continue;
    }

    final startedAt = DateTime.tryParse(
      (trip['fecha_salida'] ?? trip['fecha_programada'])?.toString() ?? '',
    );
    if (startedAt == null ||
        (lastReading != null && startedAt.isBefore(lastReading))) {
      continue;
    }

    final distanceKm = readDouble(trip['distancia_km']);
    if (distanceKm == null || distanceKm <= 0) continue;
    final progress = status == 3
        ? 1.0
        : (readDouble(trip['progreso_simulado']) ?? 0).clamp(0.0, 1.0);
    used += distanceKm * progress / _estimatedKmPerGallon;
  }
  return recordedFuel == null ? used : used.clamp(0.0, recordedFuel).toDouble();
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.trips,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final Map<String, dynamic> unit;
  final List<Map<String, dynamic>> trips;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleActive;

  @override
  Widget build(BuildContext context) {
    final active = readBool(unit['activo'], fallback: true);
    final fuel = readDouble(unit['combustible_actual_gal']);
    final capacity = readDouble(unit['capacidad_tanque_gal']);
    final estimatedFuelUsed = _estimatedFuelUsed(unit, trips);
    final displayedFuel = fuel == null
        ? null
        : (fuel - estimatedFuelUsed).clamp(0.0, fuel).toDouble();
    final fuelRatio = displayedFuel != null && capacity != null && capacity > 0
        ? (displayedFuel / capacity).clamp(0, 1).toDouble()
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  color: Color(0xFF087E8B),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    unit['placa']?.toString() ?? 'Unidad',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                StatusChip(
                  label: active
                      ? (unit['estado_nombre']?.toString() ?? 'Activa')
                      : 'Inactiva',
                  color: active
                      ? const Color(0xFF16805D)
                      : const Color(0xFF6B7280),
                ),
                if (isAdmin)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit?.call();
                      if (value == 'toggle') onToggleActive?.call();
                      if (value == 'delete') onDelete?.call();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(active ? 'Desactivar' : 'Activar'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Eliminar'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              '${unit['tipo_nombre'] ?? 'Tipo sin indicar'} · Conductor: ${unit['conductor_nombre'] ?? 'Sin asignar'}',
              style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 12),
            ),
            Text(
              'Carga: ${unit['capacidad_ton'] ?? '—'} t · Tanque: ${unit['capacidad_tanque_gal'] ?? '—'} gal',
              style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 12),
            ),
            if (fuelRatio != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: fuelRatio,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      color: fuelRatio < .2
                          ? const Color(0xFFCA3D3D)
                          : const Color(0xFF087E8B),
                      backgroundColor: const Color(0xFFE8EDF3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${displayedFuel!.toStringAsFixed(1)} gal'),
                ],
              ),
            ],
            if (estimatedFuelUsed > 0) ...[
              const SizedBox(height: 5),
              Text(
                'Trayecto: ${estimatedFuelUsed.toStringAsFixed(1)} gal menos '
                '(estimado a $_estimatedKmPerGallon km/gal).',
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnitFormDialog extends StatefulWidget {
  const _UnitFormDialog({
    required this.api,
    required this.units,
    required this.types,
    required this.states,
    required this.drivers,
    this.unit,
  });

  final ApiService api;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> states;
  final List<Map<String, dynamic>> drivers;
  final Map<String, dynamic>? unit;

  @override
  State<_UnitFormDialog> createState() => _UnitFormDialogState();
}

class _UnitFormDialogState extends State<_UnitFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _plate = TextEditingController(
    text: widget.unit?['placa']?.toString(),
  );
  late final _code = TextEditingController(
    text: widget.unit?['codigo_interno']?.toString(),
  );
  late final _capacity = TextEditingController(
    text: widget.unit?['capacidad_ton']?.toString(),
  );
  late final _tank = TextEditingController(
    text: widget.unit?['capacidad_tanque_gal']?.toString(),
  );
  int? _typeId;
  int? _stateId;
  int? _driverId;
  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _typeId = _optionalInt(widget.unit?['id_tipo_unidad']);
    _stateId = _optionalInt(widget.unit?['id_estado_unidad']);
    _driverId = _optionalInt(widget.unit?['id_conductor']);
    _active = readBool(widget.unit?['activo'], fallback: true);
  }

  int? _optionalInt(dynamic value) =>
      value == null ? null : int.tryParse(value.toString());

  @override
  void dispose() {
    _plate.dispose();
    _code.dispose();
    _capacity.dispose();
    _tank.dispose();
    super.dispose();
  }

  String? _positiveNumber(String? value, {required double maximum}) {
    final input = (value ?? '').trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) {
      return 'Usa un número mayor que cero con hasta dos decimales.';
    }
    final number = double.tryParse(input);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Ingresa un número mayor que cero.';
    }
    if (number > maximum) return 'El valor máximo permitido es $maximum.';
    return null;
  }

  String? _validatePlate(String? value) {
    final plate = (value ?? '').trim().toUpperCase();
    if (plate.isEmpty) return 'La placa es obligatoria.';
    if (plate.length > 20) return 'La placa no puede superar 20 caracteres.';
    final currentId = widget.unit?['id_unidad']?.toString();
    final duplicate = widget.units.any(
      (unit) =>
          unit['id_unidad']?.toString() != currentId &&
          unit['placa']?.toString().trim().toUpperCase() == plate,
    );
    return duplicate ? 'Esta placa ya está registrada.' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'placa': _plate.text.trim().toUpperCase(),
      'codigo_interno': _code.text.trim(),
      'id_tipo_unidad': _typeId,
      'id_estado_unidad': _stateId,
      'id_conductor': _driverId,
      'capacidad_ton': _capacity.text.trim(),
      'capacidad_tanque_gal': _tank.text.trim(),
      'activo': _active,
    };
    try {
      if (widget.unit == null) {
        await widget.api.post('unidades/unidades/', body);
      } else {
        await widget.api.patch(
          'unidades/unidades/${widget.unit!['id_unidad']}/',
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
    title: Text(widget.unit == null ? 'Nueva unidad' : 'Editar unidad'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Placa *'),
                maxLength: 20,
                validator: _validatePlate,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Código interno *',
                ),
                maxLength: 50,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'El código interno es obligatorio.'
                    : null,
              ),
              const SizedBox(height: 12),
              _DropdownField(
                label: 'Tipo de unidad *',
                value: _typeId,
                items: widget.types,
                idKey: 'id_tipo_unidad',
                nameKey: 'nombre',
                onChanged: (value) => setState(() => _typeId = value),
                validator: (value) =>
                    value == null ? 'Selecciona un tipo de unidad.' : null,
              ),
              const SizedBox(height: 12),
              _DropdownField(
                label: 'Estado *',
                value: _stateId,
                items: widget.states,
                idKey: 'id_estado_unidad',
                nameKey: 'nombre',
                onChanged: (value) => setState(() => _stateId = value),
                validator: (value) =>
                    value == null ? 'Selecciona un estado.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _driverId,
                decoration: const InputDecoration(labelText: 'Conductor'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Sin asignar'),
                  ),
                  ...widget.drivers.map(
                    (driver) => DropdownMenuItem<int?>(
                      value: readInt(driver['id_conductor']),
                      child: Text(driver['nombre']?.toString() ?? 'Conductor'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _driverId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _capacity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Capacidad de carga (t) *',
                ),
                validator: (value) =>
                    _positiveNumber(value, maximum: 99999999.99),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tank,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Capacidad del tanque (gal) *',
                ),
                validator: (value) =>
                    _positiveNumber(value, maximum: 999999.99),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Unidad activa'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              if (_error != null) ErrorBanner(message: _error!),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Guardar'),
      ),
    ],
  );
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.idKey,
    required this.nameKey,
    required this.onChanged,
    required this.validator,
  });

  final String label;
  final int? value;
  final List<Map<String, dynamic>> items;
  final String idKey;
  final String nameKey;
  final ValueChanged<int?> onChanged;
  final FormFieldValidator<int?> validator;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: items
        .map(
          (item) => DropdownMenuItem<int>(
            value: readInt(item[idKey]),
            child: Text(item[nameKey]?.toString() ?? ''),
          ),
        )
        .toList(),
    onChanged: onChanged,
    validator: validator,
  );
}

class _RefuelDialog extends StatefulWidget {
  const _RefuelDialog({
    required this.api,
    required this.units,
    required this.trips,
  });

  final ApiService api;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> trips;

  @override
  State<_RefuelDialog> createState() => _RefuelDialogState();
}

class _RefuelDialogState extends State<_RefuelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _gallons = TextEditingController();
  final _tankLevel = TextEditingController();
  final _price = TextEditingController();
  final _place = TextEditingController();
  final _invoice = TextEditingController();
  int? _unitId;
  int? _tripId;
  DateTime _dateTime = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _gallons.dispose();
    _tankLevel.dispose();
    _price.dispose();
    _place.dispose();
    _invoice.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _selectedUnit => widget.units
      .where((unit) => readInt(unit['id_unidad']) == _unitId)
      .firstOrNull;

  double? get _tankCapacity =>
      readDouble(_selectedUnit?['capacidad_tanque_gal']);

  double? get _currentTankLevel =>
      readDouble(_selectedUnit?['combustible_actual_gal']);

  double? get _maximumRefuelGallons {
    final capacity = _tankCapacity;
    if (capacity == null) return null;
    final remaining = (capacity - (_currentTankLevel ?? 0))
        .clamp(0.0, capacity)
        .toDouble();
    return remaining < 9999.99 ? remaining : 9999.99;
  }

  String _normalizeDecimal(String? value) =>
      (value ?? '').trim().replaceAll(',', '.');

  int? _activeTripIdForUnit(int? unitId) {
    final trip = _activeTripForUnit(unitId);
    return trip == null ? null : readInt(trip['id_viaje']);
  }

  Map<String, dynamic>? _activeTripForUnit(int? unitId) => widget.trips
      .where(
        (trip) =>
            readInt(trip['id_unidad']) == unitId &&
            readInt(trip['id_estado_viaje']) == 2,
      )
      .firstOrNull;

  String? _positive(
    String? value, {
    required int decimalPlaces,
    double? maximum,
  }) {
    final input = _normalizeDecimal(value);
    final pattern = RegExp(
      decimalPlaces == 0 ? r'^\d+$' : '^\\d+(?:\\.\\d{1,$decimalPlaces})?\$',
    );
    if (!pattern.hasMatch(input)) {
      return 'Usa un número mayor que cero con hasta $decimalPlaces decimales.';
    }
    final number = double.tryParse(input);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Ingresa un valor mayor que cero.';
    }
    if (maximum != null && number > maximum) {
      return 'No puede superar la capacidad del tanque (${maximum.toStringAsFixed(2)} gal).';
    }
    return null;
  }

  String? _validateGallons(String? value) {
    final capacity = _tankCapacity;
    if (capacity == null || capacity <= 0) {
      return 'Registra primero la capacidad del tanque en Unidades.';
    }
    final error = _positive(value, decimalPlaces: 2);
    if (error != null) return error;
    final gallons = double.parse(_normalizeDecimal(value));
    final maximum = _maximumRefuelGallons!;
    if (gallons > maximum) {
      final current = _currentTankLevel;
      if (current != null && current > 0) {
        return 'La unidad ya tiene ${current.toStringAsFixed(2)} gal; solo puede cargar hasta ${maximum.toStringAsFixed(2)} gal más (capacidad: ${capacity.toStringAsFixed(2)} gal).';
      }
      return 'No puede superar la capacidad del tanque (${capacity.toStringAsFixed(2)} gal).';
    }
    return null;
  }

  String? _validateTankLevel(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final error = _positive(value, decimalPlaces: 2, maximum: _tankCapacity);
    if (error != null) {
      if (_tankCapacity == null || _tankCapacity! <= 0) {
        return 'Registra primero la capacidad del tanque en Unidades.';
      }
      return error;
    }
    final level = double.parse(_normalizeDecimal(value));
    final gallons = double.tryParse(_normalizeDecimal(_gallons.text));
    if (gallons != null && level < gallons) {
      return 'El nivel final debe ser al menos igual a los galones comprados.';
    }
    return null;
  }

  String? _validateTrip(int? tripId) {
    if (tripId != null) {
      final trip = widget.trips
          .where((item) => readInt(item['id_viaje']) == tripId)
          .firstOrNull;
      if (trip == null || readInt(trip['id_unidad']) != _unitId) {
        return 'El viaje debe corresponder a la unidad seleccionada.';
      }
      if (![1, 2].contains(readInt(trip['id_estado_viaje']))) {
        return 'Solo puedes asociar viajes programados o en curso.';
      }
      if (readInt(trip['id_estado_viaje']) == 2) {
        final departure = DateTime.tryParse(
          trip['fecha_salida']?.toString() ?? '',
        );
        if (departure == null) {
          return 'El viaje en curso no tiene una hora de salida registrada.';
        }
        if (_dateTime.isBefore(departure)) {
          return 'La fecha de la recarga no puede ser anterior a la salida.';
        }
      }
    } else if (_activeTripForUnit(_unitId) != null) {
      return 'Selecciona el viaje en curso para asociar esta recarga.';
    }
    return null;
  }

  Future<void> _pickDateTime(FormFieldState<DateTime> field) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime.isAfter(now) ? now : _dateTime,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => _dateTime = selected);
    field.didChange(selected);
    _formKey.currentState?.validate();
  }

  String? _validateDateTime(DateTime? value) {
    if (value == null) return 'La fecha de la recarga es obligatoria.';
    if (value.isAfter(DateTime.now())) {
      return 'La fecha de la recarga no puede estar en el futuro.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.post('viajes/recargas/', {
        'id_unidad': _unitId,
        'id_viaje': _tripId,
        'fecha_hora': _dateTime.toIso8601String(),
        'galones': _normalizeDecimal(_gallons.text),
        'nivel_tanque_gal': _normalizeDecimal(_tankLevel.text).isEmpty
            ? null
            : _normalizeDecimal(_tankLevel.text),
        'precio_galon': _normalizeDecimal(_price.text),
        'lugar': _place.text.trim(),
        'numero_factura': _invoice.text.trim(),
      });
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
    title: const Text('Registrar recarga'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _unitId,
                decoration: const InputDecoration(labelText: 'Unidad *'),
                items: widget.units
                    .map(
                      (unit) => DropdownMenuItem<int>(
                        value: readInt(unit['id_unidad']),
                        child: Text(unit['placa']?.toString() ?? 'Unidad'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _unitId = value;
                    _tripId = _activeTripIdForUnit(value);
                  });
                  _formKey.currentState?.validate();
                },
                validator: (value) =>
                    value == null ? 'Selecciona una unidad.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _tripId,
                decoration: const InputDecoration(labelText: 'Viaje'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Carga de unidad, sin viaje'),
                  ),
                  ...widget.trips.map(
                    (trip) => DropdownMenuItem<int?>(
                      value: readInt(trip['id_viaje']),
                      child: Text(
                        '${trip['correlativo'] ?? 'Viaje'} · ${trip['unidad_placa'] ?? 'Unidad'}',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _tripId = value;
                    if (value != null) {
                      final trip = widget.trips
                          .where((item) => readInt(item['id_viaje']) == value)
                          .firstOrNull;
                      _unitId = readInt(trip?['id_unidad']);
                    }
                  });
                  _formKey.currentState?.validate();
                },
                validator: _validateTrip,
              ),
              if (_activeTripForUnit(_unitId) != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Esta unidad está en viaje; asocia la recarga al viaje en curso.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              FormField<DateTime>(
                initialValue: _dateTime,
                validator: _validateDateTime,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fecha y hora de compra *'),
                      subtitle: Text(
                        '${_dateTime.day.toString().padLeft(2, '0')}/${_dateTime.month.toString().padLeft(2, '0')}/${_dateTime.year} · ${_dateTime.hour.toString().padLeft(2, '0')}:${_dateTime.minute.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: _saving ? null : () => _pickDateTime(field),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _gallons,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Galones cargados *',
                ),
                validator: _validateGallons,
                onChanged: (_) => _formKey.currentState?.validate(),
              ),
              if (_currentTankLevel != null && _tankCapacity != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Nivel registrado: ${_currentTankLevel!.toStringAsFixed(2)} gal · Espacio disponible: ${_maximumRefuelGallons!.toStringAsFixed(2)} gal',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tankLevel,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Nivel final del tanque (gal, opcional)',
                ),
                validator: _validateTankLevel,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio por galón *',
                ),
                validator: (value) =>
                    _positive(value, decimalPlaces: 3, maximum: 999.999),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _place,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Gasolinera o lugar',
                ),
              ),
              TextFormField(
                controller: _invoice,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Número de factura',
                ),
              ),
              if (_error != null) ErrorBanner(message: _error!),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Guardar'),
      ),
    ],
  );
}
