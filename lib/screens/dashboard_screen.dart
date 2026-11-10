import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'common_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _trips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        widget.api.getMap('reportes/panel/'),
        widget.api.getList('unidades/unidades/'),
        widget.api.getList('viajes/viajes/'),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = values[0] as Map<String, dynamic>;
        _units = values[1] as List<Map<String, dynamic>>;
        _trips = values[2] as List<Map<String, dynamic>>;
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _units.isEmpty) return const LoadingView();
    if (_error != null && _units.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    final activeUnits = _units
        .where((unit) => readBool(unit['activo'], fallback: true))
        .toList();
    final planned = _trips
        .where((trip) => readInt(trip['id_estado_viaje']) == 1)
        .length;
    final inTransit = _trips
        .where((trip) => readInt(trip['id_estado_viaje']) == 2)
        .length;
    final lowFuel = activeUnits.where((unit) {
      final current = readDouble(unit['combustible_actual_gal']);
      final capacity = readDouble(unit['capacidad_tanque_gal']);
      return current != null &&
          capacity != null &&
          capacity > 0 &&
          current / capacity < .2;
    }).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Text(
            'Operación en tiempo real',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF13243A),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Indicadores principales de tu flota.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(
                    width: width,
                    label: 'Unidades disponibles',
                    value:
                        '${_summary['unidades_disponibles'] ?? activeUnits.length}',
                    icon: Icons.local_shipping_outlined,
                    color: const Color(0xFF087E8B),
                  ),
                  _StatCard(
                    width: width,
                    label: 'En tránsito',
                    value: '${_summary['viajes_transito'] ?? inTransit}',
                    icon: Icons.alt_route_rounded,
                    color: const Color(0xFF3457D5),
                  ),
                  _StatCard(
                    width: width,
                    label: 'Programados',
                    value: '${_summary['viajes_programados'] ?? planned}',
                    icon: Icons.event_available_outlined,
                    color: const Color(0xFFB66A00),
                  ),
                  _StatCard(
                    width: width,
                    label: 'Alertas pendientes',
                    value: '${_summary['alertas_pendientes'] ?? lowFuel}',
                    icon: Icons.warning_amber_rounded,
                    color: const Color(0xFFCA3D3D),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          SectionTitle(
            title: 'Viajes recientes',
            trailing: '${_trips.length} registrados',
          ),
          const SizedBox(height: 8),
          if (_trips.isEmpty)
            const EmptyView(message: 'No hay viajes registrados.')
          else
            ..._trips.take(5).map((trip) => _DashboardTripCard(trip: trip)),
          const SizedBox(height: 16),
          SectionTitle(
            title: 'Estado de las unidades',
            trailing: '${activeUnits.length} activas',
          ),
          const SizedBox(height: 8),
          if (activeUnits.isEmpty)
            const EmptyView(message: 'No hay unidades activas.')
          else
            ...activeUnits
                .take(4)
                .map((unit) => _DashboardUnitCard(unit: unit)),
          if (_error != null) ErrorBanner(message: _error!),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.blueGrey.shade700)),
          ],
        ),
      ),
    ),
  );
}

class _DashboardTripCard extends StatelessWidget {
  const _DashboardTripCard({required this.trip});

  final Map<String, dynamic> trip;

  @override
  Widget build(BuildContext context) {
    final status = readInt(trip['id_estado_viaje']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          trip['correlativo']?.toString() ?? 'Viaje',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${trip['origen_nombre'] ?? 'Origen'} → ${trip['destino_nombre'] ?? 'Destino'}',
        ),
        trailing: StatusChip(
          label: tripStatus(status),
          color: tripStatusColor(status),
        ),
      ),
    );
  }
}

class _DashboardUnitCard extends StatelessWidget {
  const _DashboardUnitCard({required this.unit});

  final Map<String, dynamic> unit;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: const Icon(
        Icons.local_shipping_outlined,
        color: Color(0xFF087E8B),
      ),
      title: Text(
        unit['placa']?.toString() ?? 'Unidad',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${unit['tipo_nombre'] ?? 'Tipo no indicado'} · ${unit['estado_nombre'] ?? 'Sin estado'}',
      ),
    ),
  );
}
