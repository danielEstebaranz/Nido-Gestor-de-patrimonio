import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/nido_store.dart';
import '../../domain/portfolio.dart';
import '../../models/account.dart';
import '../../models/movement.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/crt.dart';
import '../privacy.dart';

final _monthFormat = DateFormat('MMMM y', 'es_ES');
final _dayFormat = DateFormat("EEEE d 'de' MMMM", 'es_ES');
final _shortDate = DateFormat('d MMM y', 'es_ES');
final _pct = NumberFormat.percentPattern('es_ES');

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Importe de un movimiento con su signo: ingreso +, gasto −, transferencia neutra.
Widget movementAmount(Movement m, {double size = 15}) => switch (m.kind) {
      MovementKind.income => SignedAmount(m.amountCents, size: size),
      MovementKind.expense => SignedAmount(-m.amountCents, size: size),
      MovementKind.transfer => SignedAmount(m.amountCents, size: size, neutral: true),
    };

/// Barra LED de una categoría de gasto con su importe y su peso.
class CategoryBar extends StatelessWidget {
  const CategoryBar({super.key, required this.category, required this.cents, required this.total});

  final Category category;
  final int cents;
  final int total;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : cents / total;
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(category.icon, size: 18, color: Crt.beige),
        const SizedBox(width: 8),
        Expanded(child: Text(category.label.toUpperCase(), style: theme.textTheme.bodyMedium)),
        Text(_pct.format(share), style: mono(size: 12, color: Crt.grey)),
        const SizedBox(width: 12),
        Text(context.money(cents), style: mono(size: 14, weight: FontWeight.w700, color: Crt.offWhite)),
      ]),
      const SizedBox(height: 6),
      LedBar(value: share, color: share >= .3 ? Crt.amber : Crt.green, segments: 32, height: 8),
    ]);
  }
}

class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  MovementKind? _filter;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    final flow = store.flow;
    final now = DateTime.now();
    final isCurrentMonth = store.month.year == now.year && store.month.month == now.month;
    final shown = store.movements.where((m) => _filter == null || m.kind == _filter).toList();
    final categories = expensesByCategory(store.movements).take(5).toList();

    final byDay = <DateTime, List<Movement>>{};
    for (final m in shown) {
      byDay.putIfAbsent(DateTime(m.date.year, m.date.month, m.date.day), () => []).add(m);
    }

    final monthSwitch = CrtScreen(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 16),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: 'Mes anterior',
            icon: const Icon(Icons.chevron_left, color: Crt.green),
            onPressed: () => store.selectMonth(DateTime(store.month.year, store.month.month - 1)),
          ),
          Expanded(
            child: Text(
              _monthFormat.format(store.month).toUpperCase(),
              textAlign: TextAlign.center,
              style: crtReadout(34, Crt.green),
            ),
          ),
          IconButton(
            tooltip: 'Mes siguiente',
            icon: Icon(Icons.chevron_right, color: isCurrentMonth ? Crt.border : Crt.green),
            onPressed: isCurrentMonth ? null : () => store.selectMonth(DateTime(store.month.year, store.month.month + 1)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _FlowItem('Ingresos', flow.incomeCents),
          _FlowItem('Gastos', -flow.expenseCents),
          _FlowItem('Balance', flow.balanceCents),
        ]),
      ]),
    );

    return PageBody(maxWidth: 900, children: [
      monthSwitch,
      if (categories.isNotEmpty) ...[
        const SizedBox(height: 16),
        Panel(
          title: 'En qué se va el dinero',
          child: Column(children: [
            for (final c in categories) ...[
              CategoryBar(category: categoryOf(MovementKind.expense, c.key), cents: c.value, total: flow.expenseCents),
              const SizedBox(height: 12),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (label, kind) in const [
          ('Todo', null),
          ('Gastos', MovementKind.expense),
          ('Ingresos', MovementKind.income),
          ('Transferencias', MovementKind.transfer),
        ])
          ChoiceChip(
            label: Text(label.toUpperCase()),
            selected: _filter == kind,
            onSelected: (_) => setState(() => _filter = kind),
          ),
      ]),
      if (!store.movementsLoaded)
        const Loading()
      else if (shown.isEmpty)
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: store.movements.isEmpty ? 'Sin movimientos este mes' : 'Nada con este filtro',
          message: store.movements.isEmpty
              ? 'Registra ingresos, gastos o transferencias entre tus cuentas y los saldos se ajustarán solos.'
              : 'Prueba con otro tipo de movimiento.',
          action: store.movements.isEmpty
              ? FilledButton.icon(
                  onPressed: () => openMovementForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('NUEVO MOVIMIENTO'),
                )
              : null,
        )
      else
        for (final entry in byDay.entries) ...[
          SectionHeader(
            capitalize(_dayFormat.format(entry.key)),
            trailing: _DayTotal(entry.value),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < entry.value.length; i++) ...[
                if (i > 0) const Divider(indent: 68),
                _MovementTile(entry.value[i]),
              ],
            ]),
          ),
        ],
      if (store.movementsLoaded && shown.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text('Desliza un movimiento a la izquierda para borrarlo.',
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ),
    ]);
  }
}

