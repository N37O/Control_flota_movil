import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_flota/auth/app_permissions.dart';

void main() {
  test(
    'administrator has the same management permissions as the web panel',
    () {
      final permissions = AppPermissions.fromUser(
        user: {'rol_nombre': 'ADMINISTRADOR'},
        verifiedByApi: true,
      );

      expect(permissions.canManageUnits, isTrue);
      expect(permissions.canManageDrivers, isTrue);
      expect(permissions.canManageTrips, isTrue);
      expect(permissions.canRegisterUnits, isTrue);
      expect(permissions.canRegisterTrips, isTrue);
      expect(permissions.canRegisterLoads, isTrue);
      expect(permissions.canRegisterMovements, isTrue);
      expect(permissions.canRegisterRefuels, isTrue);
      expect(permissions.canAccessMobile, isFalse);
    },
  );

  test('operator can register operational records but not manage catalogs', () {
    final permissions = AppPermissions.fromUser(
      user: {'rol_nombre': 'OPERADOR'},
      verifiedByApi: true,
    );

    expect(permissions.canManageUnits, isFalse);
    expect(permissions.canManageDrivers, isFalse);
    expect(permissions.canManageTrips, isFalse);
    expect(permissions.canRegisterUnits, isTrue);
    expect(permissions.canRegisterTrips, isTrue);
    expect(permissions.canRegisterLoads, isTrue);
    expect(permissions.canRegisterMovements, isTrue);
    expect(permissions.canRegisterRefuels, isTrue);
    expect(permissions.canAccessMobile, isTrue);
  });

  test('supervisor can consult but cannot register or manage records', () {
    final permissions = AppPermissions.fromUser(
      user: {'rol_nombre': 'SUPERVISOR'},
      verifiedByApi: true,
    );

    expect(permissions.isSupervisor, isTrue);
    expect(permissions.canManageUnits, isFalse);
    expect(permissions.canManageDrivers, isFalse);
    expect(permissions.canManageTrips, isFalse);
    expect(permissions.canRegisterUnits, isFalse);
    expect(permissions.canRegisterTrips, isFalse);
    expect(permissions.canRegisterLoads, isFalse);
    expect(permissions.canRegisterMovements, isFalse);
    expect(permissions.canRegisterRefuels, isFalse);
    expect(permissions.canAccessMobile, isTrue);
  });

  test(
    'unknown or unverified roles never receive administrator permissions',
    () {
      for (final user in [
        <String, dynamic>{},
        {'rol_nombre': 'SUPERVISOR'},
        {'rol_nombre': 'ADMINISTRADOR'},
      ]) {
        final permissions = AppPermissions.fromUser(
          user: user,
          verifiedByApi: false,
        );

        expect(permissions.isAdministrator, isFalse);
        expect(permissions.canAccessMobile, isFalse);
      }
    },
  );
}
