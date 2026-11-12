import 'package:flutter/material.dart';

import '../auth/app_permissions.dart';
import '../services/api_service.dart';
import 'conductores_screen.dart';
import 'dashboard_screen.dart';
import 'operaciones_screen.dart';
import 'reportes_screen.dart';
import 'unidades_screen.dart';
import 'viajes_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.api,
    required this.user,
    required this.roleVerified,
    required this.roleVerificationError,
    required this.onVerifyRole,
    required this.onLogout,
    required this.onSessionExpired,
    super.key,
  });

  final ApiService api;
  final Map<String, dynamic> user;
  final bool roleVerified;
  final String? roleVerificationError;
  final Future<void> Function() onVerifyRole;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSessionExpired;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.api.onSessionExpired = widget.onSessionExpired;
  }

  @override
  Widget build(BuildContext context) {
    final permissions = AppPermissions.fromUser(
      user: widget.user,
      verifiedByApi: widget.roleVerified,
    );
    final pages = <Widget>[
      DashboardScreen(api: widget.api),
      UnidadesScreen(
        api: widget.api,
        isAdmin: permissions.canManageUnits,
        canRegister: permissions.canRegisterUnits,
      ),
    ];
    final pageTitles = <String>['Resumen de flota', 'Unidades'];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Inicio',
      ),
      const NavigationDestination(
        icon: Icon(Icons.local_shipping_outlined),
        selectedIcon: Icon(Icons.local_shipping),
        label: 'Unidades',
      ),
    ];
    if (permissions.isAdministrator) {
      pages.add(
        ConductoresScreen(
          api: widget.api,
          isAdmin: permissions.canManageDrivers,
        ),
      );
      pageTitles.add('Conductores');
      destinations.add(
        const NavigationDestination(
          icon: Icon(Icons.badge_outlined),
          selectedIcon: Icon(Icons.badge),
          label: 'Conductores',
        ),
      );
    }
    pages.add(
      ViajesScreen(
        api: widget.api,
        isAdmin: permissions.canManageTrips,
        canRegister: permissions.canRegisterTrips,
      ),
    );
    pageTitles.add('Viajes');
    destinations.add(
      const NavigationDestination(
        icon: Icon(Icons.route_outlined),
        selectedIcon: Icon(Icons.route),
        label: 'Viajes',
      ),
    );
    if (permissions.canRegisterLoads) {
      final operationsIndex = pages.length;
      pages.add(
        OperacionesScreen(
          api: widget.api,
          isActive: _selectedIndex == operationsIndex,
        ),
      );
      pageTitles.add('Operaciones');
      destinations.add(
        const NavigationDestination(
          icon: Icon(Icons.swap_horiz),
          selectedIcon: Icon(Icons.swap_horiz),
          label: 'Operaciones',
        ),
      );
    }
    if (permissions.isAdministrator || permissions.isSupervisor) {
      pages.add(ReportesScreen(api: widget.api));
      pageTitles.add('Reportes');
      destinations.add(
        const NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: 'Reportes',
        ),
      );
    }
    final name = widget.user['nombre']?.toString() ?? 'Usuario';
    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitles[_selectedIndex]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Cuenta',
            onSelected: (value) async {
              if (value == 'logout') await widget.onLogout();
              if (value == 'verify_role') await widget.onVerifyRole();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.user['rol_nombre']?.toString() ?? 'Usuario',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              if (!widget.roleVerified)
                const PopupMenuItem(
                  value: 'verify_role',
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 19),
                      SizedBox(width: 10),
                      Text('Verificar permisos'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 19),
                    SizedBox(width: 10),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white.withValues(alpha: .16),
                child: Text(
                  name.isEmpty ? 'U' : name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.roleVerified)
            Material(
              color: const Color(0xFFFFF4D6),
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.warning_amber,
                  color: Color(0xFF8B5C00),
                ),
                title: Text(
                  widget.roleVerificationError ??
                      'No se han podido verificar tus permisos. El acceso está en modo de solo lectura.',
                  style: const TextStyle(
                    color: Color(0xFF704B00),
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Verificar permisos',
                  onPressed: widget.onVerifyRole,
                  icon: const Icon(Icons.refresh, color: Color(0xFF8B5C00)),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: destinations,
      ),
    );
  }
}
