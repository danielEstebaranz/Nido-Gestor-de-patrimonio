import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/nido_store.dart';
import 'accounts/accounts_screen.dart';
import 'command/command_bar.dart';
import 'goals/goals_screen.dart';
import 'movements/movements_screen.dart';
import 'recurring/recurring_forms.dart';
import 'recurring/recurring_screen.dart';
import 'settings_screen.dart';
import 'summary/summary_screen.dart';
import 'privacy.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/crt.dart';
import 'widgets/tape.dart';

class _Section {
  const _Section(this.label, this.icon, this.page, {this.fab});

  final String label;
  final IconData icon;
  final Widget page;
  final ({String label, void Function(BuildContext) onPressed})? fab;
}

/// Navegación inferior en móvil y lateral en pantallas anchas (escritorio, tablet).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final _sections = <_Section>[
    _Section('Resumen', Icons.space_dashboard_outlined, SummaryScreen(onNavigate: _go)),
    _Section('Cuentas', Icons.account_balance_wallet_outlined, const AccountsScreen(),
        fab: (label: 'CUENTA', onPressed: openAccountForm)),
    _Section('Movimientos', Icons.swap_vert, const MovementsScreen(),
        fab: (label: 'MOVIMIENTO', onPressed: openMovementForm)),
    _Section('Recurrentes', Icons.event_repeat, const RecurringScreen(),
        fab: (label: 'PROGRAMAR', onPressed: openProgramChooser)),
    _Section('Objetivos', Icons.flag_outlined, const GoalsScreen(),
        fab: (label: 'OBJETIVO', onPressed: openGoalForm)),
  ];

  void _go(int index) => setState(() => _index = index);

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(store: context.read<NidoStore>()),
      ));

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    final section = _sections[_index];
    final fab = section.fab;
    final theme = Theme.of(context);

    // Al cambiar de pestaña, un salto de imagen VHS.
    final body = VhsGlitch(
      trigger: _index,
      child: IndexedStack(index: _index, children: [for (final s in _sections) s.page]),
    );

    final scaffold = Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: wide ? 24 : 12,
        title: Row(children: [
          if (!wide) ...[const NidoLogo(size: 26), const SizedBox(width: 10)],
          Text('> ', style: theme.appBarTheme.titleTextStyle?.copyWith(color: Crt.beige, shadows: const [])),
          // Si no cabe junto a los botones, el título se encoge en lugar de
          // pintarse por debajo de ellos.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(section.label.toUpperCase()),
            ),
          ),
          const SizedBox(width: 6),
          const BlinkingCursor(size: 22),
        ]),
        // En móvil los botones van más juntos para dejar sitio al título.
        actions: [
          if (wide) const Padding(padding: EdgeInsets.only(right: 8), child: _SyncBadge()) else const _SyncLed(compact: true),
          IconButton(
            tooltip: 'Línea de comandos (Ctrl+K)',
            visualDensity: wide ? null : VisualDensity.compact,
            icon: const Icon(Icons.terminal),
            onPressed: () => openCommandBar(context, onNavigate: _go),
          ),
          _PrivacyButton(compact: !wide),
          IconButton(
            tooltip: 'Ajustes',
            visualDensity: wide ? null : VisualDensity.compact,
            icon: const Icon(Icons.tune),
            onPressed: _openSettings,
          ),
          SizedBox(width: wide ? 8 : 4),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(2), child: Divider(height: 2, thickness: 2, color: Crt.border)),
      ),
      floatingActionButton: fab == null
          ? null
          : FloatingActionButton.extended(
              key: ValueKey(fab.label),
              onPressed: () => fab.onPressed(context),
              icon: const Icon(Icons.add),
              label: Text(fab.label),
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _go,
              height: 70,
              destinations: [
                for (final s in _sections) NavigationDestination(icon: Icon(s.icon), label: s.label),
              ],
            ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _go,
                extended: width >= 1200,
                minExtendedWidth: 210,
                labelType: width >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: width >= 1200 ? const NidoWordmark(size: 30) : const NidoLogo(size: 40),
                ),
                trailingAtBottom: true,
                trailing: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _RailDeck(extended: width >= 1200),
                ),
                destinations: [
                  for (final s in _sections)
                    NavigationRailDestination(icon: Icon(s.icon), label: Text(s.label.toUpperCase())),
                ],
              ),
              const VerticalDivider(width: 2, thickness: 2, color: Crt.border),
              Expanded(child: body),
            ])
          : body,
    );

    // Atajos de escritorio: Ctrl+K o / abren la línea de comandos; 1-4, pestañas.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => openCommandBar(context, onNavigate: _go),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => openCommandBar(context, onNavigate: _go),
        const CharacterActivator('/'): () => openCommandBar(context, onNavigate: _go),
        const SingleActivator(LogicalKeyboardKey.digit1): () => _go(0),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _go(2),
        const SingleActivator(LogicalKeyboardKey.digit4): () => _go(3),
        const SingleActivator(LogicalKeyboardKey.digit5): () => _go(4),
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }
}

