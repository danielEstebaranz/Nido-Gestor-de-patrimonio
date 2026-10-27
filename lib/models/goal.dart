import 'package:cloud_firestore/cloud_firestore.dart';

import 'account.dart';

class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.targetCents,
    this.savedCents = 0,
    this.accountIds = const [],
    this.deadline,
    this.targetMonths,
  });

  factory Goal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Goal(
      id: doc.id,
      name: d['name'] as String? ?? '',
      targetCents: (d['targetCents'] as num?)?.toInt() ?? 0,
      savedCents: (d['savedCents'] as num?)?.toInt() ?? 0,
      accountIds: List<String>.from(d['accountIds'] as List? ?? const []),
      deadline: (d['deadline'] as Timestamp?)?.toDate(),
      targetMonths: (d['targetMonths'] as num?)?.toInt(),
    );
  }

  final String id;
  final String name;
  final int targetCents;

  /// Ahorro anotado a mano; solo cuenta si el objetivo no tiene cuentas vinculadas.
  final int savedCents;

  /// Si hay cuentas vinculadas, el progreso es la suma de sus saldos.
  final List<String> accountIds;
  final DateTime? deadline;

  /// Si no es null, el objetivo es dinámico: [targetMonths] meses de gasto
  /// (ver monthlySpending). [targetCents] guarda el último importe calculado.
  final int? targetMonths;

  bool get isDynamic => targetMonths != null;

  /// Creado por "Explorar con datos de ejemplo" (ver sampleIdPrefix).
  bool get sample => id.startsWith(sampleIdPrefix);

  bool get isLinked => accountIds.isNotEmpty;
}