class _FlowItem extends StatelessWidget {
  const _FlowItem(this.label, this.cents);

  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        FittedBox(child: SignedAmount(cents, size: 17)),
      ]),
    );
  }
}

class _DayTotal extends StatelessWidget {
  const _DayTotal(this.items);

  final List<Movement> items;

  @override
  Widget build(BuildContext context) {
    final flow = monthFlow(items);
    if (flow.incomeCents == 0 && flow.expenseCents == 0) return const SizedBox.shrink();
    return SignedAmount(flow.balanceCents, size: 13);
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile(this.m);

  final Movement m;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NidoStore>();
    final theme = Theme.of(context);
    final category = categoryOf(m.kind, m.category);
    String accountName(String? id) => store.accountsById[id]?.name ?? 'Cuenta eliminada';
    final where = m.kind == MovementKind.transfer
        ? '${accountName(m.accountId)} → ${accountName(m.toAccountId)}'
        : accountName(m.accountId);
    final color = switch (m.kind) {
      MovementKind.income => Crt.green,
      MovementKind.expense => Crt.beige,
      MovementKind.transfer => Crt.amber,
    };

    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Crt.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('BORRAR', style: TextStyle(color: Crt.offWhite, fontSize: 20)),
          SizedBox(width: 8),
          Icon(Icons.delete_outline, color: Crt.offWhite),
        ]),
      ),
      confirmDismiss: (_) => confirm(context,
          title: 'Eliminar movimiento', message: 'Se revertirá su efecto en el saldo de las cuentas.'),
      onDismissed: (_) => store.run(store.repo.deleteMovement(m, store.accountsById)),
      child: InkWell(
        onTap: () => openMovementForm(context, movement: m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Crt.screen,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: .6), width: 1.5),
              ),
              child: Icon(category.icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.note.isEmpty ? category.label : m.note, style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis),
                Text(m.note.isEmpty ? where : '${category.label} · $where',
                    style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 12),
            movementAmount(m),
          ]),
        ),
      ),
    );
  }
}

void openMovementForm(BuildContext context, {Movement? movement}) {
  if (context.read<NidoStore>().accounts.isEmpty) {
    showMessage('Crea primero una cuenta en la pestaña Cuentas.');
    return;
  }
  showForm<void>(context, MovementForm(movement: movement));
}

class MovementForm extends StatefulWidget {
  const MovementForm({super.key, this.movement});

  final Movement? movement;

  @override
  State<MovementForm> createState() => _MovementFormState();
}

