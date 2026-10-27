import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth_service.dart';
import '../data/nido_store.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/crt.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  /// Esta pantalla se abre en el navegador raíz, fuera del Provider de la sesión.
  final NidoStore store;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final email = auth.currentUser?.email ?? '';
    final theme = Theme.of(context);
    return Scaffold(
      // Sin flecha de Material: el "<" del título es el botón de volver.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: BackTitle('Ajustes', style: theme.appBarTheme.titleTextStyle, cursor: false),
      ),
      body: PageBody(maxWidth: 680, children: [
        Panel(
          title: 'Sesión',
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(email, style: mono(size: 15, color: Crt.green)),
              subtitle: const Text('Cuenta con la que se sincronizan tus datos'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_reset),
              title: const Text('Cambiar contraseña'),
              subtitle: const Text('Te enviamos un enlace por correo'),
              onTap: () async {
                try {
                  await auth.sendPasswordReset(email);
                  showMessage('Correo enviado a $email');
                } catch (e) {
                  showMessage(authErrorMessage(e));
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout, color: Crt.redText),
              title: const Text('Cerrar sesión'),
              onTap: () async {
                Navigator.of(context).popUntil((r) => r.isFirst);
                await auth.signOut();
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => Panel(
            title: 'Datos de ejemplo',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                store.hasSampleData
                    ? 'Tienes cargado el hogar de ejemplo. Quítalo para quedarte solo con lo tuyo.'
                    : store.accounts.isEmpty
                        ? 'Carga un hogar de ejemplo para ver Nido funcionando. Se quita con un botón.'
                        : 'Los ejemplos solo se pueden cargar con la app vacía, para no mezclarlos con tus datos.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: store.sampleBusy
                    ? const TapeReels(width: 80, label: 'GRABANDO')
                    : store.hasSampleData
                        ? OutlinedButton(onPressed: store.removeSampleData, child: const Text('QUITAR EJEMPLOS'))
                        : FilledButton(
                            onPressed: store.accounts.isEmpty ? store.loadSampleData : null,
                            child: const Text('CARGAR EJEMPLOS'),
                          ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Sincronización',
          child: Text(
            'Tus datos se guardan en tu cuenta de Firebase y se actualizan al instante en todos tus '
            'dispositivos. Sin conexión puedes seguir usando Nido: los cambios se envían al reconectar.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 24),
        const Center(child: TapeReels(width: 110, label: 'NIDO v1.1 // LADO B')),
      ]),
    );
  }
}
