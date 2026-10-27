import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/nido_store.dart';
import '../../domain/portfolio.dart';
import '../../models/account.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/crt.dart';
import '../privacy.dart';

final _pct = NumberFormat.percentPattern('es_ES');

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    if (!store.accountsLoaded) return const Loading();
    if (store.accounts.isEmpty) {
      return PageBody(children: [
        EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Sin cuentas todavía',
          message: 'Cuentas bancarias, inversiones, inmuebles o deudas: todo lo que forma tu patrimonio.',
          action: FilledButton.icon(
            onPressed: () => openAccountForm(context),
            icon: const Icon(Icons.add),
            label: const Text('AÑADIR CUENTA'),
          ),
        ),
        const _QuickAdd(),
      ]);
    }

    final totals = store.totals;
    final groups = groupTotals(store.accounts);
    final children = <Widget>[_CompositionPanel(totals: totals, groups: groups)];
    for (final g in AccountGroup.values) {
      final list = store.accounts.where((a) => a.group == g).toList()
        ..sort((a, b) => b.balanceCents.compareTo(a.balanceCents));
      if (list.isEmpty) continue;
      final share = g == AccountGroup.debts || totals.assetsCents == 0 ? null : groups[g]! / totals.assetsCents;
      children.add(SectionHeader(
        '${g.label} · ${list.length}',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (share != null) ...[Text(_pct.format(share), style: mono(size: 13, color: Crt.grey)), const SizedBox(width: 12)],
          Text(
            g == AccountGroup.debts ? '−${context.money(groups[g]!)}' : context.money(groups[g]!),
            style: mono(size: 15, weight: FontWeight.w700, color: context.nido.group(g)),
          ),
        ]),
      ));
      children.add(_AccountGroupCard(list, group: g));
    }
    children.add(const SizedBox(height: 8));
    children.add(const _QuickAdd());
    return PageBody(children: children);
  }
}

class _CompositionPanel extends StatelessWidget {
  const _CompositionPanel({required this.totals, required this.groups});

  final PortfolioTotals totals;
  final Map<AccountGroup, int> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.nido;
    final assetGroups = AccountGroup.values.where((g) => g != AccountGroup.debts && groups[g]! > 0).toList();
    return CrtScreen(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 28, runSpacing: 12, children: [
          _Reading('Activos', context.money(totals.assetsCents), Crt.green),
          _Reading('Deudas', '−${context.money(totals.liabilitiesCents)}', Crt.redText),
          _Reading('Neto', context.money(totals.netWorthCents), totals.netWorthCents < 0 ? Crt.redText : Crt.amber),
        ]),
        if (assetGroups.isNotEmpty) ...[
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 12,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < assetGroups.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: flexShare(groups[assetGroups[i]]!, totals.assetsCents),
                    child: ColoredBox(color: palette.group(assetGroups[i])),
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 6, children: [
            for (final g in assetGroups)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, color: palette.group(g)),
                const SizedBox(width: 6),
                Text('${g.label.toUpperCase()} ${_pct.format(groups[g]! / totals.assetsCents)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Crt.offWhite)),
              ]),
          ]),
        ],
      ]),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      Text(value, style: crtReadout(40, color)),
    ]);
  }
}

class _AccountGroupCard extends StatelessWidget {
  const _AccountGroupCard(this.accounts, {required this.group});

  final List<Account> accounts;
  final AccountGroup group;

  @override
  Widget build(BuildContext context) {
    final color = context.nido.group(group);
    final total = accounts.fold<int>(0, (s, a) => s + (a.balanceCents > 0 ? a.balanceCents : 0));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < accounts.length; i++) ...[
          if (i > 0) const Divider(indent: 72),
          _AccountTile(accounts[i], color: color, share: total == 0 ? 0 : accounts[i].balanceCents / total),
        ],
      ]),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile(this.a, {required this.color, required this.share});

  final Account a;
  final Color color;
  final double share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [a.type.label, if (a.institution.isNotEmpty) a.institution, if (a.sample) 'ejemplo'].join(' · ');
    return InkWell(
      onTap: () => openAccountForm(context, account: a),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Crt.screen,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: .7), width: 1.5),
            ),
            child: Icon(a.type.icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis),
              Text(subtitle, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
              if (accountsShowShare(a)) ...[
                const SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: .7,
                  alignment: Alignment.centerLeft,
                  child: LedBar(value: share, color: color, segments: 20, height: 6),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Text(
            a.isLiability ? '−${context.money(a.balanceCents)}' : context.money(a.balanceCents),
            style: mono(
              size: 15,
              weight: FontWeight.w700,
              color: a.isLiability || a.balanceCents < 0 ? context.nido.negative : Crt.offWhite,
            ),
          ),
        ]),
      ),
    );
  }

  /// El peso dentro del grupo solo tiene sentido en activos con saldo positivo.
  bool accountsShowShare(Account a) => !a.isLiability && a.balanceCents > 0;
}

