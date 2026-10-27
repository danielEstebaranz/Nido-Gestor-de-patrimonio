import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'account.dart';

enum MovementKind {
  expense('Gasto', 'Gasto'),
  income('Ingreso', 'Ingreso'),
  transfer('Transferencia', 'Traspaso');

  const MovementKind(this.label, this.shortLabel);
  final String label;

  /// Para selectores estrechos (móvil).
  final String shortLabel;

  static MovementKind fromName(String? name) =>
      MovementKind.values.firstWhere((k) => k.name == name, orElse: () => MovementKind.expense);
}

class Category {
  const Category(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const expenseCategories = [
  Category('home', 'Vivienda', Icons.home_outlined),
  Category('food', 'Alimentación', Icons.shopping_cart_outlined),
  Category('transport', 'Transporte', Icons.directions_bus_outlined),
  Category('bills', 'Suministros', Icons.bolt_outlined),
  Category('leisure', 'Ocio', Icons.local_activity_outlined),
  Category('restaurants', 'Restaurantes', Icons.restaurant_outlined),
  Category('health', 'Salud', Icons.favorite_outline),
  Category('shopping', 'Compras', Icons.shopping_bag_outlined),
  Category('education', 'Formación', Icons.school_outlined),
  Category('subscriptions', 'Suscripciones', Icons.subscriptions_outlined),
  Category('taxes', 'Impuestos', Icons.receipt_long_outlined),
  // Intereses de préstamos e hipotecas: la parte de la cuota que es gasto.
  Category('interest', 'Intereses de deuda', Icons.percent),
  Category('other', 'Otros', Icons.more_horiz),
];

const incomeCategories = [
  Category('salary', 'Nómina', Icons.work_outline),
  Category('freelance', 'Trabajo extra', Icons.handyman_outlined),
  Category('dividends', 'Dividendos e intereses', Icons.percent),
  Category('rent', 'Alquileres', Icons.key_outlined),
  Category('gift', 'Regalos', Icons.card_giftcard_outlined),
  Category('other', 'Otros', Icons.more_horiz),
];

const transferCategory = Category('transfer', 'Transferencia', Icons.swap_horiz);

List<Category> categoriesFor(MovementKind kind) => switch (kind) {
      MovementKind.expense => expenseCategories,
      MovementKind.income => incomeCategories,
      MovementKind.transfer => const [transferCategory],
    };

Category categoryOf(MovementKind kind, String id) =>
    categoriesFor(kind).firstWhere((c) => c.id == id, orElse: () => categoriesFor(kind).last);

class Movement {
  const Movement({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.accountId,
    required this.date,
    this.toAccountId,
    this.category = 'other',
    this.note = '',
  });

  factory Movement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final kind = MovementKind.fromName(d['kind'] as String?);
    return Movement(
      id: doc.id,
      kind: kind,
      amountCents: (d['amountCents'] as num?)?.toInt() ?? 0,
      accountId: d['accountId'] as String? ?? '',
      toAccountId: d['toAccountId'] as String?,
      category: d['category'] as String? ?? 'other',
      note: d['note'] as String? ?? '',
      date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final MovementKind kind;

  /// Siempre positivo; el signo lo da [kind].
  final int amountCents;
  final String accountId;

  /// Solo en transferencias.
  final String? toAccountId;
  final String category;
  final String note;
  final DateTime date;

  /// Creado por "Explorar con datos de ejemplo" (ver sampleIdPrefix).
  bool get sample => id.startsWith(sampleIdPrefix);

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'amountCents': amountCents,
        'accountId': accountId,
        'toAccountId': kind == MovementKind.transfer ? toAccountId : null,
        'category': kind == MovementKind.transfer ? transferCategory.id : category,
        'note': note,
        'date': Timestamp.fromDate(date),
      };
}
