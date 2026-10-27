# Nido

Gestor de patrimonio personal para **Android, Windows y web**, con una sola base de código en Flutter y
sincronización en tiempo real entre dispositivos mediante **Firebase** (Authentication + Cloud Firestore).

## Descargas

Versión compilada, lista para usar con el proyecto de Firebase `nido-b0061`:

- **Windows**: [descargas/Nido-Windows.zip](descargas/Nido-Windows.zip). Descomprime la carpeta entera y abre `Nido.exe`.
- **Android**: [descargas/Nido-arm64.apk](descargas/Nido-arm64.apk). Para casi cualquier móvil actual; hay que permitir
  instalar apps de origen desconocido.

## Qué hace

- **Resumen**: patrimonio neto (activos − deudas) con su evolución mensual, variación frente al mes anterior,
  tres indicadores de aguja (colchón de seguridad en meses de gasto, endeudamiento y tasa de ahorro), gasto
  del mes por categoría, distribución (liquidez, inversiones, bienes, deudas), objetivos y últimos movimientos.
- **Cuentas**: agrupadas en Liquidez, Inversiones, Bienes y Deudas, con subtotales y peso de cada una.
  Plantillas para añadir rápido (cuenta corriente, fondo indexado, hipoteca…).
- **Movimientos**: ingresos, gastos y traspasos por categorías y por mes, con filtro y gasto por categoría.
  Ajustan los saldos solos; editar o borrar un movimiento revierte su efecto.
- **Objetivos**: vinculados a cuentas (el progreso es su saldo) o con aportaciones manuales, con estado, fecha
  límite y la aportación mensual necesaria.
- **Primeros pasos y datos de ejemplo**: con la app vacía, una guía de inicio y un botón para cargar un hogar
  de ejemplo (ids `ejemplo-…`) que se quita con otro botón.
- **Sincronización y modo sin conexión**: los cambios se ven al instante en el resto de dispositivos; sin red se
  sigue usando la app y se sincroniza al volver.
- **Recurrentes** (pestaña propia):
  - *Programaciones*: ingresos, gastos y traspasos que se repiten (semanal, mensual, trimestral, anual), con
    fin opcional. Se apuntan solos al abrir la app o se proponen para confirmar. Cada repetición se apunta en
    una transacción que avanza `nextIndex`, así dos dispositivos no la duplican (las reglas impiden que el
    contador retroceda). Lo anterior a la fecha de alta se da por apuntado.
  - *Suscripciones*: las programaciones de la categoría Suscripciones, con coste mensual y anual, próximo
    cargo y aviso si suben de precio.
  - *Plazos*: préstamos, hipotecas y compras a plazos con TIN, plazo y cuadro de amortización (sistema francés).
    Cada cuota se apunta como traspaso del capital a la deuda más un gasto por los intereses, así la tasa de
    ahorro no sale inflada. Indicador cuotas/ingresos (zona roja desde el 35 %).
  - Motor en `lib/domain/recurrence_engine.dart`; en la línea de comandos: `cada mes 12,99 netflix día 14`.
- **Línea de comandos** (`Ctrl+K`, `/` o el icono de terminal): apuntar escribiendo, por ejemplo
  `gasto 54,30 mercadona tarjeta`, `ingreso 2400 nómina`, `traspaso 300 nómina > fondo` o `ayer 12,50 cena`.
  Deduce la categoría por el concepto y la cuenta por su nombre, y muestra la interpretación antes de guardar.
  Intérprete en `lib/domain/command_parser.dart`.
- **Pletina del patrimonio**: ⏪ ▶ ⏩ ■ sobre la lectura del patrimonio neto para rebobinar y reproducir la
  evolución mes a mes.
- **Sincronización a la vista**: las bobinas giran solo mientras se envían cambios; sin conexión se enciende
  un LED de REC con los cambios en cola. Se da por perdida la conexión si una escritura tarda más de 8 s.
- **Objetivos como casete**: la cinta pasa de la bobina izquierda a la derecha según lo ahorrado.
- **Modo privado**: el ojo de la barra superior oculta todos los importes (`••••• €`). Se recuerda en cada
  dispositivo por separado (no se sincroniza), así puedes tenerlo activado en el ordenador y no en el móvil.
- Interfaz adaptable: navegación inferior en móvil y lateral en escritorio, en español. En Windows la barra de
  título es oscura aunque el sistema esté en tema claro.

## Diseño

Sigue el sistema **cassette futurism** de `../.claude/skills/design/SKILL.md` (una copia de la skill
"Cassette Futurism" con el nombre `design`): solo tema oscuro, verde CRT `#33FF00`, ámbar `#FFB000`, rojo cinta,
carbón y beige; VT323 para la interfaz y JetBrains Mono para importes; líneas de escaneo, brillo de fósforo,
bordes gruesos de 8 px, indicadores analógicos, barras LED y bobinas de cinta en lugar de spinners.
Los tokens están en `lib/ui/theme.dart` y las piezas en `lib/ui/widgets/crt.dart`. Una desviación consciente:
el botón principal lleva texto carbón sobre verde (la guía dice ámbar, pero ámbar sobre verde no se lee).

En Windows solo se abre una instancia: si Nido ya está abierto, al lanzarlo de nuevo se trae su ventana al
frente (la caché local de Firestore no admite dos procesos a la vez).

## Puesta en marcha

### 1. Requisitos

