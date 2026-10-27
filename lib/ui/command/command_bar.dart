import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/nido_store.dart';
import '../../domain/command_parser.dart';
import '../../domain/recurrence_engine.dart';
import '../../models/movement.dart';
import '../../models/recurrence.dart';
import '../privacy.dart';
import '../theme.dart';
import '../widgets/crt.dart';

final _day = DateFormat('d MMM', 'es_ES');

const _examples = [
  'gasto 12,50 café',
  'gasto 54,30 mercadona tarjeta',
  'ingreso 2400 nómina',
  'traspaso 300 nómina > fondo',
  'ayer 30 gasolina',
  'cada mes 12,99 netflix día 14',
  'ir objetivos',
  'ocultar',
];

/// Abre la línea de comandos (Ctrl+K o /): apuntar gastos escribiendo.
Future<void> openCommandBar(BuildContext context, {void Function(int tab)? onNavigate}) {
  final store = context.read<NidoStore>();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar línea de comandos',
    barrierColor: Colors.black.withValues(alpha: .55),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => ChangeNotifierProvider<NidoStore>.value(
      value: store,
      child: _CommandBar(onNavigate: onNavigate),
    ),
    // Entrada: fundido y desplazamiento, como pide el sistema de diseño.
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -.04), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

class _LogLine {
  const _LogLine(this.input, this.output, this.ok);
  final String input;
  final String output;
  final bool ok;
}

class _CommandBar extends StatefulWidget {
  const _CommandBar({this.onNavigate});

  final void Function(int tab)? onNavigate;

  @override
  State<_CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<_CommandBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _log = <_LogLine>[];
  CommandResult _result = const EmptyCommand();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _parse(String text) {
    final store = context.read<NidoStore>();
    setState(() => _result = parseCommand(text, accounts: store.accounts, now: DateTime.now()));
  }

  void _insert(String example) {
    _controller.text = example;
    _controller.selection = TextSelection.collapsed(offset: example.length);
    _parse(example);
    _focus.requestFocus();
  }

