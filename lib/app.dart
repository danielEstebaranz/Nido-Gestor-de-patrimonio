import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/auth_service.dart';
import 'data/nido_repository.dart';
import 'data/nido_store.dart';
import 'ui/auth/login_screen.dart';
import 'ui/home_shell.dart';
import 'ui/privacy.dart';
import 'ui/theme.dart';
import 'ui/widgets/common.dart';
import 'ui/widgets/crt.dart';

class NidoApp extends StatelessWidget {
  const NidoApp({super.key, required this.privacy});

  final PrivacyController privacy;

  @override
  Widget build(BuildContext context) {
    // Por encima de MaterialApp para que los diálogos también oculten importes.
    return PrivacyScope(
      controller: privacy,
      child: Provider<AuthService>(
        create: (_) => AuthService(FirebaseAuth.instance),
        child: const _NidoMaterialApp(home: AuthGate()),
      ),
    );
  }
}

class _NidoMaterialApp extends StatelessWidget {
  const _NidoMaterialApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nido',
      debugShowCheckedModeBanner: false,
      // Cassette futurism es solo oscuro (.claude/skills/design).
      theme: nidoTheme(),
      themeMode: ThemeMode.dark,
      builder: (context, child) => CrtOverlay(child: child ?? const SizedBox.shrink()),
      scaffoldMessengerKey: messengerKey,
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );
  }
}

/// Muestra el login o, con sesión iniciada, la app con los datos de ese usuario.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<User?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return ChangeNotifierProvider<NidoStore>(
          key: ValueKey(user.uid),
          create: (_) => NidoStore(
            NidoRepository(FirebaseFirestore.instance, user.uid),
            onError: (e) => showMessage(firestoreErrorMessage(e)),
          ),
          child: const HomeShell(),
        );
      },
    );
  }
}

/// Se muestra si Firebase no arranca, normalmente porque falta `flutterfire configure`.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return _NidoMaterialApp(
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const NidoWordmark(size: 40),
                  const SizedBox(height: 24),
                  const PromptLabel('Falta conectar Firebase', cursor: true, color: Crt.amber),
                  const SizedBox(height: 12),
                  const Text(
                    'Ejecuta "flutterfire configure" en la carpeta del proyecto y vuelve a abrir la app. '
                    'Los pasos están en el README.',
                  ),
                  const SizedBox(height: 16),
                  Text('$error', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
