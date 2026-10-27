import 'package:cloud_firestore/cloud_firestore.dart';

import 'account.dart';
import 'movement.dart';

enum Frequency {
  weekly('Semanal', 'semana', 'cada semana'),
  monthly('Mensual', 'mes', 'cada mes'),
  quarterly('Trimestral', 'trimestre', 'cada trimestre'),
  yearly('Anual', 'año', 'cada año');

  const Frequency(this.label, this.unit, this.every);
  final String label;
  final String unit;
  final String every;

  static Frequency fromName(String? name) =>
      Frequency.values.firstWhere((f) => f.name == name, orElse: () => Frequency.monthly);
}

enum RecurrenceType {
  /// Un ingreso, gasto o traspaso que se repite (nómina, suscripción, alquiler…).
  movement,

  /// Un préstamo, hipoteca o compra a plazos con cuadro de amortización.
  installment,
}

/// Una programación: algo que se repite y que Nido apunta solo (o propone).
///
/// [nextIndex] es cuántas repeticiones se han procesado ya (apuntadas o
/// saltadas). Se avanza dentro de una transacción, así dos dispositivos no
/// pueden apuntar la misma repetición dos veces.
class Recurrence {
  const Recurrence({
    required this.id,
    required this.type,
    required this.frequency,
    required this.startDate,
    required this.accountId,
    this.kind = MovementKind.expense,
    this.amountCents = 0,
    this.previousAmountCents,
    this.toAccountId,
    this.category = 'other',
    this.note = '',
    this.count,
    this.endDate,
    this.nextIndex = 0,
    this.auto = true,
    this.principalCents = 0,
    this.rateBps = 0,
    this.months = 0,
    this.payAccountId,
  });

  factory Recurrence.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    int? optInt(String k) => (d[k] as num?)?.toInt();
    return Recurrence(
      id: doc.id,
      type: d['type'] == 'installment' ? RecurrenceType.installment : RecurrenceType.movement,
      frequency: Frequency.fromName(d['frequency'] as String?),
      startDate: (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      accountId: d['accountId'] as String? ?? '',
      kind: MovementKind.fromName(d['kind'] as String?),
      amountCents: optInt('amountCents') ?? 0,
      previousAmountCents: optInt('previousAmountCents'),
      toAccountId: d['toAccountId'] as String?,
      category: d['category'] as String? ?? 'other',
      note: d['note'] as String? ?? '',
      count: optInt('count'),
      endDate: (d['endDate'] as Timestamp?)?.toDate(),
      nextIndex: optInt('nextIndex') ?? 0,
      auto: d['auto'] as bool? ?? true,
      principalCents: optInt('principalCents') ?? 0,
      rateBps: optInt('rateBps') ?? 0,
      months: optInt('months') ?? 0,
      payAccountId: d['payAccountId'] as String?,
    );
  }

  final String id;
  final RecurrenceType type;
  final Frequency frequency;

  /// Fecha de la primera repetición; marca también el día del mes o de la semana.
  final DateTime startDate;

  /// Cuenta del movimiento; en un plazo, la cuenta de deuda.
  final String accountId;
  final MovementKind kind;
  final int amountCents;

  /// Importe anterior, si se cambió (para avisar de subidas de precio).
  final int? previousAmountCents;
  final String? toAccountId;
  final String category;

  /// Nombre que se ve (Netflix, Nómina, Portátil a plazos…).
  final String note;

  /// Número total de repeticiones, o null si no tiene fin.
  final int? count;
  final DateTime? endDate;
  final int nextIndex;

  /// true: se apunta sola. false: se propone para confirmar.
  final bool auto;

  // Solo plazos.
  final int principalCents;

  /// TIN anual en puntos básicos (210 = 2,10 %).
  final int rateBps;
  final int months;

  /// Cuenta desde la que se paga la cuota.
  final String? payAccountId;

  bool get isInstallment => type == RecurrenceType.installment;
  bool get isSubscription => !isInstallment && kind == MovementKind.expense && category == 'subscriptions';
  bool get sample => id.startsWith(sampleIdPrefix);

  /// Repeticiones totales (los plazos acaban al pagar la última cuota).
  int? get totalCount => isInstallment ? months : count;
}
