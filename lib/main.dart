import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'ui/privacy.dart';

/// `flutter run --dart-define=USE_EMULATOR=true` usa los emuladores locales de
/// Firebase (ver README) en lugar del proyecto real.
const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

/// En el emulador de Android, el ordenador anfitrión es 10.0.2.2.
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

const _emulatorOptions = FirebaseOptions(
  apiKey: 'demo-key',
  appId: '1:000000000000:web:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-nido',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'es_ES';
  await initializeDateFormatting('es_ES');

  try {
    await Firebase.initializeApp(
      options: _useEmulator ? _emulatorOptions : DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    runApp(ConfigErrorApp(error: e));
    return;
  }

  if (_useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    // En web, una sesión guardada se restauraría contra Google antes de
    // conectar el emulador; sin persistencia hay que entrar en cada recarga.
    if (kIsWeb) await FirebaseAuth.instance.setPersistence(Persistence.NONE);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8181);
    debugPrint('Nido: usando emuladores en $_emulatorHost');
  }

  // Caché local: la app funciona sin conexión y sincroniza al recuperarla.
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: !(_useEmulator && kIsWeb),
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  final privacy = await PrivacyController.load();
  runApp(NidoApp(privacy: privacy));
}
