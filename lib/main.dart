import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/app_permissions.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';

const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const _defaultApiBaseUrl = 'http://158.23.59.41/api';
const _mobileAccessDeniedMessage =
    'El rol administrador no puede acceder desde la aplicación móvil. '
    'Usa el panel web.';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final storedApiBaseUrl = preferences.getString('api_base_url');
  final isLegacyLocalUrl =
      storedApiBaseUrl == 'http://10.0.2.2:8000/api' ||
      storedApiBaseUrl == 'http://127.0.0.1:8000/api';
  final isFirstHostedApiLaunch =
      storedApiBaseUrl == _defaultApiBaseUrl &&
      !(preferences.getBool('hosted_api_session_migrated') ?? false);
  final shouldResetSession = isLegacyLocalUrl || isFirstHostedApiLaunch;
  final savedApiBaseUrl = isLegacyLocalUrl
      ? _defaultApiBaseUrl
      : storedApiBaseUrl;
  if (shouldResetSession) {
    await preferences.setString('api_base_url', _defaultApiBaseUrl);
    await preferences.remove('access_token');
    await preferences.remove('refresh_token');
    await preferences.remove('user_data');
  }
  await preferences.setBool('hosted_api_session_migrated', true);
  final api = ApiService(
    baseUrl: _configuredApiBaseUrl.isNotEmpty
        ? _configuredApiBaseUrl
        : savedApiBaseUrl ?? _defaultApiBaseUrl,
    accessToken: preferences.getString('access_token'),
    refreshToken: preferences.getString('refresh_token'),
    onTokenUpdate: (access, refresh) async {
      if (access == null || refresh == null) {
        await preferences.remove('access_token');
        await preferences.remove('refresh_token');
      } else {
        await preferences.setString('access_token', access);
        await preferences.setString('refresh_token', refresh);
      }
    },
  );
  final cachedUser = preferences.getString('user_data');
  Map<String, dynamic>? user;
  if (cachedUser != null) {
    try {
      final decoded = jsonDecode(cachedUser);
      if (decoded is Map<String, dynamic>) user = decoded;
    } on FormatException {
      await preferences.remove('user_data');
    }
  }
  runApp(
    FlotaApp(
      api: api,
      preferences: preferences,
      initialUser: api.accessToken == null ? null : user,
    ),
  );
}

class FlotaApp extends StatefulWidget {
  const FlotaApp({
    required this.api,
    required this.preferences,
    required this.initialUser,
    super.key,
  });

  final ApiService api;
  final SharedPreferences preferences;
  final Map<String, dynamic>? initialUser;

  @override
  State<FlotaApp> createState() => _FlotaAppState();
}

class _FlotaAppState extends State<FlotaApp> {
  late Map<String, dynamic>? _user = widget.initialUser;
  bool _roleVerified = false;
  String? _roleVerificationError;
  String? _loginError;

  @override
  void initState() {
    super.initState();
    if (_user != null) _verifyStoredRole();
  }

  Future<void> _onLogin(Map<String, dynamic> response) async {
    final user = response['usuario'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException(
        'La respuesta de acceso no contiene los datos del usuario.',
      );
    }
    final permissions = AppPermissions.fromUser(
      user: user,
      verifiedByApi: true,
    );
    if (!permissions.canAccessMobile) {
      await widget.api.logout();
      throw const ApiException(_mobileAccessDeniedMessage);
    }
    await widget.preferences.setString('api_base_url', widget.api.baseUrl);
    await widget.preferences.setString('user_data', jsonEncode(user));
    setState(() {
      _user = user;
      _roleVerified = true;
      _roleVerificationError = null;
      _loginError = null;
    });
  }

  Future<void> _onLogout() async {
    await widget.api.logout();
    await _clearUser();
  }

  Future<void> _onSessionExpired() async {
    await _clearUser();
  }

  Future<void> _verifyStoredRole() async {
    try {
      final user = await widget.api.getMap('usuarios/usuarios/yo/');
      final permissions = AppPermissions.fromUser(
        user: user,
        verifiedByApi: true,
      );
      if (!permissions.canAccessMobile) {
        await widget.api.logout();
        await _clearUser();
        if (mounted) {
          setState(() => _loginError = _mobileAccessDeniedMessage);
        }
        return;
      }
      await widget.preferences.setString('user_data', jsonEncode(user));
      if (mounted) {
        setState(() {
          _user = user;
          _roleVerified = true;
          _roleVerificationError = null;
        });
      }
    } on ApiException catch (error) {
      if (mounted && widget.api.accessToken != null) {
        setState(() {
          _roleVerified = false;
          _roleVerificationError = error.message;
        });
      }
    }
  }

  Future<void> _clearUser() async {
    await widget.preferences.remove('user_data');
    if (mounted) {
      setState(() {
        _user = null;
        _roleVerified = false;
        _roleVerificationError = null;
        _loginError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF13243A);
    const teal = Color(0xFF087E8B);
    return MaterialApp(
      title: 'Sistema de Flota',
      debugShowCheckedModeBanner: false,
      scrollBehavior: MaterialScrollBehavior().copyWith(
        physics: const ClampingScrollPhysics(),
        overscroll: false,
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          primary: navy,
          secondary: teal,
          surface: const Color(0xFFF6F8FB),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE8EDF3)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDDE4EC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDDE4EC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: teal, width: 1.5),
          ),
        ),
      ),
      home: _user == null
          ? LoginScreen(
              api: widget.api,
              onLogin: _onLogin,
              initialError: _loginError,
            )
          : !_roleVerified
          ? _RoleVerificationScreen(
              error: _roleVerificationError,
              onRetry: _verifyStoredRole,
              onLogout: _onLogout,
            )
          : HomeShell(
              api: widget.api,
              user: _user!,
              roleVerified: _roleVerified,
              roleVerificationError: _roleVerificationError,
              onVerifyRole: _verifyStoredRole,
              onLogout: _onLogout,
              onSessionExpired: _onSessionExpired,
            ),
    );
  }
}

class _RoleVerificationScreen extends StatelessWidget {
  const _RoleVerificationScreen({
    required this.error,
    required this.onRetry,
    required this.onLogout,
  });

  final String? error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error == null)
                const CircularProgressIndicator()
              else
                const Icon(Icons.wifi_off, size: 40),
              const SizedBox(height: 16),
              Text(
                error ?? 'Verificando permisos de acceso…',
                textAlign: TextAlign.center,
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
                TextButton(
                  onPressed: onLogout,
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
