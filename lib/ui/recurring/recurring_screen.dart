import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/nido_store.dart';
import '../../domain/recurrence_engine.dart';
import '../../models/movement.dart';
import '../../models/recurrence.dart';
import '../privacy.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/crt.dart';
import 'recurring_forms.dart';

final _day = DateFormat('d MMM', 'es_ES');
final _monthYear = DateFormat('MMM y', 'es_ES');
final _pct = NumberFormat.percentPattern('es_ES');
final _rate = NumberFormat('0.00', 'es_ES');
// El símbolo del euro y el espacio (no separable) que lo precede.
final _euro = RegExp(r'\s*€');

String recurrenceName(Recurrence r) => r.note.isEmpty ? categoryOf(r.kind, r.category).label : r.note;

/// Pestaña Recurrentes: suscripciones, plazos y el resto de programaciones.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    if (!store.recurrencesLoaded) return const Loading();
    final all = store.recurrences;
    if (all.isEmpty) {
      return PageBody(children: [
        EmptyState(
          icon: Icons.event_repeat,
          title: 'Nada programado todavía',
          message: 'Nómina, alquiler, suscripciones, la cuota de la hipoteca… Prográmalo una vez y Nido lo apunta '
              'solo cada vez que toque. También desde la línea de comandos: cada mes 12,99 netflix día 14',
          action: FilledButton.icon(
            onPressed: () => openProgramChooser(context),
            icon: const Icon(Icons.add),
            label: const Text('PROGRAMAR'),
          ),
        ),
      ]);
    }

    int byName(Recurrence a, Recurrence b) => recurrenceName(a).compareTo(recurrenceName(b));
    final subs = all.where((r) => r.isSubscription).toList()..sort(byName);
    final plans = all.where((r) => r.isInstallment).toList()..sort(byName);
    final others = all.where((r) => !r.isSubscription && !r.isInstallment).toList()..sort(byName);
    final pending = store.toConfirm;
    final upcoming = store.upcoming(days: 30);
    final subsMonthly = subs.where((r) => nextOccurrence(r) != null).fold<int>(0, (s, r) => s + monthlyEquivalent(r.amountCents, r.frequency));

    return PageBody(children: [
      const _FixedSummary(),
      if (pending.isNotEmpty) ...[
        SectionHeader('Por confirmar · ${pending.length}'),
        _ConfirmList(pending),
      ],
      if (subs.isNotEmpty) ...[
        SectionHeader(
          'Suscripciones · ${subs.length}',
          trailing: Text('${context.money(subsMonthly)}/mes', style: mono(size: 14, weight: FontWeight.w700, color: Crt.amber)),
        ),
        Card(clipBehavior: Clip.antiAlias, child: Column(children: _divided([for (final r in subs) _SubscriptionTile(r)]))),
      ],
      if (plans.isNotEmpty) ...[
        SectionHeader('Plazos · ${plans.length}'),
        for (final p in plans) Padding(padding: const EdgeInsets.only(bottom: 12), child: _InstallmentCard(p)),
      ],
      if (others.isNotEmpty) ...[
        SectionHeader('Programaciones · ${others.length}'),
        Card(clipBehavior: Clip.antiAlias, child: Column(children: _divided([for (final r in others) _RecurrenceTile(r)]))),
      ],
      SectionHeader('Próximos 30 días · ${upcoming.length}'),
      if (upcoming.isEmpty)
        Text('Nada previsto en los próximos 30 días.', style: Theme.of(context).textTheme.bodySmall)
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [for (final u in upcoming.take(20)) UpcomingRow(u.r, u.date)]),
          ),
        ),
    ]);
  }
}

List<Widget> _divided(List<Widget> items) => [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) const Divider(indent: 72), items[i]],
    ];