class _MovementFormState extends State<MovementForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.movement == null ? '' : centsToInput(widget.movement!.amountCents),
  );
  late final _note = TextEditingController(text: widget.movement?.note);
  late MovementKind _kind = widget.movement?.kind ?? MovementKind.expense;
  late String? _accountId = widget.movement?.accountId;
  late String? _toAccountId = widget.movement?.toAccountId;
  late String _category = widget.movement?.category ?? categoriesFor(_kind).first.id;
  late DateTime _date = widget.movement?.date ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final accounts = context.read<NidoStore>().accounts;
    // Si la cuenta original ya no existe, obliga a elegir otra.
    final ids = accounts.map((a) => a.id).toSet();
    // Por defecto, una cuenta de liquidez (de donde sale el día a día).
    if (!ids.contains(_accountId)) {
      _accountId = (accounts.where((a) => a.group == AccountGroup.liquidity).firstOrNull ?? accounts.first).id;
    }
    if (!ids.contains(_toAccountId)) _toAccountId = null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setKind(MovementKind kind) => setState(() {
        _kind = kind;
        if (!categoriesFor(kind).any((c) => c.id == _category)) _category = categoriesFor(kind).first.id;
      });

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<NidoStore>();
    final movement = Movement(
      id: widget.movement?.id ?? '',
      kind: _kind,
      amountCents: parseCents(_amount.text)!,
      accountId: _accountId!,
      toAccountId: _kind == MovementKind.transfer ? _toAccountId : null,
      category: _category,
      note: _note.text.trim(),
      date: _date,
    );
    final before = widget.movement;
    store.run(before == null
        ? store.repo.addMovement(movement, store.accountsById)
        : store.repo.updateMovement(before, movement, store.accountsById));
    Navigator.pop(context);
    showMessage(before == null ? '${_kind.label} de ${context.moneyOnce(movement.amountCents)} registrado.' : 'Movimiento guardado.');
  }

  Future<void> _delete() async {
    final store = context.read<NidoStore>();
    final ok = await confirm(context,
        title: 'Eliminar movimiento', message: 'Se revertirá su efecto en el saldo de las cuentas.');
    if (!ok || !mounted) return;
    store.run(store.repo.deleteMovement(widget.movement!, store.accountsById));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<NidoStore>().accounts;
    final accountItems = [
      for (final a in accounts)
        DropdownMenuItem(
          value: a.id,
          child: Row(children: [
            Icon(a.type.icon, size: 20, color: a.isLiability ? Crt.redText : Crt.green),
            const SizedBox(width: 12),
            Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
          ]),
        ),
    ];
    final transfer = _kind == MovementKind.transfer;

    return Form(
      key: _formKey,
      child: FormFrame(
        title: widget.movement == null ? 'Nuevo movimiento' : 'Editar movimiento',
        onSave: _save,
        onDelete: widget.movement == null ? null : _delete,
        children: [
          SegmentedButton<MovementKind>(
            segments: [
              for (final k in MovementKind.values) ButtonSegment(value: k, label: Text(k.shortLabel.toUpperCase())),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _setKind(s.first),
          ),
          MoneyField(controller: _amount, label: 'Importe', allowZero: false, autofocus: widget.movement == null),
          LabeledField(
            label: transfer ? 'Desde' : 'Cuenta',
            child: DropdownButtonFormField<String>(
              initialValue: _accountId,
              isExpanded: true,
              dropdownColor: Crt.panelHigh,
              items: accountItems,
              onChanged: (v) => setState(() => _accountId = v),
            ),
          ),
          if (transfer)
            LabeledField(
              label: 'Hacia',
              hint: 'Para pagar una deuda (tarjeta, préstamo, hipoteca) haz una transferencia hacia ella.',
              child: DropdownButtonFormField<String>(
                initialValue: _toAccountId,
                isExpanded: true,
                dropdownColor: Crt.panelHigh,
                items: accountItems,
                onChanged: (v) => setState(() => _toAccountId = v),
                validator: (v) {
                  if (v == null) return 'Elige la cuenta de destino';
                  if (v == _accountId) return 'Debe ser otra cuenta';
                  return null;
                },
              ),
            )
          else
            LabeledField(
              label: 'Categoría',
              child: DropdownButtonFormField<String>(
                key: ValueKey(_kind),
                initialValue: _category,
                isExpanded: true,
                dropdownColor: Crt.panelHigh,
                items: [
                  for (final c in categoriesFor(_kind))
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(children: [Icon(c.icon, size: 20, color: Crt.beige), const SizedBox(width: 12), Text(c.label)]),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
            ),
          LabeledField(
            label: 'Fecha',
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(_shortDate.format(_date).toUpperCase(), style: mono(size: 15, color: Crt.green)),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), alignment: Alignment.centerLeft),
            ),
          ),
          LabeledField(
            label: 'Concepto (opcional)',
            child: TextFormField(
              controller: _note,
              decoration: const InputDecoration(hintText: 'Ej.: Mercadona'),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
            ),
          ),
        ],
      ),
    );
  }
}
