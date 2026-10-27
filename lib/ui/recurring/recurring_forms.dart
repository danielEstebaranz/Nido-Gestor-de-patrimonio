import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/nido_store.dart';
import '../../domain/recurrence_engine.dart';
import '../../models/account.dart';
import '../../models/movement.dart';
import '../../models/recurrence.dart';
import '../privacy.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/crt.dart';

final _date = DateFormat('d MMM y', 'es_ES');
final _monthYear = DateFormat('MMMM y', 'es_ES');

/// Elegir qué programar: suscripción, ingreso/gasto fijo o plazos.
void openProgramChooser(BuildContext context) {
  showForm<void>(
    context,
    _Chooser(
      onPick: (kind) {
        Navigator.of(context, rootNavigator: true).pop();
        switch (kind) {
          case 0:
            openRecurrenceForm(context, subscription: true);
          case 1:
            openRecurrenceForm(context);
          case _:
            openInstallmentForm(context);
        }
      },
    ),
  );
}

class _Chooser extends StatelessWidget {
  const _Chooser({required this.onPick});

  final void Function(int) onPick;

  @override
  Widget build(BuildContext context) {
    Widget option(int i, IconData icon, String title, String text) => Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(icon, color: Crt.green),
            title: Text(title.toUpperCase()),
            subtitle: Text(text),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onPick(i),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const BackTitle('Programar'),
        const SizedBox(height: 16),
        option(0, Icons.subscriptions_outlined, 'Suscripción', 'Netflix, Spotify, gimnasio, móvil… Cuánto te cuestan al año.'),
        const SizedBox(height: 10),
        option(1, Icons.event_repeat, 'Ingreso o gasto fijo', 'Nómina, alquiler, aportación al fondo, comunidad…'),
        const SizedBox(height: 10),
        option(2, Icons.request_quote_outlined, 'Préstamo o compra a plazos',
            'Hipoteca, préstamo, móvil a 12 meses… Con cuota, intereses y fecha de fin.'),
      ]),
    );
  }
}

/// Opción "apuntar solo / pedir confirmación".
class _AutoSwitch extends StatelessWidget {
  const _AutoSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: Crt.green,
      title: Text(value ? 'APUNTAR SOLO' : 'PEDIR CONFIRMACIÓN'),
      subtitle: Text(value
          ? 'Nido lo registra solo cada vez que toque.'
          : 'Nido te lo propone en Recurrentes y tú lo apuntas o lo saltas.'),
    );
  }
}

// ---------------------------------------------------------------- Ingresos, gastos y suscripciones

void openRecurrenceForm(BuildContext context, {Recurrence? recurrence, bool subscription = false}) {
  if (context.read<NidoStore>().accounts.isEmpty) {
    showMessage('Crea primero una cuenta en la pestaña Cuentas.');
    return;
  }
  showForm<void>(context, RecurrenceForm(recurrence: recurrence, subscription: subscription));
}

class RecurrenceForm extends StatefulWidget {
  const RecurrenceForm({super.key, this.recurrence, this.subscription = false});

  final Recurrence? recurrence;
  final bool subscription;

  @override
  State<RecurrenceForm> createState() => _RecurrenceFormState();
}

class _RecurrenceFormState extends State<RecurrenceForm> {
  final _formKey = GlobalKey<FormState>();
  late final Recurrence? _r = widget.recurrence;
  late final _name = TextEditingController(text: _r?.note);
  late final _amount = TextEditingController(text: _r == null ? '' : centsToInput(_r.amountCents));
  late final _count = TextEditingController(text: _r?.count?.toString() ?? '');
  late MovementKind _kind = _r?.kind ?? MovementKind.expense;
  late String _category = _r?.category ?? (widget.subscription ? 'subscriptions' : categoriesFor(_kind).first.id);
  late Frequency _frequency = _r?.frequency ?? Frequency.monthly;
  late DateTime _start = _r?.startDate ?? DateTime.now();
  late bool _auto = _r?.auto ?? true;
  String? _accountId;
  String? _toAccountId;

