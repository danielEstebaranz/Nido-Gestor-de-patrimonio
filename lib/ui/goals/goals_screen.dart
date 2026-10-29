import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/nido_store.dart';
import '../../domain/portfolio.dart';
import '../../models/goal.dart';
import '../theme.dart';
import '../widgets/account_item.dart';
import '../widgets/common.dart';
import '../widgets/crt.dart';
import '../widgets/tape.dart';
import '../privacy.dart';

final _date = DateFormat('d MMM y', 'es_ES');
final _monthYear = DateFormat('MMM y', 'es_ES');
final _pct = NumberFormat.percentPattern('es_ES');

Color _statusColor(GoalStatus s) => switch (s) {
      GoalStatus.done => Crt.green,
      GoalStatus.onTrack => Crt.amber,
      GoalStatus.late => Crt.redText,
      GoalStatus.open => Crt.beige,
    };

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    if (store.goals.isEmpty) {
      return PageBody(children: [
        EmptyState(
          icon: Icons.flag_outlined,
          title: 'Define tu primer objetivo',
          message: 'Un fondo de emergencia, la entrada de un piso, un viaje… '
              'Vincúlalo a tus cuentas de ahorro y Nido medirá el progreso solo.',
          action: FilledButton.icon(
            onPressed: () => openGoalForm(context),
            icon: const Icon(Icons.add),
            label: const Text('CREAR OBJETIVO'),
          ),
        ),
      ]);
    }

    final now = DateTime.now();
    var saved = 0;
    var target = 0;
    var done = 0;
    for (final g in store.goals) {
      final p = goalProgressCents(g, store.accountsById);
      final t = store.goalTarget(g);
      saved += p.clamp(0, t);
      target += t;
      if (goalStatus(g, p, now, target: t) == GoalStatus.done) done++;
    }

    return PageBody(children: [
      CrtScreen(
        padding: const EdgeInsets.all(20),
        child: Wrap(spacing: 32, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('AHORRADO PARA TUS METAS', style: theme.textTheme.labelSmall),
            Text(context.money(saved), style: crtReadout(44, Crt.amber)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('DE UN TOTAL DE', style: theme.textTheme.labelSmall),
            Text(context.money(target), style: mono(size: 18, weight: FontWeight.w700, color: Crt.offWhite)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('CONSEGUIDOS', style: theme.textTheme.labelSmall),
            Text('$done / ${store.goals.length}', style: mono(size: 18, weight: FontWeight.w700, color: Crt.green)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth >= 760 ? 2 : 1;
        final w = (c.maxWidth - 16 * (perRow - 1)) / perRow;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          for (final g in store.goals) SizedBox(width: w, child: HoverLift(scale: 1.015, child: GoalCard(g))),
        ]);
      }),
    ]);
  }
}

/// Tarjeta completa de un objetivo: una cinta de casete cuya cinta pasa de la
/// bobina izquierda a la derecha según lo ahorrado.
class GoalCard extends StatelessWidget {
  const GoalCard(this.goal, {super.key});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final now = DateTime.now();
    final progress = goalProgressCents(goal, store.accountsById);
    final target = store.goalTarget(goal);
    final ratio = target > 0 ? progress / target : 0.0;
    final status = goalStatus(goal, progress, now, target: target);
    final monthly = monthlyNeededCents(goal, progress, now, target: target);
    final reference = store.spending;
    final linked = goal.accountIds.where(store.accountsById.containsKey).map((id) => store.accountsById[id]!.name);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openGoalForm(context, goal: goal),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LayoutBuilder(
              builder: (context, c) => Center(
                child: CassetteTape(
                  progress: ratio,
                  title: goal.name,
                  stripe: _statusColor(status),
                  side: status == GoalStatus.done ? 'B' : 'A',
                  // Contador de cinta de tres cifras: el porcentaje.
                  counter: (ratio * 100).clamp(0, 999).round().toString().padLeft(3, '0'),
                  width: c.maxWidth.clamp(200, 380),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  StatusTag(status.label, color: _statusColor(status)),
                  if (goal.sample) const StatusTag('Ejemplo', color: Crt.grey),
                ]),
              ),
              Text(_pct.format(ratio.clamp(0, 9.99)), style: crtReadout(30, _statusColor(status))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text(context.money(progress), style: mono(size: 17, weight: FontWeight.w700, color: Crt.green)),
              Text('  /  ${context.money(target)}', style: mono(size: 14, color: Crt.grey)),
            ]),
            const SizedBox(height: 12),
            if (goal.isDynamic)
              _Detail(
                Icons.autorenew,
                reference == null
                    ? 'Dinámico: ${goal.targetMonths} meses de gasto. Aún no hay gastos para calcularlo; se usa el último importe.'
                    : 'Dinámico: ${goal.targetMonths} meses × ${context.money(reference.totalCents)} de gasto al mes '
                        '(${context.money(reference.fixedCents)} fijo + ${context.money(reference.variableCents)} variable). '
                        'Se recalcula solo.',
              ),
            _Detail(Icons.link, goal.isLinked ? 'Mide: ${linked.isEmpty ? 'cuentas eliminadas' : linked.join(', ')}' : 'Ahorro anotado a mano'),
            if (goal.deadline != null) _Detail(Icons.event_outlined, 'Fecha límite: ${_date.format(goal.deadline!)}'),
            if (monthly != null) _Detail(Icons.speed, 'Necesitas ${context.money(monthly)} al mes para llegar a tiempo'),
            if (!goal.isLinked && status != GoalStatus.done)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showForm<void>(context, _ContributionForm(goal)),
                  icon: const Icon(Icons.add),
                  label: const Text('APORTAR'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.icon, this.text);

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