/// Lo fijo al mes: gastos, ingresos, suscripciones al año y peso de las cuotas.
class _FixedSummary extends StatelessWidget {
  const _FixedSummary();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    var outMonthly = 0;
    var inMonthly = 0;
    var subsYearly = 0;
    var cuotas = 0;
    for (final r in store.recurrences.where((r) => nextOccurrence(r) != null)) {
      final monthly = monthlyEquivalent(amountPerOccurrence(r), r.frequency);
      if (r.isInstallment) {
        cuotas += monthly;
        outMonthly += monthly;
      } else if (r.kind == MovementKind.expense) {
        outMonthly += monthly;
        if (r.isSubscription) subsYearly += annualEquivalent(r.amountCents, r.frequency);
      } else if (r.kind == MovementKind.income) {
        inMonthly += monthly;
      }
    }
    final burden = store.debtBurden;

    Widget reading(String label, String value, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [Text(label, style: theme.textTheme.labelSmall), Text(value, style: crtReadout(34, color))],
        );

    return CrtScreen(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 28, runSpacing: 14, children: [
          reading('SALE CADA MES', context.money(outMonthly), Crt.redText),
          reading('ENTRA CADA MES', context.money(inMonthly), Crt.green),
          reading('SUSCRIPCIONES AL AÑO', context.money(subsYearly), Crt.amber),
        ]),
        if (cuotas > 0) ...[
          const SizedBox(height: 16),
          Text(
            burden == null
                ? 'Cuotas de préstamos: ${context.money(cuotas)} al mes.'
                : 'Cuotas de préstamos: ${context.money(cuotas)} al mes, el ${_pct.format(burden)} de lo que entra.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: burden == null ? Crt.offWhite : (burden > .35 ? Crt.redText : burden > .25 ? Crt.amber : Crt.green),
            ),
          ),
          if (burden != null) ...[
            const SizedBox(height: 6),
            LedBar(value: burden / .6, color: burden > .35 ? Crt.redText : burden > .25 ? Crt.amber : Crt.green, segments: 30),
            const SizedBox(height: 4),
            Text('Por encima del 35 % los bancos lo consideran un endeudamiento alto.', style: theme.textTheme.bodySmall),
          ],
        ],
      ]),
    );
  }
}

class _ConfirmList extends StatelessWidget {
  const _ConfirmList(this.items);

  final List<({Recurrence r, int index, DateTime date})> items;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NidoStore>();
    final theme = Theme.of(context);
    final seen = <String>{};
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final it in items)
          Builder(builder: (context) {
            // Se confirman en orden: solo la más antigua de cada programación.
            final first = seen.add(it.r.id);
            return ListTile(
              leading: const Icon(Icons.pending_actions, color: Crt.amber),
              title: Text(recurrenceName(it.r)),
              subtitle: Text('${_day.format(it.date).toUpperCase()} · ${context.money(amountPerOccurrence(it.r))}'),
              trailing: !first
                  ? Text('EN ESPERA', style: theme.textTheme.labelSmall)
                  : Wrap(spacing: 4, children: [
                      TextButton(
                        onPressed: () => store.skipOccurrence(it.r, it.index),
                        style: TextButton.styleFrom(foregroundColor: Crt.grey),
                        child: const Text('SALTAR'),
                      ),
                      FilledButton(
                        onPressed: () => store.confirmOccurrence(it.r, it.index),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                        child: const Text('APUNTAR'),
                      ),
                    ]),
            );
          }),
      ]),
    );
  }
}

/// Icono de cinta en bucle para las suscripciones.
class _LoopIcon extends StatelessWidget {
  const _LoopIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Crt.screen,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .7), width: 1.5),
      ),
      child: const TapeReels(width: 36, label: null, spinning: false),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile(this.r);

  final Recurrence r;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NidoStore>();
    final theme = Theme.of(context);
    final next = nextOccurrence(r);
    final account = store.accountsById[r.accountId]?.name ?? 'Cuenta eliminada';
    final previous = r.previousAmountCents;
    final rose = previous != null && previous > 0 && r.amountCents > previous;
    final change = rose ? (r.amountCents - previous) / previous : 0.0;
    return InkWell(
      onTap: () => openRecurrenceForm(context, recurrence: r, subscription: true),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          _LoopIcon(color: next == null ? Crt.grey : Crt.amber),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(recurrenceName(r), style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis),
              Text(
                [
                  r.frequency.label,
                  account,
                  next == null ? 'terminada' : 'próximo cargo ${_day.format(next)}',
                  if (!r.auto) 'con confirmación',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              if (rose) ...[
                const SizedBox(height: 4),
                StatusTag('▲ Subió ${_pct.format(change)} · antes ${context.money(previous)}', color: Crt.redText),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(context.money(r.amountCents), style: mono(size: 15, weight: FontWeight.w700, color: Crt.offWhite)),
            Text('${context.money(annualEquivalent(r.amountCents, r.frequency))}/año', style: mono(size: 12, color: Crt.grey)),
          ]),
        ]),
      ),
    );
  }
}