  @override
  void initState() {
    super.initState();
    final accounts = context.read<NidoStore>().accounts;
    final ids = accounts.map((a) => a.id).toSet();
    _accountId = ids.contains(_r?.accountId) ? _r!.accountId : _defaultAccount(accounts, _kind).id;
    _toAccountId = ids.contains(_r?.toAccountId) ? _r!.toAccountId : null;
  }

  Account _defaultAccount(List<Account> accounts, MovementKind kind) =>
      (widget.subscription ? accounts.where((a) => a.type == AccountType.creditCard).firstOrNull : null) ??
      accounts.where((a) => a.type == AccountType.bank).firstOrNull ??
      accounts.where((a) => a.group == AccountGroup.liquidity).firstOrNull ??
      accounts.first;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _start = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<NidoStore>();
    final draft = Recurrence(
      id: _r?.id ?? '',
      type: RecurrenceType.movement,
      frequency: _frequency,
      startDate: DateTime(_start.year, _start.month, _start.day),
      accountId: _accountId!,
      kind: _kind,
      amountCents: parseCents(_amount.text)!,
      toAccountId: _kind == MovementKind.transfer ? _toAccountId : null,
      category: _kind == MovementKind.transfer ? transferCategory.id : _category,
      note: _name.text.trim(),
      count: int.tryParse(_count.text.trim()),
      auto: _auto,
      nextIndex: _r?.nextIndex ?? 0,
    );
    if (_r == null) {
      // Lo anterior a hoy se da por hecho: solo se apunta desde hoy en adelante.
      final skipped = occurrencesBefore(draft, DateTime.now());
      store.run(store.repo.createRecurrence(_copyNext(draft, skipped)));
    } else {
      store.run(store.repo.updateRecurrence(_r, draft));
    }
    Navigator.pop(context);
    showMessage(_r == null ? '"${draft.note}" programado.' : '"${draft.note}" guardado.');
  }

  Future<void> _delete() async {
    final store = context.read<NidoStore>();
    final ok = await confirm(context,
        title: 'Eliminar "${_r!.note}"', message: 'Dejará de apuntarse. Los movimientos ya apuntados se conservan.');
    if (!ok || !mounted) return;
    store.run(store.repo.deleteRecurrence(_r.id));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<NidoStore>().accounts;
    final items = [
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
    final amount = parseCents(_amount.text);
    return Form(
      key: _formKey,
      child: FormFrame(
        title: _r == null ? (widget.subscription ? 'Nueva suscripción' : 'Nuevo fijo') : 'Editar programación',
        onSave: _save,
        onDelete: _r == null ? null : _delete,
        children: [
          SegmentedButton<MovementKind>(
            segments: [for (final k in MovementKind.values) ButtonSegment(value: k, label: Text(k.shortLabel.toUpperCase()))],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              if (!categoriesFor(_kind).any((c) => c.id == _category)) _category = categoriesFor(_kind).first.id;
            }),
          ),
          LabeledField(
            label: 'Nombre',
            child: TextFormField(
              controller: _name,
              decoration: InputDecoration(hintText: widget.subscription ? 'Ej.: Netflix' : 'Ej.: Nómina, Alquiler…'),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              validator: requiredText,
            ),
          ),
          MoneyField(controller: _amount, label: 'Importe de cada cargo', allowZero: false),
          LabeledField(
            label: transfer ? 'Desde' : 'Cuenta',
            child: DropdownButtonFormField<String>(
              initialValue: _accountId,
              isExpanded: true,
              dropdownColor: Crt.panelHigh,
              items: items,
              onChanged: (v) => setState(() => _accountId = v),
            ),
          ),
          if (transfer)
            LabeledField(
              label: 'Hacia',
              child: DropdownButtonFormField<String>(
                initialValue: _toAccountId,
                isExpanded: true,
                dropdownColor: Crt.panelHigh,
                items: items,
                onChanged: (v) => setState(() => _toAccountId = v),
                validator: (v) => v == null ? 'Elige la cuenta de destino' : (v == _accountId ? 'Debe ser otra cuenta' : null),
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
            label: 'Cada cuánto',
            hint: amount == null
                ? null
                : 'Equivale a ${context.money(monthlyEquivalent(amount, _frequency))} al mes · '
                    '${context.money(annualEquivalent(amount, _frequency))} al año.',
            child: SegmentedButton<Frequency>(
              segments: [for (final f in Frequency.values) ButtonSegment(value: f, label: Text(f.unit.toUpperCase()))],
              selected: {_frequency},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
          ),
          LabeledField(
            label: _r == null ? 'Primer cargo' : 'Fecha de referencia',
            hint: _r == null ? 'Si es anterior a hoy, lo pasado se da por apuntado.' : null,
            child: OutlinedButton.icon(
              onPressed: _pickStart,
              icon: const Icon(Icons.event_outlined),
              label: Text(_date.format(_start).toUpperCase(), style: mono(size: 15, color: Crt.green)),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), alignment: Alignment.centerLeft),
            ),
          ),
          LabeledField(
            label: 'Número de cargos (opcional)',
            hint: 'Déjalo vacío si no tiene fin.',
            child: TextFormField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Sin fin'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                return (n == null || n <= 0 || n > 10000) ? 'Escribe un número entero' : null;
              },
            ),
          ),
          _AutoSwitch(value: _auto, onChanged: (v) => setState(() => _auto = v)),
        ],
      ),
    );
  }
}