/// El ojo: oculta o muestra saldos e importes en toda la app.
class _PrivacyButton extends StatelessWidget {
  const _PrivacyButton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final privacy = PrivacyScope.maybeOf(context);
    final hidden = privacy?.hidden ?? false;
    return IconButton(
      tooltip: hidden ? 'Mostrar importes' : 'Ocultar importes',
      onPressed: privacy?.toggle,
      isSelected: hidden,
      visualDensity: compact ? VisualDensity.compact : null,
      // Oculto en ámbar, para que se vea de un vistazo que el modo está activo.
      icon: const Icon(Icons.visibility_outlined),
      selectedIcon: Icon(Icons.visibility_off_outlined, color: Crt.amber, shadows: glow(Crt.amber, blur: 6)),
    );
  }
}

final _clock = DateFormat('HH:mm', 'es_ES');

/// Texto y color del estado de sincronización.
({String label, String detail, Color color}) syncInfo(NidoStore store) {
  final last = store.lastSyncedAt == null ? '' : ' Última confirmación: ${_clock.format(store.lastSyncedAt!)}.';
  final n = store.pendingWrites;
  final cambios = n == 1 ? '1 cambio' : '$n cambios';
  final seEnvia = switch (n) {
    0 => 'lo que apuntes se enviará',
    1 => '1 cambio se enviará',
    _ => '$n cambios se enviarán',
  };
  return switch (store.syncState) {
    SyncState.synced => (
        label: 'Sincronizado',
        detail: 'Todo está guardado en el servidor y en tus otros dispositivos.$last',
        color: Crt.green,
      ),
    SyncState.syncing => (
        label: 'Grabando $n',
        detail: 'Enviando $cambios al servidor.',
        color: Crt.amber,
      ),
    SyncState.offline => (
        label: n == 0 ? 'Sin conexión' : 'Sin conexión · $n en cola',
        detail: 'Sin conexión. Puedes seguir usando Nido: $seEnvia al volver la red.$last',
        color: Crt.redText,
      ),
  };
}

/// Indicador de escritorio: estado real de sincronización y si hay ejemplos.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final info = syncInfo(store);
    return Tooltip(
      message: info.detail,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (store.hasSampleData) ...[const StatusTag('Datos de ejemplo', color: Crt.amber), const SizedBox(width: 8)],
        if (store.syncState == SyncState.offline) ...[const RecLed(), const SizedBox(width: 8)],
        if (store.syncState == SyncState.syncing) ...[
          const TapeReels(width: 40, label: null),
          const SizedBox(width: 8),
        ],
        StatusTag(info.label, color: info.color),
      ]),
    );
  }
}

/// Indicador de móvil: un LED (verde fijo; ámbar o rojo parpadeando).
class _SyncLed extends StatelessWidget {
  const _SyncLed({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final info = syncInfo(store);
    return IconButton(
      tooltip: info.label,
      onPressed: () => showMessage(info.detail),
      visualDensity: compact ? VisualDensity.compact : null,
      icon: store.syncState == SyncState.synced
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Crt.green,
                boxShadow: [BoxShadow(color: Crt.green.withValues(alpha: .6), blurRadius: 6)],
              ),
            )
          : RecLed(label: null, color: info.color),
    );
  }
}

/// Pletina del menú lateral: las bobinas giran solo cuando hay datos en tránsito.
class _RailDeck extends StatelessWidget {
  const _RailDeck({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final info = syncInfo(store);
    final offline = store.syncState == SyncState.offline;
    // Rótulo corto: el menú lateral es estrecho y el REC ya dice "sin conexión".
    final label = switch (store.syncState) {
      SyncState.synced => 'SINCRONIZADO',
      SyncState.syncing => 'GRABANDO ${store.pendingWrites}',
      SyncState.offline => store.pendingWrites == 0 ? 'SIN CONEXIÓN' : 'EN COLA: ${store.pendingWrites}',
    };
    return Tooltip(
      message: info.detail,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (offline) ...[RecLed(label: extended ? 'REC' : null), const SizedBox(height: 8)],
        TapeReels(
          width: extended ? 96 : 56,
          spinning: store.syncState == SyncState.syncing,
          label: extended ? label : null,
          labelColor: info.color,
        ),
      ]),
    );
  }
}
