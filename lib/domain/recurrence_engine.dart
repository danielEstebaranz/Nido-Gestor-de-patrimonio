import 'dart:math' as math;

import '../models/movement.dart';
import '../models/recurrence.dart';

/// Lógica pura de programaciones y plazos: fechas de cada repetición, qué toca
/// apuntar hoy, cuadro de amortización y los movimientos de cada repetición.

DateTime _addMonths(DateTime d, int months) {
  final y = d.year + ((d.month - 1 + months) ~/ 12);
  final m = (d.month - 1 + months) % 12 + 1;
  // Día 31 en un mes de 30: último día del mes.
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, math.min(d.day, lastDay));
}

/// Fecha de la repetición número [index] (0 = la primera).
DateTime occurrenceDate(Recurrence r, int index) {
  final s = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
  return switch (r.frequency) {
    Frequency.weekly => DateTime(s.year, s.month, s.day + 7 * index),
    Frequency.monthly => _addMonths(s, index),
    Frequency.quarterly => _addMonths(s, 3 * index),
    Frequency.yearly => _addMonths(s, 12 * index),
  };
}

/// Si la repetición [index] existe (no ha terminado la programación).
bool occurrenceExists(Recurrence r, int index) {
  final total = r.totalCount;
  if (total != null && index >= total) return false;
  final end = r.endDate;
  if (end != null && occurrenceDate(r, index).isAfter(DateTime(end.year, end.month, end.day))) return false;
  return true;
}

/// Repeticiones pendientes con fecha de hoy o anterior, en orden. Con tope para
/// no inundar la app si una programación lleva años sin abrirse.
List<({int index, DateTime date})> dueOccurrences(Recurrence r, DateTime now, {int limit = 60}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <({int index, DateTime date})>[];
  for (var i = r.nextIndex; out.length < limit && occurrenceExists(r, i); i++) {
    final d = occurrenceDate(r, i);
    if (d.isAfter(today)) break;
    out.add((index: i, date: d));
  }
  return out;
}

/// Próxima repetición sin procesar, o null si la programación ha terminado.
DateTime? nextOccurrence(Recurrence r) => occurrenceExists(r, r.nextIndex) ? occurrenceDate(r, r.nextIndex) : null;

/// Cuántas repeticiones hay con fecha anterior o igual a [now].
int occurrencesUpTo(Recurrence r, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  var i = 0;
  while (occurrenceExists(r, i) && !occurrenceDate(r, i).isAfter(today)) {
    i++;
  }
  return i;
}

/// Importe de cada repetición (en un plazo, la cuota).
int amountPerOccurrence(Recurrence r) =>
    r.isInstallment ? installmentCents(r.principalCents, r.rateBps, r.months) : r.amountCents;

/// Equivalente mensual de una cantidad que se repite con [f].
int monthlyEquivalent(int cents, Frequency f) => switch (f) {
      Frequency.weekly => (cents * 52 / 12).round(),
      Frequency.monthly => cents,
      Frequency.quarterly => (cents / 3).round(),
      Frequency.yearly => (cents / 12).round(),
    };

int annualEquivalent(int cents, Frequency f) => switch (f) {
      Frequency.weekly => cents * 52,
      Frequency.monthly => cents * 12,
      Frequency.quarterly => cents * 4,
      Frequency.yearly => cents,
    };

// ---------------------------------------------------------------- Plazos

/// Cuota de un préstamo por el sistema francés (cuota constante).
int installmentCents(int principalCents, int rateBps, int months) {
  if (months <= 0 || principalCents <= 0) return 0;
  if (rateBps == 0) return (principalCents / months).ceil();
  final i = rateBps / 10000 / 12;
  return (principalCents * i / (1 - math.pow(1 + i, -months))).round();
}

class AmortizationRow {
  const AmortizationRow(this.index, this.paymentCents, this.interestCents, this.principalCents, this.remainingCents);

  final int index;
  final int paymentCents;
  final int interestCents;
  final int principalCents;

  /// Capital pendiente después de esta cuota.
  final int remainingCents;
}