/// Repeticiones con fecha anterior a hoy (no se apuntan al crear).
int occurrencesBefore(Recurrence r, DateTime now) {
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  return occurrencesUpTo(r, yesterday);
}

Recurrence _copyNext(Recurrence r, int nextIndex) => Recurrence(
      id: r.id,
      type: r.type,
      frequency: r.frequency,
      startDate: r.startDate,
      accountId: r.accountId,
      kind: r.kind,
      amountCents: r.amountCents,
      previousAmountCents: r.previousAmountCents,
      toAccountId: r.toAccountId,
      category: r.category,
      note: r.note,
      count: r.count,
      endDate: r.endDate,
      nextIndex: nextIndex,
      auto: r.auto,
      principalCents: r.principalCents,
      rateBps: r.rateBps,
      months: r.months,
      payAccountId: r.payAccountId,
    );

// ---------------------------------------------------------------- Plazos

void openInstallmentForm(BuildContext context, {Recurrence? plan}) {
  if (!context.read<NidoStore>().accounts.any((a) => a.group == AccountGroup.liquidity)) {
    showMessage('Crea primero una cuenta corriente o de ahorro desde la que pagar las cuotas.');
    return;
  }
  showForm<void>(context, InstallmentForm(plan: plan));
}

const _newDebt = '__nueva__';

class InstallmentForm extends StatefulWidget {
  const InstallmentForm({super.key, this.plan});

  final Recurrence? plan;

  @override
  State<InstallmentForm> createState() => _InstallmentFormState();
}

class _InstallmentFormState extends State<InstallmentForm> {
  final _formKey = GlobalKey<FormState>();
  late final Recurrence? _p = widget.plan;
  late final _name = TextEditingController(text: _p?.note);
  late final _principal = TextEditingController(text: _p == null ? '' : centsToInput(_p.principalCents));
  late final _rate = TextEditingController(text: _p == null ? '' : centsToInput(_p.rateBps));
  late final _months = TextEditingController(text: _p?.months.toString() ?? '');
  late DateTime _first = _p?.startDate ?? DateTime.now();
  late bool _auto = _p?.auto ?? true;
  late String _debtId;
  late String _payId;
  AccountType _newType = AccountType.loan;

