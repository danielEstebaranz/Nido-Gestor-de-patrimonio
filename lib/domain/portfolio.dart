import '../models/account.dart';
import '../models/goal.dart';
import '../models/movement.dart';
import '../models/recurrence.dart';
import 'recurrence_engine.dart';

class PortfolioTotals {
  const PortfolioTotals({required this.assetsCents, required this.liabilitiesCents});

  final int assetsCents;
  final int liabilitiesCents;

  int get netWorthCents => assetsCents - liabilitiesCents;
}

PortfolioTotals totalsOf(Iterable<Account> accounts) {
  var assets = 0;
  var liabilities = 0;
  for (final a in accounts) {
    if (a.isLiability) {
      liabilities += a.balanceCents;
    } else {
      assets += a.balanceCents;
    }
  }
  return PortfolioTotals(assetsCents: assets, liabilitiesCents: liabilities);
}

/// Valor de los activos por tipo, de mayor a menor. Ignora saldos negativos.
List<MapEntry<AccountType, int>> assetDistribution(Iterable<Account> accounts) {
  final byType = <AccountType, int>{};
  for (final a in accounts) {
    if (a.isLiability || a.balanceCents <= 0) continue;
    byType[a.type] = (byType[a.type] ?? 0) + a.balanceCents;
  }
  return byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Cuánto cambia el saldo de cada cuenta al aplicar [m].
///
/// En un activo, un ingreso suma y un gasto resta. En un pasivo es al revés:
/// un gasto con tarjeta aumenta la deuda y un pago (ingreso o transferencia
/// entrante) la reduce. Las cuentas que ya no existen se ignoran.
Map<String, int> balanceChanges(Movement m, Map<String, Account> accounts) {
  final changes = <String, int>{};
  void apply(String? id, int sign) {
    final account = id == null ? null : accounts[id];
    if (account == null) return;
    final delta = (account.isLiability ? -sign : sign) * m.amountCents;
    changes[account.id] = (changes[account.id] ?? 0) + delta;
  }

  switch (m.kind) {
    case MovementKind.income:
      apply(m.accountId, 1);
    case MovementKind.expense:
      apply(m.accountId, -1);
    case MovementKind.transfer:
      apply(m.accountId, -1);
      apply(m.toAccountId, 1);
  }
  changes.removeWhere((_, v) => v == 0);
  return changes;
}

/// Suma de cambios `after - before`, para editar un movimiento en una sola escritura.
Map<String, int> diffChanges(Map<String, int> before, Map<String, int> after) {
  final result = <String, int>{...after};
  before.forEach((id, v) => result[id] = (result[id] ?? 0) - v);
  result.removeWhere((_, v) => v == 0);
  return result;
}

int goalProgressCents(Goal goal, Map<String, Account> accounts) {
  if (!goal.isLinked) return goal.savedCents;
  var sum = 0;
  for (final id in goal.accountIds) {
    final a = accounts[id];
    if (a != null && !a.isLiability) sum += a.balanceCents;
  }
  return sum < 0 ? 0 : sum;
}

/// Aportación mensual necesaria para llegar a tiempo, o `null` si no aplica.
int? monthlyNeededCents(Goal goal, int progressCents, DateTime now, {int? target}) {
  final deadline = goal.deadline;
  final remaining = (target ?? goal.targetCents) - progressCents;
  if (deadline == null || remaining <= 0) return null;
  final months = (deadline.year - now.year) * 12 + deadline.month - now.month;
  if (months <= 0) return remaining;
  return (remaining / months).ceil();
}

class MonthFlow {
  const MonthFlow(this.incomeCents, this.expenseCents);

  final int incomeCents;
  final int expenseCents;

  int get balanceCents => incomeCents - expenseCents;

  /// Porcentaje de los ingresos que se ha ahorrado, o `null` sin ingresos.
  double? get savingsRate => incomeCents > 0 ? balanceCents / incomeCents : null;
}

MonthFlow monthFlow(Iterable<Movement> movements) {
  var income = 0;
  var expense = 0;
  for (final m in movements) {
    if (m.kind == MovementKind.income) income += m.amountCents;
    if (m.kind == MovementKind.expense) expense += m.amountCents;
  }
  return MonthFlow(income, expense);
}

String monthId(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Total por grupo. En activos ignora saldos negativos (un descubierto no
/// es "menos vivienda"); en deudas suma lo pendiente.
Map<AccountGroup, int> groupTotals(Iterable<Account> accounts) {
  final totals = {for (final g in AccountGroup.values) g: 0};
  for (final a in accounts) {
    if (!a.isLiability && a.balanceCents <= 0) continue;
    totals[a.group] = totals[a.group]! + a.balanceCents;
  }
  return totals;
}

/// Gasto por categoría, de mayor a menor.
List<MapEntry<String, int>> expensesByCategory(Iterable<Movement> movements) {
  final byCategory = <String, int>{};
  for (final m in movements) {
    if (m.kind != MovementKind.expense) continue;
    byCategory[m.category] = (byCategory[m.category] ?? 0) + m.amountCents;
  }
  return byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Gasto medio mensual de los meses con gastos en [movements], o `null`.
int? averageMonthlyExpense(Iterable<Movement> movements) {
  final byMonth = <String, int>{};
  for (final m in movements) {
    if (m.kind != MovementKind.expense) continue;
    final id = monthId(m.date);
    byMonth[id] = (byMonth[id] ?? 0) + m.amountCents;
  }
  if (byMonth.isEmpty) return null;
  return (byMonth.values.fold<int>(0, (a, b) => a + b) / byMonth.length).round();
}

/// Ingreso medio mensual de los meses con ingresos en [movements], o `null`.
int? averageMonthlyIncome(Iterable<Movement> movements) {
  final byMonth = <String, int>{};
  for (final m in movements) {
    if (m.kind != MovementKind.income) continue;
    final id = monthId(m.date);
    byMonth[id] = (byMonth[id] ?? 0) + m.amountCents;
  }
  if (byMonth.isEmpty) return null;
  return (byMonth.values.fold<int>(0, (a, b) => a + b) / byMonth.length).round();
}

/// Colchón de seguridad: cuántos meses de [monthlyCents] cubre la liquidez.
double? emergencyMonths(Iterable<Account> accounts, int? monthlyCents) {
  if (monthlyCents == null || monthlyCents <= 0) return null;
  return groupTotals(accounts)[AccountGroup.liquidity]! / monthlyCents;
}

/// Si [m] es parte de lo que cuesta vivir: un gasto, o la cuota de un
/// préstamo o hipoteca (traspaso desde un activo). El pago de la tarjeta de
/// crédito no: lo comprado con ella ya está contado como gasto.
bool isSpending(Movement m, Map<String, Account> accounts) =>
    m.kind == MovementKind.expense ||
    (m.kind == MovementKind.transfer && _paysLoan(m.accountId, m.toAccountId, accounts));

bool _paysLoan(String from, String? to, Map<String, Account> accounts) {
  final type = accounts[to]?.type;
  return (type == AccountType.loan || type == AccountType.mortgage) && !(accounts[from]?.isLiability ?? false);
}

/// Media mensual de lo gastado (ver [isSpending]) en los últimos [maxMonths]
/// meses completos, desde el primero con algún movimiento; los meses sin gastos
/// cuentan como 0. Sin ningún mes completo, lo del mes en curso (months: 0).
/// [include] filtra qué gastos entran. null sin movimientos.
({int cents, int months})? averageSpending(
  Iterable<Movement> movements,
  Map<String, Account> accounts,
  DateTime now, {
  bool Function(Movement m)? include,
  int maxMonths = 3,
}) {
  int index(DateTime d) => d.year * 12 + d.month - 1;
  final current = index(now);
  int? first;
  var complete = 0;
  var thisMonth = 0;
  for (final m in movements) {
    final i = index(m.date);
    if (i < current - maxMonths || i > current) continue;
    if (first == null || i < first) first = i;
    if (!isSpending(m, accounts) || !(include?.call(m) ?? true)) continue;
    if (i == current) {
      thisMonth += m.amountCents;
    } else {
      complete += m.amountCents;
    }
  }
  if (first == null) return null;
  final months = current - first;
  if (months == 0) return (cents: thisMonth, months: 0);
  return (cents: (complete / months).round(), months: months);
}

/// Media mensual de todo lo gastado, incluido lo que viene de Recurrentes.
int? monthlySpending(Iterable<Movement> movements, Map<String, Account> accounts, DateTime now) =>
    averageSpending(movements, accounts, now)?.cents;

/// Lo que cuesta al mes una programación de gasto o una cuota activa, en su
/// equivalente mensual (un pago anual cuenta 1/12). 0 si es un ingreso, un
/// ahorro o ya ha terminado.
int fixedMonthlyCost(Recurrence r, Map<String, Account> accounts) {
  if (nextOccurrence(r) == null) return 0;
  final costs = r.isInstallment ||
      r.kind == MovementKind.expense ||
      (r.kind == MovementKind.transfer && _paysLoan(r.accountId, r.toAccountId, accounts));
  return costs ? monthlyEquivalent(amountPerOccurrence(r), r.frequency) : 0;
}

final _generatedId = RegExp(r'-r\d+(-[ci])?$');

/// Si [m] ya está contado en lo fijo: lo apuntó una programación, o es el mismo
/// cargo apuntado a mano (mismo tipo, cuentas, categoría e importe, también el
/// precio anterior) o un pago a la deuda de un plazo. Se miran también las
/// programaciones terminadas: una suscripción dada de baja deja de contar.
bool coveredByRecurrence(Movement m, Iterable<Recurrence> recurrences) {
  if (_generatedId.hasMatch(m.id)) return true;
  for (final r in recurrences) {
    if (r.isInstallment) {
      if (m.kind == MovementKind.transfer && m.toAccountId == r.accountId) return true;
    } else if (m.kind == r.kind &&
        m.accountId == r.accountId &&
        (m.kind == MovementKind.transfer ? m.toAccountId == r.toAccountId : m.category == r.category) &&
        (m.amountCents == r.amountCents || m.amountCents == r.previousAmountCents)) {
      return true;
    }
  }
  return false;
}

/// Lo que cuesta un mes de tu vida, en dos partes.
class SpendingReference {
  const SpendingReference({required this.fixedCents, required this.variableCents, required this.months});

  /// Gastos y cuotas programados en Recurrentes, al mes.
  final int fixedCents;

  /// Media mensual del resto de gastos apuntados.
  final int variableCents;

  /// Meses completos de historial en [variableCents] (0: el mes en curso o ninguno).
  final int months;

  int get totalCents => fixedCents + variableCents;
}

/// Gasto mensual de referencia del colchón de seguridad y del fondo de
/// emergencia: lo fijo de Recurrentes más la media de lo que no viene de ahí,
/// para no contar nada dos veces. null si no hay ni gastos ni programaciones.
SpendingReference? spendingReference(
  Iterable<Movement> movements,
  Map<String, Account> accounts,
  Iterable<Recurrence> recurrences,
  DateTime now,
) {
  final fixed = recurrences.fold<int>(0, (s, r) => s + fixedMonthlyCost(r, accounts));
  final variable = averageSpending(movements, accounts, now, include: (m) => !coveredByRecurrence(m, recurrences));
  final ref = SpendingReference(fixedCents: fixed, variableCents: variable?.cents ?? 0, months: variable?.months ?? 0);
  return ref.totalCents > 0 ? ref : null;
}

/// Fondo de emergencia recomendado: [months] meses de gasto, redondeado hacia
/// arriba a cientos de euros.
int recommendedEmergencyFund(int monthlyCents, int months) => ((monthlyCents * months) / 10000).ceil() * 10000;

/// Deuda sobre activos (0,25 = las deudas son un 25 % de lo que tienes).
double? debtRatio(PortfolioTotals t) => t.assetsCents > 0 ? t.liabilitiesCents / t.assetsCents : null;

enum GoalStatus {
  done('Conseguido'),
  onTrack('En camino'),
  late('Fuera de plazo'),
  open('Sin fecha');

  const GoalStatus(this.label);
  final String label;
}

GoalStatus goalStatus(Goal goal, int progressCents, DateTime now, {int? target}) {
  if (progressCents >= (target ?? goal.targetCents)) return GoalStatus.done;
  final deadline = goal.deadline;
  if (deadline == null) return GoalStatus.open;
  return deadline.isBefore(DateTime(now.year, now.month, now.day)) ? GoalStatus.late : GoalStatus.onTrack;
}
