import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import 'common_widgets.dart';

class ConductoresScreen extends StatefulWidget {
  const ConductoresScreen({
    required this.api,
    required this.isAdmin,
    super.key,
  });

  final ApiService api;
  final bool isAdmin;

  @override
  State<ConductoresScreen> createState() => _ConductoresScreenState();
}

class _ConductoresScreenState extends State<ConductoresScreen> {
  bool _loading = true;
  bool _showInactive = false;
  String? _error;
  List<Map<String, dynamic>> _drivers = [];

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
      final drivers = await widget.api.getList('unidades/conductores/');
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
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

  Future<void> _edit([Map<String, dynamic>? driver]) async {
    if (!widget.isAdmin) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _DriverFormDialog(driver: driver, drivers: _drivers, api: widget.api),
    );
    if (saved == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              driver == null
                  ? 'Conductor creado correctamente.'
                  : 'Conductor actualizado correctamente.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> driver) async {
    if (!widget.isAdmin) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar conductor'),
        content: Text(
          '¿Eliminar a ${driver['nombre']}? Esta acción no se puede deshacer.',
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
      await widget.api.delete(
        'unidades/conductores/${driver['id_conductor']}/',
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Conductor eliminado.')));
      }
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> driver) async {
    if (!widget.isAdmin) return;
    final active = !readBool(driver['activo'], fallback: true);
    try {
      await widget.api.patch(
        'unidades/conductores/${driver['id_conductor']}/',
        {'activo': active},
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
    if (_loading && _drivers.isEmpty) return const LoadingView();
    if (_error != null && _drivers.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    final drivers = _drivers
        .where(
          (driver) =>
              _showInactive || readBool(driver['activo'], fallback: true),
        )
        .toList();
    final activeCount = _drivers
        .where((driver) => readBool(driver['activo'], fallback: true))
        .length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Nuevo conductor'),
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
                    '$activeCount activos · ${_drivers.length} registrados',
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  ),
                ),
                ChoiceChip(
                  label: Text(_showInactive ? 'Todos' : 'Activos'),
                  selected: true,
                  onSelected: (_) =>
                      setState(() => _showInactive = !_showInactive),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (drivers.isEmpty)
              const EmptyView(message: 'No se encontraron conductores.')
            else
              ...drivers.map(
                (driver) => _DriverCard(
                  driver: driver,
                  isAdmin: widget.isAdmin,
                  onEdit: widget.isAdmin ? () => _edit(driver) : null,
                  onDelete: widget.isAdmin ? () => _delete(driver) : null,
                  onToggleActive: widget.isAdmin
                      ? () => _toggleActive(driver)
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

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.driver,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final Map<String, dynamic> driver;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleActive;

  @override
  Widget build(BuildContext context) {
    final active = readBool(driver['activo'], fallback: true);
    final name = driver['nombre']?.toString() ?? 'Conductor';
    final licenseImageUrl = driver['licencia_imagen_url']?.toString();
    final hasLicenseImage = licenseImageUrl != null && licenseImageUrl.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 8, 12),
        child: Row(
          children: [
            Tooltip(
              message: hasLicenseImage
                  ? 'Ver foto de la licencia'
                  : 'Sin foto de licencia',
              child: GestureDetector(
                onTap: hasLicenseImage
                    ? () => _showLicenseImage(context, licenseImageUrl)
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 76,
                    height: 56,
                    child: hasLicenseImage
                        ? Image.network(
                            licenseImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(
                                  color: Color(0xFFE5F4F5),
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Color(0xFF087E8B),
                                  ),
                                ),
                          )
                        : const ColoredBox(
                            color: Color(0xFFE5F4F5),
                            child: Icon(
                              Icons.badge_outlined,
                              color: Color(0xFF087E8B),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Licencia: ${driver['licencia'] ?? '—'} · DUI: ${driver['dui'] ?? '—'}',
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${driver['tipo_licencia'] ?? 'Tipo sin indicar'} · ${driver['telefono'] ?? 'Sin teléfono'}',
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  StatusChip(
                    label: active ? 'Activo' : 'Inactivo',
                    color: active
                        ? const Color(0xFF16805D)
                        : const Color(0xFF6B7280),
                  ),
                ],
              ),
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
                  const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showLicenseImage(BuildContext context, String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No se pudo cargar la foto de la licencia.'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverFormDialog extends StatefulWidget {
  const _DriverFormDialog({
    required this.api,
    required this.drivers,
    this.driver,
  });

  final ApiService api;
  final List<Map<String, dynamic>> drivers;
  final Map<String, dynamic>? driver;

  @override
  State<_DriverFormDialog> createState() => _DriverFormDialogState();
}

class _DriverFormDialogState extends State<_DriverFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.driver?['nombre']?.toString(),
  );
  late final _dui = TextEditingController(
    text: widget.driver?['dui']?.toString(),
  );
  late final _license = TextEditingController(
    text: widget.driver?['licencia']?.toString(),
  );
  late final _licenseType = TextEditingController(
    text: widget.driver?['tipo_licencia']?.toString() ?? 'Pesado',
  );
  late final _phone = TextEditingController(
    text: widget.driver?['telefono']?.toString(),
  );
  bool _active = true;
  bool _saving = false;
  bool _pickingImage = false;
  XFile? _licenseImage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _active = readBool(widget.driver?['activo'], fallback: true);
  }

  @override
  void dispose() {
    _name.dispose();
    _dui.dispose();
    _license.dispose();
    _licenseType.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? _validateDui(String? value) => _validateUniqueId(value, 'dui');

  String? _validateLicense(String? value) =>
      _validateUniqueId(value, 'licencia');

  String? _validateUniqueId(String? value, String field) {
    final id = (value ?? '').trim();
    if (id.isEmpty) return null;
    if (!RegExp(r'^\d{8}-\d$').hasMatch(id)) {
      return 'Formato requerido: 00000000-0.';
    }
    final currentId = widget.driver?['id_conductor']?.toString();
    final duplicate = widget.drivers.any(
      (driver) =>
          driver['id_conductor']?.toString() != currentId &&
          driver[field]?.toString().trim() == id,
    );
    return duplicate ? 'Este número ya está registrado.' : null;
  }

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.length < 3) {
      return 'El nombre debe tener al menos 3 caracteres.';
    }
    if (name.length > 100) return 'El nombre no puede superar 100 caracteres.';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = (value ?? '').trim();
    if (phone.isNotEmpty && !RegExp(r'^\d{8,9}$').hasMatch(phone)) {
      return 'Escribe un teléfono de 8 o 9 dígitos.';
    }
    return null;
  }

  Future<void> _pickLicenseImage(ImageSource source) async {
    setState(() {
      _pickingImage = true;
      _error = null;
    });
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (!mounted) return;
      if (image == null) {
        setState(() => _pickingImage = false);
        return;
      }

      final extension = image.name.split('.').last.toLowerCase();
      if (!{'jpg', 'jpeg', 'png'}.contains(extension)) {
        setState(() {
          _error = 'La imagen debe ser JPG o PNG.';
          _pickingImage = false;
        });
        return;
      }
      final imageLength = await image.length();
      if (!mounted) return;
      if (imageLength > 5 * 1024 * 1024) {
        setState(() {
          _error = 'La imagen no debe superar 5 MB.';
          _pickingImage = false;
        });
        return;
      }
      setState(() {
        _licenseImage = image;
        _pickingImage = false;
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo abrir la cámara o galería: ${error.message}';
          _pickingImage = false;
        });
      }
    } on FileSystemException {
      if (mounted) {
        setState(() {
          _error = 'No se pudo leer la foto seleccionada.';
          _pickingImage = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = <String, dynamic>{
      'nombre': _name.text.trim(),
      'dui': _dui.text.trim(),
      'licencia': _license.text.trim(),
      'tipo_licencia': _licenseType.text.trim(),
      'telefono': _phone.text.trim(),
      'activo': _active,
    };
    try {
      final image = _licenseImage;
      if (image != null && widget.driver == null) {
        await widget.api.postMultipart(
          'unidades/conductores/',
          data,
          fileField: 'licencia_imagen',
          filePath: image.path,
        );
      } else if (image != null) {
        await widget.api.patchMultipart(
          'unidades/conductores/${widget.driver!['id_conductor']}/',
          data,
          fileField: 'licencia_imagen',
          filePath: image.path,
        );
      } else if (widget.driver == null) {
        await widget.api.post('unidades/conductores/', data);
      } else {
        await widget.api.patch(
          'unidades/conductores/${widget.driver!['id_conductor']}/',
          data,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: const Color(0xFFB42318),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.driver == null ? 'Nuevo conductor' : 'Editar conductor'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                ),
                maxLength: 100,
                validator: _validateName,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dui,
                keyboardType: TextInputType.number,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: 'DUI (00000000-0)',
                ),
                inputFormatters: [_SalvadorIdFormatter()],
                validator: _validateDui,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _license,
                keyboardType: TextInputType.number,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: 'Número de licencia (00000000-0)',
                ),
                inputFormatters: [_SalvadorIdFormatter()],
                validator: _validateLicense,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _licenseType,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: 'Tipo de licencia',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                maxLength: 9,
                inputFormatters: [_DigitsOnlyFormatter()],
                decoration: const InputDecoration(labelText: 'Teléfono'),
                validator: _validatePhone,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Foto de la licencia (opcional)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'JPG o PNG, máximo 5 MB. Puedes tomarla o elegirla de la galería.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickingImage
                          ? null
                          : () => _pickLicenseImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Cámara'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickingImage
                          ? null
                          : () => _pickLicenseImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galería'),
                    ),
                  ),
                ],
              ),
              if (_pickingImage)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              if (_licenseImage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_licenseImage!.path),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else if ((widget.driver?['licencia_imagen_url']?.toString() ?? '')
                  .isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.driver!['licencia_imagen_url'].toString(),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Text('No se pudo cargar la foto guardada.'),
                    ),
                  ),
                ),
              if (_licenseImage != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _pickingImage
                        ? null
                        : () => setState(() => _licenseImage = null),
                    icon: const Icon(Icons.close),
                    label: const Text('Quitar foto nueva'),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Conductor activo'),
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

class _SalvadorIdFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 9 ? digits.substring(0, 9) : digits;
    final formatted = limited.length > 8
        ? '${limited.substring(0, 8)}-${limited.substring(8)}'
        : limited;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _DigitsOnlyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