class _RecurrenceTile extends StatelessWidget {
  const _RecurrenceTile(this.r);

  final Recurrence r;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NidoStore>();
    final theme = Theme.of(context);
    final next = nextOccurrence(r);
    String name(String? id) => store.accountsById[id]?.name ?? 'Cuenta eliminada';
    final where = r.kind == MovementKind.transfer ? '${name(r.accountId)} → ${name(r.toAccountId)}' : name(r.accountId);
    final color = switch (r.kind) {
      MovementKind.income => Crt.green,
      MovementKind.expense => Crt.beige,
      MovementKind.transfer => Crt.amber,
    };
    final amount = switch (r.kind) {
      MovementKind.income => SignedAmount(r.amountCents),
      MovementKind.expense => SignedAmount(-r.amountCents),
      MovementKind.transfer => SignedAmount(r.amountCents, neutral: true),
    };
    return InkWell(
      onTap: () => openRecurrenceForm(context, recurrence: r),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Crt.screen,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: .6), width: 1.5),
            ),
            child: Icon(Icons.event_repeat, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(recurrenceName(r), style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                StatusTag(r.auto ? 'Auto' : 'Confirmar', color: r.auto ? Crt.green : Crt.amber),
              ]),
              Text(
                '${r.frequency.label} · $where · ${next == null ? 'terminada' : 'próximo ${_day.format(next)}'}',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const SizedBox(width: 12),
          amount,
        ]),
      ),
    );
  }
}

class _InstallmentCard extends StatelessWidget {
  const _InstallmentCard(this.p);