/// Cuadro de amortización completo. La última cuota se ajusta para dejar la
/// deuda exactamente a cero (los redondeos a céntimos se acumulan).
List<AmortizationRow> amortization(int principalCents, int rateBps, int months) {
  final rows = <AmortizationRow>[];
  if (months <= 0 || principalCents <= 0) return rows;
  final payment = installmentCents(principalCents, rateBps, months);
  final i = rateBps / 10000 / 12;
  var remaining = principalCents;
  for (var k = 0; k < months; k++) {
    final interest = (remaining * i).round();
    var capital = payment - interest;
    if (k == months - 1 || capital > remaining) capital = remaining;
    remaining -= capital;
    rows.add(AmortizationRow(k, capital + interest, interest, capital, remaining));
  }
  return rows;
}

/// Capital pendiente según el plan tras [paid] cuotas pagadas.
int remainingAfter(Recurrence r, int paid) {
  if (paid <= 0) return r.principalCents;
  final rows = amortization(r.principalCents, r.rateBps, r.months);
  return paid >= rows.length ? 0 : rows[paid - 1].remainingCents;
}

int totalInterest(Recurrence r) =>
    amortization(r.principalCents, r.rateBps, r.months).fold(0, (s, row) => s + row.interestCents);

// ---------------------------------------------------------------- Movimientos

/// Ids deterministas: si dos dispositivos generan la misma repetición, escriben
/// el mismo documento. Con prefijo del id de la programación, así los datos de
/// ejemplo (ejemplo-…) se quitan junto con sus movimientos.
String occurrenceMovementId(Recurrence r, int index, [String part = '']) => '${r.id}-r$index$part';

/// Movimientos que produce la repetición [index]: uno para una programación
/// normal; para un plazo, el capital (traspaso a la deuda) y los intereses (gasto).
List<Movement> occurrenceMovements(Recurrence r, int index) {
  final day = occurrenceDate(r, index);
  final date = DateTime(day.year, day.month, day.day, 9);
  if (!r.isInstallment) {
    return [
      Movement(
        id: occurrenceMovementId(r, index),
        kind: r.kind,
        amountCents: r.amountCents,
        accountId: r.accountId,
        toAccountId: r.kind == MovementKind.transfer ? r.toAccountId : null,
        category: r.category,
        note: r.note,
        date: date,
      ),
    ];
  }
  final rows = amortization(r.principalCents, r.rateBps, r.months);
  if (index >= rows.length) return const [];
  final row = rows[index];
  final from = r.payAccountId ?? '';
  final label = r.note.isEmpty ? 'Cuota' : r.note;
  return [
    if (row.principalCents > 0)
      Movement(
        id: occurrenceMovementId(r, index, '-c'),
        kind: MovementKind.transfer,
        amountCents: row.principalCents,
        accountId: from,
        toAccountId: r.accountId,
        note: '$label · cuota ${index + 1}/${r.months}',
        date: date,
      ),
    if (row.interestCents > 0)
      Movement(
        id: occurrenceMovementId(r, index, '-i'),
        kind: MovementKind.expense,
        amountCents: row.interestCents,
        accountId: from,
        category: 'interest',
        note: '$label · intereses ${index + 1}/${r.months}',
        date: date,
      ),
  ];
}

/// Fecha de la primera repetición a partir de hoy para un día del mes (o de la
/// semana, 1 = lunes) dado. Sin día, hoy.
DateTime firstOccurrenceFrom(DateTime now, Frequency f, int? day) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == null) return today;
  if (f == Frequency.weekly) {
    // Días de calendario, no de 24 h: con el cambio de hora un Duration se
    // quedaría en las 23:00 del día anterior.
    final delta = (day - today.weekday) % 7;
    return DateTime(today.year, today.month, today.day + delta);
  }
  var candidate = DateTime(today.year, today.month, math.min(day, DateTime(today.year, today.month + 1, 0).day));
  if (candidate.isBefore(today)) {
    final next = DateTime(today.year, today.month + 1);
    candidate = DateTime(next.year, next.month, math.min(day, DateTime(next.year, next.month + 1, 0).day));
  }
  return candidate;
}