/// Una parte del gasto de referencia en el panel del objetivo dinámico.
class _SpendingLine extends StatelessWidget {
  const _SpendingLine(this.label, this.cents, this.source);

  final String label;
  final int cents;
  final String source;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 74, child: Text(label.toUpperCase(), style: mono(size: 12, color: Crt.amber))),
        SizedBox(
          width: 96,
          child: Text(context.money(cents), style: mono(size: 13, weight: FontWeight.w700, color: Crt.offWhite)),
        ),
        Expanded(child: Text(source, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

/// Fila compacta para el resumen.
class GoalProgressRow extends StatelessWidget {
  const GoalProgressRow({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    final progress = goalProgressCents(goal, store.accountsById);
    final target = store.goalTarget(goal);
    final ratio = target > 0 ? progress / target : 0.0;
    final status = goalStatus(goal, progress, DateTime.now(), target: target);
    return InkWell(
      onTap: () => openGoalForm(context, goal: goal),
      borderRadius: BorderRadius.circular(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(goal.name.toUpperCase(), style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis)),
          Text(_pct.format(ratio.clamp(0, 9.99)), style: mono(size: 14, weight: FontWeight.w700, color: _statusColor(status))),
        ]),
        const SizedBox(height: 6),
        LedBar(value: ratio, color: _statusColor(status), segments: 28, height: 8),
        const SizedBox(height: 4),
        Text(
          [
            '${context.money(progress)} de ${context.money(target)}${goal.isDynamic ? ' (dinámico)' : ''}',
            if (goal.deadline != null) 'para ${_monthYear.format(goal.deadline!)}',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
      ]),
    );
  }
}

class _ContributionForm extends StatefulWidget {
  const _ContributionForm(this.goal);

  final Goal goal;

  @override
  State<_ContributionForm> createState() => _ContributionFormState();
}

class _ContributionFormState extends State<_ContributionForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: FormFrame(
        title: 'Aportar a "${widget.goal.name}"',
        onSave: () {
          if (!_formKey.currentState!.validate()) return;
          final store = context.read<NidoStore>();
          final cents = parseCents(_amount.text)!;
          store.run(store.repo.contributeToGoal(widget.goal.id, cents));
          Navigator.pop(context);
          showMessage('${context.moneyOnce(cents)} anotados en "${widget.goal.name}".');
        },
        children: [
          MoneyField(
            controller: _amount,
            label: 'Importe',
            hint: 'En negativo para retirar dinero del objetivo.',
            allowNegative: true,
            allowZero: false,
            autofocus: true,
          ),
        ],
      ),
    );
  }
}

void openGoalForm(BuildContext context, {Goal? goal}) => showForm<void>(context, GoalForm(goal: goal));

class GoalForm extends StatefulWidget {
  const GoalForm({super.key, this.goal});

  final Goal? goal;