  final Recurrence p;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NidoStore>();
    final theme = Theme.of(context);
    final paid = p.nextIndex.clamp(0, p.months);
    final remaining = remainingAfter(p, paid);
    final interest = totalInterest(p);
    final rows = amortization(p.principalCents, p.rateBps, p.months);
    final interestPaid = rows.take(paid).fold<int>(0, (s, r) => s + r.interestCents);
    final done = paid >= p.months;
    final debt = store.accountsById[p.accountId];
    final pay = store.accountsById[p.payAccountId]?.name ?? 'cuenta eliminada';
    final last = occurrenceDate(p, p.months - 1);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openInstallmentForm(context, plan: p),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(recurrenceName(p).toUpperCase(), style: theme.textTheme.titleLarge?.copyWith(color: Crt.offWhite)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    StatusTag(done ? 'Pagado' : 'Cuota ${paid + 1} de ${p.months}', color: done ? Crt.green : Crt.amber),
                    StatusTag('TIN ${_rate.format(p.rateBps / 100)} %', color: Crt.beige),
                    if (!p.auto) const StatusTag('Confirmar', color: Crt.amber),
                  ]),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('CUOTA', style: theme.textTheme.labelSmall),
                Text(context.money(amountPerOccurrence(p)), style: crtReadout(30, Crt.amber)),
              ]),
            ]),
            const SizedBox(height: 14),
            LedBar(value: p.principalCents == 0 ? 0 : 1 - remaining / p.principalCents, color: Crt.green, segments: 36, height: 10),
            const SizedBox(height: 6),
            Row(children: [
              Text('PAGADO ${context.money(p.principalCents - remaining)}', style: mono(size: 12, color: Crt.green)),
              const Spacer(),
              Text('PENDIENTE ${context.money(remaining)}', style: mono(size: 12, color: Crt.redText)),
            ]),
            const SizedBox(height: 12),
            _Line(Icons.flag_outlined, done ? 'Terminado' : 'Última cuota: ${_monthYear.format(last)}'),
            _Line(Icons.percent, 'Intereses: ${context.money(interestPaid)} pagados de ${context.money(interest)} en total'),
            _Line(Icons.account_balance_outlined, 'Se paga desde $pay${debt == null ? '' : ' · deuda en "${debt.name}"'}'),
            if (debt != null && (debt.balanceCents - remaining).abs() > 100)
              _Line(Icons.info_outline,
                  'La cuenta de deuda marca ${context.money(debt.balanceCents)}; el plan, ${context.money(remaining)}.'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => showForm<void>(context, _AmortizationTable(p)),
                icon: const Icon(Icons.table_rows_outlined),
                label: const Text('VER CUADRO'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Crt.beige),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

/// Cuadro de amortización completo, con la próxima cuota resaltada.
const _rowHeight = 22.0;

class _AmortizationTable extends StatelessWidget {
  const _AmortizationTable(this.p);

  final Recurrence p;

  @override
  Widget build(BuildContext context) {
    final rows = amortization(p.principalCents, p.rateBps, p.months);
    final head = mono(size: 11, weight: FontWeight.w700, color: Crt.beige);
    Widget cell(String s, TextStyle st, {int flex = 3}) =>
        Expanded(flex: flex, child: Text(s, style: st, textAlign: TextAlign.right));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BackTitle('Cuadro · ${recurrenceName(p)}', cursor: false),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: Text('Nº', style: head)),
            cell('FECHA', head, flex: 4),
            cell('CUOTA', head),
            cell('INTERÉS', head),
            cell('CAPITAL', head),
            cell('PENDIENTE', head, flex: 4),
          ]),
          const Divider(height: 12),
          Expanded(
            child: ListView.builder(
              // Filas de alto fijo: se abre colocado en la próxima cuota.
              itemExtent: _rowHeight,
              controller: ScrollController(
                initialScrollOffset: ((p.nextIndex - 3).clamp(0, rows.length) * _rowHeight).toDouble(),
              ),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                final isNext = i == p.nextIndex;
                final color = i < p.nextIndex ? Crt.grey : (isNext ? Crt.amber : Crt.offWhite);
                final st = mono(size: 11, color: color, weight: isNext ? FontWeight.w700 : FontWeight.w500);
                return Container(
                  color: isNext ? Crt.amberDeep : null,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(flex: 2, child: Text('${i + 1}', style: st)),
                    cell(DateFormat('MM/yy').format(occurrenceDate(p, i)), st, flex: 4),
                    cell(context.money(row.paymentCents).replaceAll(_euro, ''), st),
                    cell(context.money(row.interestCents).replaceAll(_euro, ''), st),
                    cell(context.money(row.principalCents).replaceAll(_euro, ''), st),
                    cell(context.money(row.remainingCents).replaceAll(_euro, ''), st, flex: 4),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR')),
          ),
        ]),
      ),
    );
  }
}

/// Fila de "próximos cargos" (también se usa en el resumen).
class UpcomingRow extends StatelessWidget {
  const UpcomingRow(this.r, this.date, {super.key});

  final Recurrence r;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = amountPerOccurrence(r);
    final Widget value = r.isInstallment || r.kind == MovementKind.expense
        ? SignedAmount(-amount, size: 13)
        : r.kind == MovementKind.income
            ? SignedAmount(amount, size: 13)
            : SignedAmount(amount, size: 13, neutral: true);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        SizedBox(width: 60, child: Text(_day.format(date).toUpperCase(), style: mono(size: 12, color: Crt.grey))),
        Icon(
          r.isInstallment ? Icons.request_quote_outlined : (r.isSubscription ? Icons.subscriptions_outlined : Icons.event_repeat),
          size: 18,
          color: Crt.beige,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(recurrenceName(r), style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
        value,
      ]),
    );
  }
}