- Flutter 3.35 o superior (este equipo lo tiene en `C:\src\flutter`).
- Android: Android Studio con un emulador o un móvil.
- Windows: Visual Studio 2022 con la carga de trabajo **"Desarrollo para el escritorio con C++"**, y el
  **Modo de desarrollador** de Windows activado (Configuración → Sistema → Para programadores). Flutter lo
  necesita para compilar plugins.
- Node.js (para la CLI de Firebase).

### 2. Crear el proyecto de Firebase

1. En <https://console.firebase.google.com> crea un proyecto (por ejemplo `nido`).
2. **Authentication** → Sign-in method → activa **Correo electrónico/contraseña**.
3. **Firestore Database** → Crear base de datos (modo producción, región `europe-west`).

### 3. Conectar la app

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --platforms=android,windows,web
```

`flutterfire configure` sustituye `lib/firebase_options.dart`, que ahora es un archivo provisional. Mientras no
lo ejecutes, la app muestra la pantalla "Falta conectar Firebase".

### 4. Publicar las reglas de seguridad

```bash
firebase use --add
firebase deploy --only firestore:rules,firestore:indexes
```

### 5. Ejecutar

```bash
flutter run -d windows
flutter run -d chrome
flutter run              # en el móvil o emulador Android conectado
```

Para generar los instalables:

- **Android**: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`. Está firmada con la
  clave de depuración: sirve para instalarla directamente, pero no para Google Play.
- **Windows**: `tool\build_windows.bat` → `build/windows/ninja/runner/`. Flutter 3.35 no reconoce Visual Studio
  2026 y elige el MSVC de VS 2019, con el que el SDK C++ de Firebase no enlaza; el script compila con el
  entorno de VS 2026 y Ninja. Hay que distribuir la carpeta entera (exe + DLL + `data/`).
- **Web**: `flutter build web --release`.

Las versiones ya compiladas están en `dist/`: `Nido.apk` y `Nido-Windows.zip`.

## Desarrollo sin proyecto real (emuladores)

```bash
firebase emulators:start --only auth,firestore --project demo-nido
flutter run -d chrome --dart-define=USE_EMULATOR=true
# Emulador de Android: el PC anfitrión es 10.0.2.2
flutter run --dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=10.0.2.2
```

Firestore usa el puerto **8181** (el 8080 suele estar ocupado por Tomcat u Oracle). Los datos del emulador se
borran al cerrarlo. Cuenta de prueba usada en desarrollo: `demo@nido.test` / `nido-demo-2026` (créala con
"Crear una cuenta nueva"; solo existe en el emulador). En web con emulador la sesión no se guarda: hay que entrar
de nuevo tras recargar.

## Tests

```bash
flutter analyze
flutter test                      # importes, cálculo de patrimonio, saldos y objetivos
cd firestore-tests && npm install && npm test   # reglas de seguridad contra el emulador (requiere Java 11+)
```

## Estructura

```
lib/
  main.dart, app.dart          arranque, tema, localización, puerta de sesión
  core/money.dart              céntimos <-> texto en formato español
  models/                      Account, Movement, Goal, NetWorthSnapshot
  domain/portfolio.dart        lógica pura: totales, efecto en saldos, objetivos, flujo mensual
  data/nido_repository.dart    lecturas y escrituras en Firestore
  data/nido_store.dart         estado en vivo (listeners) para la interfaz
  data/auth_service.dart       login, registro y recuperación de contraseña
  ui/                          pantallas y widgets
firestore.rules                reglas de seguridad
firestore-tests/               tests de las reglas
```

## Modelo de datos

Todo cuelga de `users/{uid}`, así que cada usuario solo ve lo suyo:

| Colección | Campos |
|---|---|
| `accounts` | `name`, `type`, `institution`, `balanceCents`, `createdAt`, `updatedAt` |
| `movements` | `kind` (income/expense/transfer), `amountCents`, `accountId`, `toAccountId`, `category`, `note`, `date` |
| `goals` | `name`, `targetCents`, `savedCents`, `accountIds[]`, `deadline` |
| `snapshots/{yyyy-MM}` | `assetsCents`, `liabilitiesCents` (una foto por mes para la gráfica) |

Decisiones clave:

- **Importes en céntimos enteros**, nunca `double`.
- **Las deudas guardan lo que se debe en positivo.** Un gasto con tarjeta la aumenta y una transferencia hacia
  ella la reduce.
- **Los saldos se ajustan con `FieldValue.increment` en el mismo batch que el movimiento.** Si dos dispositivos
  registran gastos a la vez sin conexión, al sincronizar se suman los dos en lugar de pisarse.
- **La foto mensual solo se escribe con datos confirmados por el servidor**, para que un dispositivo recién
  instalado (con la caché vacía) no la sobrescriba con ceros.
- **Las reglas validan tipos, rangos y campos permitidos**, fijan `createdAt` y exigen `updatedAt` = hora del
  servidor.

## Pendiente / ideas

- Google Sign-In en Android y web (en Windows no lo soporta FlutterFire; ahí se mantiene correo/contraseña).
- Actualización automática del valor de inversiones con una Cloud Function programada.
- Movimientos recurrentes, presupuestos por categoría e importación de extractos CSV/Excel.
- Exportar datos y borrar la cuenta desde Ajustes (requiere una Cloud Function que borre las subcolecciones).
- Bloqueo con huella/PIN y App Check.
- Volver a añadir tests del repositorio con `fake_cloud_firestore` cuando sea compatible con
  `cloud_firestore` ≥ 6.7. Se verificaron con 6.6.0, pero la app usa 6.10 por sus arreglos en Windows.