  @override
  State<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<GoalForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.goal?.name);
  late final _target = TextEditingController(
    text: widget.goal == null ? '' : centsToInput(widget.goal!.targetCents),
  );
  late final _saved = TextEditingController(text: centsToInput(widget.goal?.savedCents ?? 0));
  late final Set<String> _accountIds = {...?widget.goal?.accountIds};
  late DateTime? _deadline = widget.goal?.deadline;

  /// Meses de gasto del objetivo dinámico; null = importe fijo.
  late int? _months = widget.goal?.targetMonths;

  /// Un objetivo llamado "fondo de emergencia" o "colchón" propone el modo dinámico.
  bool get _looksLikeEmergency {
    final n = _name.text.toLowerCase();
    return n.contains('emergencia') || n.contains('colch') || n.contains('imprevistos');
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 50),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<NidoStore>();
    final name = _name.text.trim();
    final dynamicTarget = _months == null ? null : _dynamicTarget(store);
    final target = dynamicTarget ?? parseCents(_target.text)!;
    final saved = parseCents(_saved.text) ?? 0;
    final accountIds = _accountIds.where(store.accountsById.containsKey).toList();
    final existing = widget.goal;
    store.run(existing == null
        ? store.repo.createGoal(
            name: name, targetCents: target, savedCents: saved, accountIds: accountIds, deadline: _deadline,
            targetMonths: _months)
        : store.repo.updateGoal(existing.id,
            name: name, targetCents: target, savedCents: saved, accountIds: accountIds, deadline: _deadline,
            targetMonths: _months));
    Navigator.pop(context);
    showMessage(existing == null ? 'Objetivo "$name" creado.' : 'Objetivo "$name" guardado.');
  }

  /// Importe recomendado hoy para [_months] meses, o null si no hay datos de gasto.
  int? _dynamicTarget(NidoStore store) {
    final ref = store.referenceSpending;
    return ref == null || _months == null ? null : recommendedEmergencyFund(ref, _months!);
  }

  Widget _dynamicPanel(BuildContext context, NidoStore store) {
    final theme = Theme.of(context);
    final spending = store.spending;
    final ref = spending?.totalCents;
    final on = _months != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: on,
        activeThumbColor: Crt.green,
        onChanged: ref == null && !on ? null : (v) => setState(() => _months = v ? 6 : null),
        title: const Text('IMPORTE SEGÚN TUS GASTOS'),
        subtitle: Text(ref == null
            ? 'Disponible cuando haya gastos registrados o programados.'
            : 'El objetivo se recalcula solo: tantos meses de lo que te cuesta vivir.'),
      ),
      if (on && spending != null && ref != null)
        CrtScreen(
          tint: Crt.amber,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('RECOMENDADO HOY', style: theme.textTheme.labelSmall),
            Text(context.money(recommendedEmergencyFund(ref, _months!)), style: crtReadout(34, Crt.amber)),
            Text(
              '$_months meses × ${context.money(ref)} al mes',
              style: theme.textTheme.bodySmall?.copyWith(color: Crt.offWhite),
            ),
            const SizedBox(height: 6),
            _SpendingLine('Fijo', spending.fixedCents, 'suscripciones, recibos y cuotas de Recurrentes'),
            _SpendingLine(
              'Variable',
              spending.variableCents,
              switch (spending.months) {
                0 => 'lo apuntado este mes, a falta de un mes completo',
                1 => 'lo que apuntaste el mes pasado',
                final n => 'media de lo que apuntaste en los últimos $n meses',
              },
            ),
            Slider(
              value: _months!.toDouble(),
              min: 3,
              max: 12,
              divisions: 9,
              label: '$_months meses',
              activeColor: Crt.amber,
              inactiveColor: Crt.amberDeep,
              onChanged: (v) => setState(() => _months = v.round()),
            ),
            Text(
              switch (_months!) {
                < 4 => 'Mínimo razonable si tus ingresos son muy estables.',
                < 7 => 'Lo habitual: entre 3 y 6 meses.',
                _ => 'Prudente si eres autónomo, tienes ingresos variables o personas a tu cargo.',
              },
              style: theme.textTheme.bodySmall,
            ),
          ]),
        ),
    ]);
  }

  Future<void> _delete() async {
    final store = context.read<NidoStore>();
    final ok = await confirm(context, title: 'Eliminar objetivo', message: 'No afecta a tus cuentas.');
    if (!ok || !mounted) return;
    store.run(store.repo.deleteGoal(widget.goal!.id));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final assets = context.watch<NidoStore>().accounts.where((a) => !a.isLiability).toList();
    return Form(
      key: _formKey,
      child: FormFrame(
        title: widget.goal == null ? 'Nuevo objetivo' : 'Editar objetivo',
        onSave: _save,
        onDelete: widget.goal == null ? null : _delete,
        children: [
          LabeledField(
            label: 'Nombre',
            child: TextFormField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'Ej.: Fondo de emergencia'),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              validator: requiredText,
            ),
          ),
          if (_months == null) MoneyField(controller: _target, label: 'Importe objetivo', allowZero: false),
          if (_months != null || _looksLikeEmergency || widget.goal == null) _dynamicPanel(context, context.watch<NidoStore>()),
          LabeledField(
            label: 'Fecha límite (opcional)',
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDeadline,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _deadline == null ? 'SIN FECHA' : _date.format(_deadline!).toUpperCase(),
                    style: mono(size: 15, color: Crt.green),
                  ),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), alignment: Alignment.centerLeft),
                ),
              ),
              if (_deadline != null)
                IconButton(
                  tooltip: 'Quitar fecha',
                  onPressed: () => setState(() => _deadline = null),
                  icon: const Icon(Icons.close),
                ),
            ]),
          ),
          if (assets.isNotEmpty)
            LabeledField(
              label: 'Medir con el saldo de',
              hint: 'Si eliges cuentas, el progreso es su saldo. Si no, anotas tú lo ahorrado.',
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in assets)
                  FilterChip(
                    label: Text(accountLabel(context, a, assets).toUpperCase()),
                    selected: _accountIds.contains(a.id),
                    onSelected: (v) => setState(() => v ? _accountIds.add(a.id) : _accountIds.remove(a.id)),
                  ),
              ]),
            ),
          if (_accountIds.isEmpty) MoneyField(controller: _saved, label: 'Ya ahorrado'),
        ],
      ),
    );
  }
}
