import 'package:flutter_test/flutter_test.dart';
import 'package:nido/domain/portfolio.dart';
import 'package:nido/domain/recurrence_engine.dart';
import 'package:nido/models/account.dart';
import 'package:nido/models/movement.dart';
import 'package:nido/models/recurrence.dart';

Recurrence monthly({required DateTime start, int next = 0, int? count, DateTime? end, int amount = 1299}) => Recurrence(
      id: 'netflix',
      type: RecurrenceType.movement,
      frequency: Frequency.monthly,
      startDate: start,
      accountId: 'tarjeta',
      amountCents: amount,
      category: 'subscriptions',
      note: 'Netflix',
      nextIndex: next,
      count: count,
      endDate: end,
    );

void main() {
  group('fechas', () {
    test('mensual el día 31 cae en el último día de los meses cortos', () {
      final r = monthly(start: DateTime(2026, 1, 31));
      expect(occurrenceDate(r, 1), DateTime(2026, 2, 28));
      expect(occurrenceDate(r, 2), DateTime(2026, 3, 31));
      expect(occurrenceDate(r, 11), DateTime(2026, 12, 31));
      expect(occurrenceDate(r, 12), DateTime(2027, 1, 31));
    });

    test('semanal, trimestral y anual', () {
      final base = monthly(start: DateTime(2026, 10, 22));
      Recurrence withF(Frequency f) => Recurrence(
          id: 'x', type: RecurrenceType.movement, frequency: f, startDate: base.startDate, accountId: 'a');
      expect(occurrenceDate(withF(Frequency.weekly), 2), DateTime(2026, 11, 5));
      expect(occurrenceDate(withF(Frequency.quarterly), 1), DateTime(2027, 1, 22));
      expect(occurrenceDate(withF(Frequency.yearly), 1), DateTime(2027, 10, 22));
    });

    test('lo que toca apuntar hoy, sin lo ya procesado', () {
      final r = monthly(start: DateTime(2026, 8, 14), next: 1);
      final due = dueOccurrences(r, DateTime(2026, 10, 22, 13));
      expect(due.map((d) => d.index), [1, 2]);
      expect(due.last.date, DateTime(2026, 10, 14));
      expect(nextOccurrence(monthly(start: DateTime(2026, 8, 14), next: 3)), DateTime(2026, 11, 14));
    });

    test('respeta el número de cargos y la fecha de fin', () {
      expect(dueOccurrences(monthly(start: DateTime(2026, 1, 1), count: 2), DateTime(2026, 10, 1)), hasLength(2));
      expect(nextOccurrence(monthly(start: DateTime(2026, 1, 1), count: 2, next: 2)), isNull);
      final withEnd = monthly(start: DateTime(2026, 1, 1), end: DateTime(2026, 3, 15));
      expect(dueOccurrences(withEnd, DateTime(2026, 10, 1)), hasLength(3));
    });

    test('primer cargo a partir de hoy', () {
      final now = DateTime(2026, 10, 22);
      expect(firstOccurrenceFrom(now, Frequency.monthly, 14), DateTime(2026, 11, 14));
      expect(firstOccurrenceFrom(now, Frequency.monthly, 25), DateTime(2026, 10, 25));
      expect(firstOccurrenceFrom(now, Frequency.monthly, 22), DateTime(2026, 10, 22));
      expect(firstOccurrenceFrom(now, Frequency.monthly, null), DateTime(2026, 10, 22));
      // 22/10/2026 es jueves (4): el próximo lunes (1) es el 26.
      expect(firstOccurrenceFrom(now, Frequency.weekly, 1), DateTime(2026, 10, 26));
    });

    test('equivalentes mensual y anual', () {
      expect(monthlyEquivalent(1200, Frequency.yearly), 100);
      expect(monthlyEquivalent(1000, Frequency.weekly), 4333);
      expect(annualEquivalent(1299, Frequency.monthly), 15588);
    });
  });

  group('plazos', () {
    test('cuota francesa conocida: 150.000 € al 2,10 % a 30 años', () {
      // 150.000 × 0,00175 / (1 − 1,00175^−360) = 561,96 €/mes.
      expect(installmentCents(15000000, 210, 360), closeTo(56196, 1));
    });

    test('sin intereses, cuotas iguales', () {
      expect(installmentCents(120000, 0, 12), 10000);
      final rows = amortization(120000, 0, 12);
      expect(rows.every((r) => r.interestCents == 0), isTrue);
      expect(rows.last.remainingCents, 0);
    });

    test('el cuadro termina en cero y el capital suma el préstamo', () {
      final rows = amortization(1000000, 795, 36);
      expect(rows, hasLength(36));
      expect(rows.last.remainingCents, 0);
      expect(rows.fold<int>(0, (s, r) => s + r.principalCents), 1000000);
      // Los intereses bajan y el capital sube con cada cuota.
      expect(rows.first.interestCents, greaterThan(rows.last.interestCents));
      expect(rows.first.principalCents, lessThan(rows.last.principalCents));
    });

    test('una cuota separa capital (traspaso a la deuda) e intereses (gasto)', () {
      final plan = Recurrence(
        id: 'hipo',
        type: RecurrenceType.installment,
        frequency: Frequency.monthly,
        startDate: DateTime(2026, 11, 5),
        accountId: 'hipoteca',
        payAccountId: 'nomina',
        principalCents: 15000000,
        rateBps: 210,
        months: 360,
        note: 'Hipoteca',
      );
      final ms = occurrenceMovements(plan, 0);
      expect(ms, hasLength(2));
      final capital = ms.firstWhere((m) => m.kind == MovementKind.transfer);
      final interest = ms.firstWhere((m) => m.kind == MovementKind.expense);
      expect(interest.amountCents, 26250); // 150.000 × 2,10 % / 12
      expect(capital.amountCents + interest.amountCents, installmentCents(15000000, 210, 360));
      expect(interest.category, 'interest');
      expect(capital.id, 'hipo-r0-c');

      // Aplicado a las cuentas: la deuda baja solo el capital y la nómina paga la cuota entera.
      const accounts = {
        'nomina': Account(id: 'nomina', name: 'Nómina', type: AccountType.bank, balanceCents: 0),
        'hipoteca': Account(id: 'hipoteca', name: 'Hipoteca', type: AccountType.mortgage, balanceCents: 15000000),
      };
      final total = <String, int>{};
      for (final m in ms) {
        balanceChanges(m, accounts).forEach((k, v) => total[k] = (total[k] ?? 0) + v);
      }
      expect(total['hipoteca'], -capital.amountCents);
      expect(total['nomina'], -(capital.amountCents + interest.amountCents));
      expect(remainingAfter(plan, 1), 15000000 - capital.amountCents);
    });

    test('un movimiento normal usa un id determinista', () {
      final m = occurrenceMovements(monthly(start: DateTime(2026, 8, 14)), 2).single;
      expect(m.id, 'netflix-r2');
      expect(m.date, DateTime(2026, 10, 14, 9));
      expect(m.amountCents, 1299);
    });
  });
}

