import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Los datos de ejemplo usan ids con este prefijo, así se pueden quitar sin
/// añadir campos al documento ni tocar las reglas de Firestore.
const sampleIdPrefix = 'ejemplo-';

/// Cómo se agrupa el patrimonio en pantalla.
enum AccountGroup {
  liquidity('Liquidez', 'Dinero disponible al momento', Icons.water_drop_outlined),
  investments('Inversiones', 'Fondos, acciones y cripto', Icons.trending_up),
  belongings('Bienes', 'Vivienda, vehículos y otros', Icons.home_work_outlined),
  debts('Deudas', 'Lo que queda por pagar', Icons.receipt_long_outlined);

  const AccountGroup(this.label, this.description, this.icon);
  final String label;
  final String description;
  final IconData icon;
}

enum AccountType {
  cash('Efectivo', Icons.payments_outlined),
  bank('Cuenta corriente', Icons.account_balance_outlined),
  savings('Cuenta de ahorro', Icons.savings_outlined),
  investment('Inversión', Icons.show_chart),
  crypto('Cripto', Icons.currency_bitcoin),
  property('Inmueble', Icons.home_outlined),
  vehicle('Vehículo', Icons.directions_car_outlined),
  other('Otro bien', Icons.category_outlined),
  creditCard('Tarjeta de crédito', Icons.credit_card, liability: true),
  loan('Préstamo', Icons.request_quote_outlined, liability: true),
  mortgage('Hipoteca', Icons.house_siding_outlined, liability: true);

  const AccountType(this.label, this.icon, {this.liability = false});

  final String label;
  final IconData icon;

  /// Los pasivos guardan en `balanceCents` lo que se debe (en positivo).
  final bool liability;

  AccountGroup get group => switch (this) {
        AccountType.cash || AccountType.bank || AccountType.savings => AccountGroup.liquidity,
        AccountType.investment || AccountType.crypto => AccountGroup.investments,
        AccountType.property || AccountType.vehicle || AccountType.other => AccountGroup.belongings,
        AccountType.creditCard || AccountType.loan || AccountType.mortgage => AccountGroup.debts,
      };

  static AccountType fromName(String? name) =>
      AccountType.values.firstWhere((t) => t.name == name, orElse: () => AccountType.other);
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.balanceCents,
    this.institution = '',
  });

  factory Account.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Account(
      id: doc.id,
      name: d['name'] as String? ?? '',
      type: AccountType.fromName(d['type'] as String?),
      balanceCents: (d['balanceCents'] as num?)?.toInt() ?? 0,
      institution: d['institution'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final AccountType type;
  final int balanceCents;
  final String institution;

  /// Creado por "Explorar con datos de ejemplo" (ver sampleIdPrefix).
  bool get sample => id.startsWith(sampleIdPrefix);

  bool get isLiability => type.liability;
  AccountGroup get group => type.group;
}
