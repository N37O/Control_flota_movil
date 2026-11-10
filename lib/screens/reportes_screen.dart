import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'common_widgets.dart';

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _performance = {};
  List<Map<String, dynamic>> _history = [];

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
        widget.api.getMap('reportes/rendimiento/'),
        widget.api.getList('reportes/historial/'),
      ]);
      if (!mounted) return;
      setState(() {
        _performance = values[0] as Map<String, dynamic>;
        _history = values[1] as List<Map<String, dynamic>>;
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
    if (_loading && _history.isEmpty && _performance.isEmpty) {
      return const LoadingView();
    }
    if (_error != null && _history.isEmpty && _performance.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(
                    Icons.speed_rounded,
                    color: Color(0xFF087E8B),
                    size: 34,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rendimiento promedio'),
                        const SizedBox(height: 4),
                        Text(
                          '${_performance['rendimiento_promedio'] ?? '0'} km/gal',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  Text('${_performance['total_viajes'] ?? 0} viajes'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle(
            title: 'Historial de viajes',
            trailing: 'Últimos 50',
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const EmptyView(message: 'No hay historial de viajes disponible.')
          else
            ..._history.map((trip) => _HistoryCard(trip: trip)),
          if (_error != null) ErrorBanner(message: _error!),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.trip});

  final Map<String, dynamic> trip;

  @override
  Widget build(BuildContext context) {
    final status = trip['estado']?.toString() ?? 'DESCONOCIDO';
    final statusNumber = switch (status.toUpperCase()) {
      'PROGRAMADO' => 1,
      'EN_CURSO' || 'EN_TRANSITO' => 2,
      'COMPLETADO' => 3,
      'CANCELADO' => 4,
      _ => 0,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFEFF3F7),
          child: Icon(Icons.route_outlined, color: Color(0xFF13243A)),
        ),
        title: Text(
          trip['correlativo']?.toString() ?? 'Viaje',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${trip['origen'] ?? 'Origen'} → ${trip['destino'] ?? 'Destino'}\n'
          '${trip['unidad'] ?? 'Unidad'} · ${trip['conductor'] ?? 'Conductor'}',
        ),
        trailing: StatusChip(
          label: status.replaceAll('_', ' '),
          color: tripStatusColor(statusNumber),
        ),
      ),
    );
  }
}