const _templates = <(String, AccountType)>[
  ('Cuenta corriente', AccountType.bank),
  ('Cuenta de ahorro', AccountType.savings),
  ('Efectivo', AccountType.cash),
  ('Fondo indexado', AccountType.investment),
  ('Acciones', AccountType.investment),
  ('Cripto', AccountType.crypto),
  ('Vivienda', AccountType.property),
  ('Coche', AccountType.vehicle),
  ('Hipoteca', AccountType.mortgage),
  ('Préstamo', AccountType.loan),
  ('Tarjeta de crédito', AccountType.creditCard),
];

class _QuickAdd extends StatelessWidget {
  const _QuickAdd();

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Añadir rápido',
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (name, type) in _templates)
          ActionChip(
            avatar: Icon(type.icon, size: 18, color: type.liability ? Crt.redText : Crt.green),
            label: Text(name.toUpperCase()),
            onPressed: () => openAccountForm(context, presetType: type, presetName: name),
          ),
      ]),
    );
  }
}

void openAccountForm(BuildContext context, {Account? account, AccountType? presetType, String? presetName}) =>
    showForm<void>(context, AccountForm(account: account, presetType: presetType, presetName: presetName));

class AccountForm extends StatefulWidget {
  const AccountForm({super.key, this.account, this.presetType, this.presetName});

  final Account? account;
  final AccountType? presetType;
  final String? presetName;

  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account?.name ?? widget.presetName);
  late final _institution = TextEditingController(text: widget.account?.institution);
  late final _balance = TextEditingController(
    text: widget.account == null ? '' : centsToInput(widget.account!.balanceCents),
  );
  late AccountType _type = widget.account?.type ?? widget.presetType ?? AccountType.bank;

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<NidoStore>();
    final name = _name.text.trim();
    final institution = _institution.text.trim();
    final balance = parseCents(_balance.text)!;
    final existing = widget.account;
    store.run(existing == null
        ? store.repo.createAccount(name: name, type: _type, institution: institution, balanceCents: balance)
        : store.repo.updateAccount(existing.id,
            name: name, type: _type, institution: institution, balanceCents: balance));
    Navigator.pop(context);
    showMessage(existing == null ? 'Cuenta "$name" añadida.' : 'Cuenta "$name" guardada.');
  }

  Future<void> _delete() async {
    final store = context.read<NidoStore>();
    final account = widget.account!;
    final ok = await confirm(context,
        title: 'Eliminar "${account.name}"',
        message: 'La cuenta desaparecerá de tu patrimonio. Los movimientos ya registrados se conservan.');
    if (!ok || !mounted) return;
    store.run(store.repo.deleteAccount(account.id, store.goals));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: FormFrame(
        title: widget.account == null ? 'Nueva cuenta' : 'Editar cuenta',
        onSave: _save,
        onDelete: widget.account == null ? null : _delete,
        children: [
          LabeledField(
            label: 'Tipo',
            child: DropdownButtonFormField<AccountType>(
              initialValue: _type,
              isExpanded: true,
              dropdownColor: Crt.panelHigh,
              items: [
                for (final t in AccountType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Row(children: [
                      Icon(t.icon, size: 20, color: t.liability ? Crt.redText : Crt.green),
                      const SizedBox(width: 12),
                      Text(t.liability ? '${t.label} (deuda)' : t.label),
                    ]),
                  ),
              ],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
          ),
          LabeledField(
            label: 'Nombre',
            child: TextFormField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'Ej.: Cuenta nómina'),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              validator: requiredText,
            ),
          ),
          LabeledField(
            label: 'Entidad (opcional)',
            child: TextFormField(
              controller: _institution,
              decoration: const InputDecoration(hintText: 'Ej.: ING, MyInvestor…'),
              maxLength: 60,
            ),
          ),
          MoneyField(
            controller: _balance,
            label: _type.liability ? 'Deuda pendiente' : 'Saldo o valor actual',
            allowNegative: !_type.liability,
            autofocus: widget.presetName != null,
            hint: widget.account != null
                ? 'Cambiar el saldo aquí es una nueva valoración. Para ingresos y gastos usa Movimientos.'
                : _type.liability
                    ? 'Lo que te queda por pagar, en positivo.'
                    : null,
          ),
        ],
      ),
    );
  }
}
