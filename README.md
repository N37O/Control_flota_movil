# Aplicación móvil Sistema de Flota

Aplicación Flutter para Android e iOS que consume la API REST existente del sistema.

## Requisitos

- Flutter 3.24 o posterior y Dart.
- Android Studio/Android SDK para compilar Android.
- La API Django iniciada y accesible desde el dispositivo.

Instala las dependencias Dart desde esta carpeta:

```powershell
flutter pub get
```

## Ejecutar

Desde esta carpeta:

```powershell
flutter run
```

La pantalla de acceso permite configurar la dirección de la API:

- Emulador Android: `http://10.0.2.2:8000/api`
- Simulador iOS: `http://127.0.0.1:8000/api`
- Teléfono físico: `http://<IP-local-del-equipo>:8000/api`

`10.0.2.2` solo funciona en el emulador Android. Para un teléfono físico,
selecciona **Teléfono USB** si está conectado por USB o **Teléfono Wi-Fi** si
ambos dispositivos están en la misma red. El botón Wi-Fi usa
`192.168.154.71` como IP predeterminada en esta red; si cambia, edítala en el
campo o define `PHYSICAL_API_HOST`. El botón **Emulador** vuelve a
`10.0.2.2`. En todos los casos la API usa el puerto 8000.

Inicia la app en el emulador Android:
```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

En un teléfono físico conectado por USB, reenvía el puerto a la API local y
ejecuta la app:
```powershell
adb reverse tcp:8000 tcp:8000
flutter run -d <ID-del-dispositivo> --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Para usar Wi-Fi, reemplaza `192.168.154.71` por la IPv4 que muestra `ipconfig`,
permite el puerto 8000 en el firewall y ejecuta Django escuchando en todas las
interfaces. Esto también permite al emulador usar la API:

```powershell
python manage.py runserver 0.0.0.0:8000
```

Permite el puerto 8000 en el firewall y asegúrate de que la API admita el host
utilizado en `ALLOWED_HOSTS`.

HTTP sin cifrar se habilita solo para compilaciones Android de depuración. Antes
de publicar, configura una dirección HTTPS y no habilites HTTP en producción.

## Funcionalidades

- Inicio de sesión JWT con renovación automática del token de acceso.
- Resumen operativo e informes de solo consulta.
- CRUD de unidades y conductores, incluida la activación y desactivación.
- CRUD de viajes programados y rutas viales calculadas con OSRM, visibles sobre
  el mapa de OpenStreetMap. Al registrar un viaje, el selector a pantalla
  completa permite marcar el inicio y el destino tocando el mapa.
- Registro de cargas, salidas y entradas desde la pantalla Operaciones.
- Simulación automática del estado y avance de los viajes según sus horarios:
  la lista se actualiza cada 30 segundos y la simulación termina a la hora
  estimada. Los viajes simulados se identifican como tales y no generan lecturas
  reales de odómetro, combustible ni posiciones GPS.
- Registro de recargas mediante la API.
- Pantallas separadas por módulo en `lib/screens/` (por ejemplo,
  `conductores_screen.dart` y `unidades_screen.dart`).
- Dirección de API editable y persistencia local de la sesión.
- `ADMINISTRADOR` administra usuarios, roles y registros desde el panel web; no
  puede iniciar sesión en esta aplicación móvil. `OPERADOR` puede registrar
  unidades, viajes, cargas, movimientos y recargas, sin editar ni eliminar
  registros existentes. `SUPERVISOR` consulta unidades, viajes, mapas e
  informes. La API valida los permisos de cada operación en el servidor; solo el
  administrador puede crear o modificar roles y usuarios.

Antes de iniciar el servidor con esta versión, aplica las migraciones de Django:

```powershell
python manage.py migrate
```