  void _submit() {
    final input = _controller.text.trim();
    final store = context.read<NidoStore>();
    switch (_result) {
      case EmptyCommand():
        return;
      case HelpCommand():
        setState(() => _log.add(_LogLine(input, 'Prueba uno de los ejemplos de abajo.', true)));
      case CommandError(:final message):
        setState(() => _log.add(_LogLine(input, message, false)));
        return;
      case NavigateCommand(:final tab):
        Navigator.of(context).pop();
        widget.onNavigate?.call(tab);
        return;
      case PrivacyCommand(:final hide):
        PrivacyScope.maybeOf(context, listen: false)?.setHidden(hide);
        setState(() => _log.add(_LogLine(input, hide ? 'Importes ocultos.' : 'Importes visibles.', true)));
      case final RecurrenceCommand rc:
        final m = rc.movement;
        final start = firstOccurrenceFrom(DateTime.now(), rc.frequency, rc.day);
        store.run(store.repo.createRecurrence(Recurrence(
          id: '',
          type: RecurrenceType.movement,
          frequency: rc.frequency,
          startDate: start,
          accountId: m.account.id,
          kind: m.kind,
          amountCents: m.amountCents,
          toAccountId: m.to?.id,
          category: m.category,
          note: m.note.isEmpty ? categoryOf(m.kind, m.category).label : m.note,
        )));
        setState(() => _log.add(_LogLine(
            input, 'Programado ${rc.frequency.every} · primer cargo ${_day.format(start)}', true)));
      case final MovementCommand m:
        store.run(store.repo.addMovement(m.toMovement(), store.accountsById));
        final where = m.to == null ? m.account.name : '${m.account.name} → ${m.to!.name}';
        setState(() => _log.add(_LogLine(input, '${m.kind.label} de ${context.moneyOnce(m.amountCents)} · $where', true)));
    }
    _controller.clear();
    _parse('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, width >= 600 ? 72 : 16, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Material(
              color: Colors.transparent,
              child: CrtScreen(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Text('NIDO // LÍNEA DE COMANDOS', style: theme.textTheme.labelSmall?.copyWith(color: Crt.green)),
                    const Spacer(),
                    const _Keycap('ESC'),
                    const SizedBox(width: 6),
                    Text('cerrar', style: theme.textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 10),
                  for (final line in _log.reversed.take(5).toList().reversed) _LogView(line),
                  Row(children: [
                    Text('>', style: crtReadout(28, Crt.green)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        autofocus: true,
                        onChanged: _parse,
                        onSubmitted: (_) => _submit(),
                        textInputAction: TextInputAction.send,
                        cursorColor: Crt.green,
                        cursorWidth: 10,
                        style: mono(size: 18, weight: FontWeight.w700, color: Crt.green).copyWith(shadows: glow(Crt.green, blur: 4)),
                        decoration: InputDecoration(
                          hintText: 'gasto 12,50 café',
                          hintStyle: mono(size: 18, color: Crt.green.withValues(alpha: .25)),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ]),
                  const Divider(color: Crt.border, height: 18),
                  _Preview(_result),
                  const SizedBox(height: 14),
                  Text('EJEMPLOS', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in _examples)
                      ActionChip(
                        label: Text(e, style: mono(size: 12, color: Crt.offWhite)),
                        onPressed: () => _insert(e),
                      ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cómo ha entendido Nido lo escrito, antes de pulsar Intro.
class _Preview extends StatelessWidget {
  const _Preview(this.result);

  final CommandResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget hint(String text, {Color color = Crt.grey}) =>
        Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color));
    return switch (result) {
      EmptyCommand() || HelpCommand() => hint(
          'Escribe qué ha pasado y pulsa Intro. Nido deduce la categoría por el concepto '
          '(mercadona, gasolina, netflix…) y la cuenta por su nombre.',
        ),
      CommandError(:final message) => hint('ERR: $message', color: Crt.redText),
      NavigateCommand(:final tab) =>
        hint('INTRO: ir a ${const ['Resumen', 'Cuentas', 'Movimientos', 'Recurrentes', 'Objetivos'][tab]}', color: Crt.amber),
      PrivacyCommand(:final hide) => hint('INTRO: ${hide ? 'ocultar' : 'mostrar'} los importes', color: Crt.amber),
      final MovementCommand m => _MovementPreview(m),
      final RecurrenceCommand rc => _MovementPreview(
          rc.movement,
          repeat: '${rc.frequency.label} · primer cargo ${_day.format(firstOccurrenceFrom(DateTime.now(), rc.frequency, rc.day))}',
        ),
    };
  }
}

class _MovementPreview extends StatelessWidget {
  const _MovementPreview(this.m, {this.repeat});

  final MovementCommand m;

  /// Si es una programación: cada cuánto y el primer cargo.
  final String? repeat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final isToday = m.date.year == today.year && m.date.month == today.month && m.date.day == today.day;
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday = m.date.year == yesterday.year && m.date.month == yesterday.month && m.date.day == yesterday.day;
    final category = categoryOf(m.kind, m.category);
    final color = switch (m.kind) {
      MovementKind.income => Crt.green,
      MovementKind.expense => Crt.redText,
      MovementKind.transfer => Crt.amber,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        StatusTag(m.kind.label, color: color),
        Text(context.money(m.amountCents), style: mono(size: 16, weight: FontWeight.w700, color: color)),
        _Field(category.icon, m.kind == MovementKind.transfer ? 'Traspaso' : category.label),
        _Field(m.account.type.icon, m.to == null ? m.account.name : '${m.account.name} → ${m.to!.name}'),
        if (repeat != null)
          _Field(Icons.event_repeat, repeat!)
        else
          _Field(Icons.event_outlined, isToday ? 'Hoy' : isYesterday ? 'Ayer' : _day.format(m.date)),
        if (m.note.isNotEmpty) _Field(Icons.notes, '«${m.note}»'),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        const _Keycap('INTRO'),
        const SizedBox(width: 8),
        Text(repeat == null ? 'para guardarlo' : 'para programarlo', style: theme.textTheme.bodySmall),
      ]),
    ]);
  }
}

class _Field extends StatelessWidget {
  const _Field(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: Crt.beige),
      const SizedBox(width: 4),
      Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ]);
  }
}

class _LogView extends StatelessWidget {
  const _LogView(this.line);

  final _LogLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('> ${line.input}', style: mono(size: 13, color: Crt.grey)),
        Text(
          '${line.ok ? 'OK' : 'ERR'} · ${line.output}',
          style: mono(size: 13, weight: FontWeight.w700, color: line.ok ? Crt.green : Crt.redText),
        ),
      ]),
    );
  }
}

/// Tecla dibujada como una tecla física.
class _Keycap extends StatelessWidget {
  const _Keycap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Crt.panelHigh,
        borderRadius: BorderRadius.circular(4),
        border: const Border(
          top: BorderSide(color: Crt.border),
          left: BorderSide(color: Crt.border),
          right: BorderSide(color: Crt.border),
          bottom: BorderSide(color: Crt.border, width: 3),
        ),
      ),
      child: Text(label, style: mono(size: 11, weight: FontWeight.w700, color: Crt.offWhite)),
    );
  }
}
