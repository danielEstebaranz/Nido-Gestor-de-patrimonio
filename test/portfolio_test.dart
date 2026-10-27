import 'package:flutter_test/flutter_test.dart';
import 'package:nido/domain/portfolio.dart';
import 'package:nido/models/account.dart';
import 'package:nido/models/goal.dart';
import 'package:nido/models/movement.dart';
import 'package:nido/models/recurrence.dart';

const bank = Account(id: 'bank', name: 'Banco', type: AccountType.bank, balanceCents: 100000);
const savings = Account(id: 'sav', name: 'Ahorro', type: AccountType.savings, balanceCents: 50000);
const card = Account(id: 'card', name: 'Tarjeta', type: AccountType.creditCard, balanceCents: 20000);
const mortgage = Account(id: 'mort', name: 'Hipoteca', type: AccountType.mortgage, balanceCents: 9000000);
final accounts = {for (final a in [bank, savings, card, mortgage]) a.id: a};

Movement mv(MovementKind kind, int cents, String from, [String? to]) =>
    Movement(id: 'm', kind: kind, amountCents: cents, accountId: from, toAccountId: to, date: DateTime(2026, 10));

void main() {
  test('el patrimonio neto resta las deudas', () {
    final t = totalsOf(accounts.values);
    expect(t.assetsCents, 150000);
    expect(t.liabilitiesCents, 9020000);
    expect(t.netWorthCents, -8870000);
  });

  group('balanceChanges', () {
    test('ingreso y gasto en un activo', () {
      expect(balanceChanges(mv(MovementKind.income, 500, 'bank'), accounts), {'bank': 500});
      expect(balanceChanges(mv(MovementKind.expense, 500, 'bank'), accounts), {'bank': -500});
    });

    test('un gasto con tarjeta aumenta la deuda', () {
      expect(balanceChanges(mv(MovementKind.expense, 500, 'card'), accounts), {'card': 500});
    });

    test('pagar la hipoteca desde el banco reduce ambas', () {
      expect(balanceChanges(mv(MovementKind.transfer, 70000, 'bank', 'mort'), accounts),
          {'bank': -70000, 'mort': -70000});
    });

    test('transferencia entre activos no cambia el patrimonio', () {
      final changes = balanceChanges(mv(MovementKind.transfer, 1000, 'bank', 'sav'), accounts);
      expect(changes, {'bank': -1000, 'sav': 1000});
    });

    test('ignora cuentas que ya no existen', () {
      expect(balanceChanges(mv(MovementKind.transfer, 1000, 'bank', 'borrada'), accounts), {'bank': -1000});
    });
  });

  test('diffChanges calcula el ajuste al editar', () {
    final before = balanceChanges(mv(MovementKind.expense, 1000, 'bank'), accounts);
    final after = balanceChanges(mv(MovementKind.expense, 1500, 'sav'), accounts);
    expect(diffChanges(before, after), {'bank': 1000, 'sav': -1500});
    expect(diffChanges(before, before), isEmpty);
  });

  group('objetivos', () {
    test('vinculado suma los saldos de sus cuentas e ignora deudas', () {
      const g = Goal(id: 'g', name: 'Colchón', targetCents: 300000, accountIds: ['bank', 'sav', 'card']);
      expect(goalProgressCents(g, accounts), 150000);
    });

    test('manual usa lo anotado', () {
      const g = Goal(id: 'g', name: 'Viaje', targetCents: 100000, savedCents: 25000);
      expect(goalProgressCents(g, accounts), 25000);
    });

    test('aportación mensual necesaria', () {
      final g = Goal(id: 'g', name: 'Coche', targetCents: 120000, deadline: DateTime(2027, 10));
      expect(monthlyNeededCents(g, 0, DateTime(2026, 10, 20)), 10000);
      expect(monthlyNeededCents(g, 120000, DateTime(2026, 10, 20)), isNull);
      expect(monthlyNeededCents(g, 0, DateTime(2027, 11)), 120000);
    });
  });

  test('flujo del mes y tasa de ahorro', () {
    final flow = monthFlow([
      mv(MovementKind.income, 200000, 'bank'),
      mv(MovementKind.expense, 50000, 'bank'),
      mv(MovementKind.transfer, 30000, 'bank', 'sav'),
    ]);
    expect(flow.incomeCents, 200000);
    expect(flow.expenseCents, 50000);
    expect(flow.savingsRate, .75);
  });

  test('monthId', () => expect(monthId(DateTime(2026, 3, 9)), '2026-03'));

  test('totales por grupo', () {
    final g = groupTotals(accounts.values);
    expect(g[AccountGroup.liquidity], 150000);
    expect(g[AccountGroup.debts], 9020000);
    expect(g[AccountGroup.investments], 0);
  });

  test('gasto por categoría ordenado', () {
    final list = expensesByCategory([
      Movement(id: 'a', kind: MovementKind.expense, amountCents: 100, accountId: 'bank', category: 'food', date: DateTime(2026)),
      Movement(id: 'b', kind: MovementKind.expense, amountCents: 300, accountId: 'bank', category: 'home', date: DateTime(2026)),
      Movement(id: 'c', kind: MovementKind.expense, amountCents: 50, accountId: 'bank', category: 'food', date: DateTime(2026)),
      Movement(id: 'd', kind: MovementKind.income, amountCents: 999, accountId: 'bank', category: 'salary', date: DateTime(2026)),
    ]);
    expect(list.map((e) => (e.key, e.value)), [('home', 300), ('food', 150)]);
  });

  test('colchón de seguridad en meses de gasto', () {
    // 1.500 € de liquidez / 400 € al mes = 3,75 meses.
    expect(emergencyMonths(accounts.values, 40000), 3.75);
    expect(emergencyMonths(accounts.values, null), isNull);
    expect(emergencyMonths(accounts.values, 0), isNull);
  });

  test('gasto mensual de referencia: gastos más pagos de deudas, meses completos', () {
    final now = DateTime(2026, 10, 20);
    final movements = [
      Movement(id: 'a', kind: MovementKind.expense, amountCents: 80000, accountId: 'bank', date: DateTime(2026, 8, 5)),
      Movement(id: 'b', kind: MovementKind.expense, amountCents: 60000, accountId: 'bank', date: DateTime(2026, 9, 5)),
      // Cuota de la hipoteca: cuenta como gasto del mes.
      Movement(id: 'c', kind: MovementKind.transfer, amountCents: 60000, accountId: 'bank', toAccountId: 'mort', date: DateTime(2026, 9, 5)),
      // Pago de la tarjeta: no cuenta (sus compras ya son gastos).
      Movement(id: 'g', kind: MovementKind.transfer, amountCents: 77777, accountId: 'bank', toAccountId: 'card', date: DateTime(2026, 9, 20)),
      // Ahorro (traspaso entre activos): no cuenta.
      Movement(id: 'd', kind: MovementKind.transfer, amountCents: 99999, accountId: 'bank', toAccountId: 'sav', date: DateTime(2026, 9, 6)),
      // Un ingreso no cuenta, y octubre (en curso) tampoco.
      Movement(id: 'e', kind: MovementKind.income, amountCents: 500000, accountId: 'bank', date: DateTime(2026, 9, 1)),
      Movement(id: 'f', kind: MovementKind.expense, amountCents: 5000, accountId: 'bank', date: DateTime(2026, 10, 2)),
    ];
    // Agosto 800 € y septiembre 600 + 600 €: media 1.000 €.
    expect(monthlySpending(movements, accounts, now), 100000);
    // Solo hay datos del mes en curso: se usa ese.
    expect(monthlySpending(movements.where((m) => m.id == 'f'), accounts, now), 5000);
    expect(monthlySpending(const [], accounts, now), isNull);
  });

  test('los meses sin gastos cuentan como 0 y solo los 3 últimos completos', () {
    final now = DateTime(2026, 10, 20);
    final movements = [
      Movement(id: 'a', kind: MovementKind.expense, amountCents: 999999, accountId: 'bank', date: DateTime(2026, 5, 5)),
      Movement(id: 'b', kind: MovementKind.income, amountCents: 200000, accountId: 'bank', date: DateTime(2026, 8, 1)),
      Movement(id: 'c', kind: MovementKind.expense, amountCents: 60000, accountId: 'bank', date: DateTime(2026, 9, 5)),
    ];
    // Mayo queda fuera (julio–septiembre). Desde agosto: (0 + 600 €) / 2.
    expect(averageSpending(movements, accounts, now), (cents: 30000, months: 2));
  });

  group('gasto de referencia: fijo de Recurrentes + variable', () {
    final now = DateTime(2026, 10, 20);
    Recurrence rec(String id, MovementKind kind, int cents, String account,
            {String? to, Frequency f = Frequency.monthly, int? previous, int? count, int next = 0, DateTime? start, String category = 'other'}) =>
        Recurrence(
          id: id,
          type: RecurrenceType.movement,
          frequency: f,
          startDate: start ?? DateTime(2026, 8, 14),
          accountId: account,
          kind: kind,
          amountCents: cents,
          previousAmountCents: previous,
          toAccountId: to,
          category: category,
          count: count,
          nextIndex: next,
        );
    final recurrences = [
      rec('netflix', MovementKind.expense, 1299, 'card', previous: 1199, category: 'subscriptions'),
      rec('prime', MovementKind.expense, 4990, 'card', f: Frequency.yearly, start: DateTime(2026, 11, 8)),
      rec('nomina', MovementKind.income, 240000, 'bank'),
      rec('ahorro', MovementKind.transfer, 25000, 'bank', to: 'sav'),
      // Gimnasio dado de baja: ya no cuenta, tampoco lo que se pagó.
      rec('gym', MovementKind.expense, 3000, 'bank', count: 2, next: 2, start: DateTime(2026, 8, 1)),
      Recurrence(
        id: 'plan',
        type: RecurrenceType.installment,
        frequency: Frequency.monthly,
        startDate: DateTime(2026, 8, 5),
        accountId: 'mort',
        payAccountId: 'bank',
        principalCents: 120000,
        rateBps: 0,
        months: 12,
      ),
    ];
    Movement e(String id, int cents, DateTime date, {String account = 'bank'}) =>
        Movement(id: id, kind: MovementKind.expense, amountCents: cents, accountId: account, date: date);
    final movements = [
      Movement(id: 'm1', kind: MovementKind.expense, amountCents: 1199, accountId: 'card', category: 'subscriptions', date: DateTime(2026, 8, 14)), // Netflix a mano, precio anterior
      Movement(id: 'm7', kind: MovementKind.expense, amountCents: 1299, accountId: 'card', category: 'food', date: DateTime(2026, 8, 15)), // mismo importe, otra cosa
      e('m2', 50000, DateTime(2026, 8, 20)),
      e('netflix-r1', 1299, DateTime(2026, 9, 14), account: 'card'), // apuntado por la programación
      e('m3', 30000, DateTime(2026, 9, 20)),
      e('m4', 3000, DateTime(2026, 9, 1)), // gimnasio
      e('plan-r1-i', 250, DateTime(2026, 9, 5)), // intereses de una cuota
      Movement(id: 'm5', kind: MovementKind.transfer, amountCents: 10000, accountId: 'bank', toAccountId: 'mort', date: DateTime(2026, 9, 5)),
      e('m6', 7000, DateTime(2026, 10, 2)), // mes en curso
    ];

    test('fijo: gastos y cuotas activos al mes; ingresos, ahorro y bajas no', () {
      final costs = {for (final r in recurrences) r.id: fixedMonthlyCost(r, accounts)};
      expect(costs, {'netflix': 1299, 'prime': 416, 'nomina': 0, 'ahorro': 0, 'gym': 0, 'plan': 10000});
    });

    test('lo que viene de Recurrentes no se cuenta dos veces', () {
      final covered = movements.where((m) => coveredByRecurrence(m, recurrences)).map((m) => m.id);
      expect(covered, ['m1', 'netflix-r1', 'm4', 'plan-r1-i', 'm5']);
    });

    test('total', () {
      final ref = spendingReference(movements, accounts, recurrences, now)!;
      expect(ref.fixedCents, 11715);
      // Agosto 500 + 12,99 € (la compra de m7) y septiembre 300 €.
      expect(ref.variableCents, 40650);
      expect(ref.months, 2);
      expect(ref.totalCents, 52365);
    });

    test('sin historial usa lo programado; sin nada, null', () {
      expect(spendingReference(const [], accounts, recurrences, now)!.totalCents, 11715);
      expect(spendingReference(const [], accounts, const [], now), isNull);
    });
  });

  test('fondo de emergencia recomendado, redondeado a cientos de euros', () {
    expect(recommendedEmergencyFund(123456, 6), 750000);
    expect(recommendedEmergencyFund(100000, 6), 600000);
  });

  test('endeudamiento', () {
    expect(debtRatio(const PortfolioTotals(assetsCents: 1000, liabilitiesCents: 250)), .25);
    expect(debtRatio(const PortfolioTotals(assetsCents: 0, liabilitiesCents: 250)), isNull);
  });

  test('estado de un objetivo', () {
    final now = DateTime(2026, 10, 20);
    final g = Goal(id: 'g', name: 'X', targetCents: 1000, deadline: DateTime(2027));
    expect(goalStatus(g, 1000, now), GoalStatus.done);
    expect(goalStatus(g, 10, now), GoalStatus.onTrack);
    expect(goalStatus(g, 10, DateTime(2027, 2)), GoalStatus.late);
    expect(goalStatus(const Goal(id: 'g', name: 'X', targetCents: 1000), 10, now), GoalStatus.open);
  });
}
