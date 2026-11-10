import 'package:flutter/material.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, required this.onRetry, super.key});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: Color(0xFF8794A5),
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Text(message, style: TextStyle(color: Colors.blueGrey.shade600)),
    ),
  );
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(message, style: const TextStyle(color: Color(0xFFB42318))),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    this.color = const Color(0xFF16805D),
    super.key,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
        ),
    ],
  );
}

int readInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

double? readDouble(dynamic value) => double.tryParse(value?.toString() ?? '');

bool readBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

String formatDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return '—';
  final local = date.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String tripStatus(int status) => switch (status) {
  1 => 'Programado',
  2 => 'En curso',
  3 => 'Completado',
  4 => 'Cancelado',
  _ => 'Desconocido',
};

Color tripStatusColor(int status) => switch (status) {
  1 => const Color(0xFFB66A00),
  2 => const Color(0xFF3457D5),
  3 => const Color(0xFF16805D),
  4 => const Color(0xFF6B7280),
  _ => const Color(0xFF6B7280),
};