  @override
  void initState() {
    super.initState();
    final accounts = context.read<NidoStore>().accounts;
    final debts = accounts.where((a) => a.isLiability).map((a) => a.id).toSet();
    _debtId = debts.contains(_p?.accountId) ? _p!.accountId : _newDebt;
    final liquid = accounts.where((a) => a.group == AccountGroup.liquidity).toList();
    _payId = liquid.any((a) => a.id == _p?.payAccountId)
        ? _p!.payAccountId!
        : (liquid.where((a) => a.type == AccountType.bank).firstOrNull ?? liquid.first).id;
  }

  @override
  void dispose() {
    _name.dispose();
    _principal.dispose();
    _rate.dispose();
    _months.dispose();
    super.dispose();
  }

  void _template(String name, int rateBps, int months, AccountType type) => setState(() {
        if (_name.text.trim().isEmpty) _name.text = name;
        _rate.text = centsToInput(rateBps);
        _months.text = '$months';
        _newType = type;
      });

  Future<void> _pickFirst() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _first,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _first = picked);
  }

  Recurrence? _draft() {
    final principal = parseCents(_principal.text);
    final rate = parseCents(_rate.text);
    final months = int.tryParse(_months.text.trim());
    if (principal == null || principal <= 0 || rate == null || rate < 0 || months == null || months <= 0) return null;
    return Recurrence(
      id: _p?.id ?? '',
      type: RecurrenceType.installment,
      frequency: Frequency.monthly,
      startDate: DateTime(_first.year, _first.month, _first.day),
      accountId: _debtId == _newDebt ? '' : _debtId,
      note: _name.text.trim(),
      principalCents: principal,
      rateBps: rate,
      months: months,
      payAccountId: _payId,
      auto: _auto,
      nextIndex: _p?.nextIndex ?? 0,
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<NidoStore>();
    final draft = _draft()!;
    if (_p == null) {
      // Las cuotas anteriores a hoy se dan por pagadas.
      final paid = occurrencesBefore(draft, DateTime.now());
      final plan = _copyNext(draft, paid);
      store.run(_debtId == _newDebt
          ? store.repo.createInstallment(plan,
              newDebtName: draft.note, debtType: _newType, debtBalanceCents: remainingAfter(plan, paid))
          : store.repo.createInstallment(plan));
    } else {
      store.run(store.repo.updateRecurrence(_p, draft));
    }
    Navigator.pop(context);
    showMessage(_p == null ? 'Plan "${draft.note}" creado.' : 'Plan "${draft.note}" guardado.');
  }

  Future<void> _delete() async {
    final store = context.read<NidoStore>();
    final ok = await confirm(context,
        title: 'Eliminar plan "${_p!.note}"',
        message: 'Dejarán de apuntarse las cuotas. La cuenta de la deuda y las cuotas ya apuntadas se conservan.');
    if (!ok || !mounted) return;
    store.run(store.repo.deleteRecurrence(_p.id));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = context.watch<NidoStore>().accounts;
    final debts = accounts.where((a) => a.isLiability).toList();
    final liquid = accounts.where((a) => a.group == AccountGroup.liquidity).toList();
    final draft = _draft();
    final paid = draft == null || _p != null ? (_p?.nextIndex ?? 0) : occurrencesBefore(draft, DateTime.now());

    return Form(
      key: _formKey,
      child: FormFrame(
        title: _p == null ? 'Préstamo o plazos' : 'Editar plan',
        onSave: _save,
        onDelete: _p == null ? null : _delete,
        children: [
          if (_p == null)
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                label: const Text('COMPRA A PLAZOS · 0 % · 12 MESES'),
                onPressed: () => _template('Compra a plazos', 0, 12, AccountType.loan),
              ),
              ActionChip(
                label: const Text('PRÉSTAMO PERSONAL · 7,95 % · 5 AÑOS'),
                onPressed: () => _template('Préstamo personal', 795, 60, AccountType.loan),
              ),
              ActionChip(
                label: const Text('HIPOTECA · 2,10 % · 30 AÑOS'),
                onPressed: () => _template('Hipoteca', 210, 360, AccountType.mortgage),
              ),
            ]),
          LabeledField(
            label: 'Nombre',
            child: TextFormField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'Ej.: Portátil a plazos, Hipoteca…'),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              validator: requiredText,
              onChanged: (_) => setState(() {}),
            ),
          ),
          LabeledField(
            label: 'Cuenta de la deuda',
            child: DropdownButtonFormField<String>(
              initialValue: _debtId,
              isExpanded: true,
              dropdownColor: Crt.panelHigh,
              items: [
                const DropdownMenuItem(
                  value: _newDebt,
                  child: Row(children: [Icon(Icons.add, size: 20, color: Crt.amber), SizedBox(width: 12), Text('Crear una deuda nueva')]),
                ),
                for (final a in debts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Row(children: [
                      Icon(a.type.icon, size: 20, color: Crt.redText),
                      const SizedBox(width: 12),
                      Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
              ],
              onChanged: _p != null ? null : (v) => setState(() => _debtId = v ?? _debtId),
            ),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: MoneyField(controller: _principal, label: 'Importe prestado', allowZero: false)),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: LabeledField(
                label: 'TIN %',
                child: TextFormField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '0,00', suffixText: '%'),
                  style: mono(size: 16, weight: FontWeight.w700, color: Crt.amber),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final b = parseCents(v ?? '');
                    return (b == null || b < 0 || b > 10000) ? 'Entre 0 y 100' : null;
                  },
                ),
              ),
            ),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: LabeledField(
                label: 'Plazo (meses)',
                child: TextFormField(
                  controller: _months,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '12'),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    return (n == null || n <= 0 || n > 600) ? 'Entre 1 y 600' : null;
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Primera cuota',
                child: OutlinedButton(
                  onPressed: _pickFirst,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: Text(_date.format(_first).toUpperCase(), style: mono(size: 14, color: Crt.green)),
                ),
              ),
            ),
          ]),
          LabeledField(
            label: 'Se paga desde',
            child: DropdownButtonFormField<String>(
              initialValue: _payId,
              isExpanded: true,
              dropdownColor: Crt.panelHigh,
              items: [
                for (final a in liquid)
                  DropdownMenuItem(
                    value: a.id,
                    child: Row(children: [Icon(a.type.icon, size: 20, color: Crt.green), const SizedBox(width: 12), Text(a.name)]),
                  ),
              ],
              onChanged: (v) => setState(() => _payId = v ?? _payId),
            ),
          ),
          if (draft != null)
            CrtScreen(
              tint: Crt.amber,
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('CUOTA', style: theme.textTheme.labelSmall),
                Text('${context.money(amountPerOccurrence(draft))}/mes', style: crtReadout(32, Crt.amber)),
                const SizedBox(height: 6),
                Text(
                  'Intereses totales: ${context.money(totalInterest(draft))} · '
                  'última cuota: ${_monthYear.format(occurrenceDate(draft, draft.months - 1))}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Crt.offWhite),
                ),
                if (_p == null && paid > 0)
                  Text(
                    '$paid cuota${paid == 1 ? '' : 's'} anterior${paid == 1 ? '' : 'es'} a hoy se dan por pagadas. '
                    'Quedan ${context.money(remainingAfter(draft, paid))} por pagar.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Crt.amber),
                  ),
                if (_debtId != _newDebt && _p == null)
                  Text('El saldo de la cuenta de deuda no se toca: las próximas cuotas lo irán bajando.',
                      style: theme.textTheme.bodySmall),
              ]),
            ),
          _AutoSwitch(value: _auto, onChanged: (v) => setState(() => _auto = v)),
        ],
      ),
    );
  }
}
