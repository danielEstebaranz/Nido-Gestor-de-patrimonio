import 'package:flutter_test/flutter_test.dart';
import 'package:nido/data/sample_data.dart';
import 'package:nido/domain/portfolio.dart';
import 'package:nido/domain/recurrence_engine.dart';
import 'package:nido/models/account.dart';

void main() {
  final now = DateTime(2026, 10, 20, 18);
  final sample = SampleData.build(now);

  test('todo lleva el prefijo de ejemplo', () {
    final ids = [
      ...sample.accounts.map((a) => a.id),
      ...sample.movements.map((m) => m.id),
      ...sample.goals.map((g) => g.id),
      ...sample.recurrences.map((r) => r.id),
    ];
    expect(ids.every((id) => id.startsWith(sampleIdPrefix)), isTrue);
    expect(ids.toSet().length, ids.length, reason: 'ids repetidos');
  });

  test('no hay movimientos en el futuro', () {
    expect(sample.movements.every((m) => !m.date.isAfter(now)), isTrue);
    expect(sample.movements, isNotEmpty);
  });

  test('los saldos iniciales llevan a los finales previstos', () {
    final balances = {for (final a in sample.accounts) a.id: a.balanceCents};
    final byId = {for (final a in sample.accounts) a.id: a};
    for (final m in sample.movements) {
      balanceChanges(m, byId).forEach((id, d) => balances[id] = balances[id]! + d);
    }
    expect(balances['${sampleIdPrefix}nomina'], 348215);
    expect(balances['${sampleIdPrefix}tarjeta'], 64880);
    // Unos 121.400 € pendientes (lo exacto sale del plan, ver el test de abajo).
    expect((balances['${sampleIdPrefix}hipoteca']! - 12138055).abs(), lessThan(70000));
    // Ningún saldo inicial negativo, ni en activos ni en deudas.
    expect(sample.accounts.every((a) => a.balanceCents >= 0), isTrue, reason: sample.accounts.map((a) => '${a.id}=${a.balanceCents}').join(' '));
  });

  test('seis meses de historia anteriores al actual', () {
    expect(sample.history.keys, hasLength(6));
    expect(sample.history.keys.every((k) => k.compareTo(monthId(now)) < 0), isTrue);
  });

  test('las programaciones no repiten lo que ya está en los movimientos', () {
    // Ninguna automática tiene nada pendiente al cargar los ejemplos.
    for (final r in sample.recurrences.where((r) => r.auto)) {
      expect(dueOccurrences(r, now), isEmpty, reason: r.id);
    }
    // La de confirmación sí: para enseñar cómo funciona.
    expect(sample.recurrences.where((r) => !r.auto).expand((r) => dueOccurrences(r, now)), isNotEmpty);
  });

  test('la hipoteca del plan cuadra con la cuenta y la cuota es la de los movimientos', () {
    final plan = sample.recurrences.singleWhere((r) => r.id == '${sampleIdPrefix}rec-hipoteca');
    expect(amountPerOccurrence(plan), closeTo(61240, 50));
    final mortgage = sample.accounts.singleWhere((a) => a.id == '${sampleIdPrefix}hipoteca');
    // La cuenta parte de lo pendiente según el plan; los movimientos de ejemplo la llevan al final.
    final balances = {for (final a in sample.accounts) a.id: a.balanceCents};
    final byId = {for (final a in sample.accounts) a.id: a};
    for (final m in sample.movements) {
      balanceChanges(m, byId).forEach((id, d) => balances[id] = balances[id]! + d);
    }
    expect(balances[mortgage.id], remainingAfter(plan, plan.nextIndex));
    final portatil = sample.recurrences.singleWhere((r) => r.id == '${sampleIdPrefix}rec-portatil');
    final account = sample.accounts.singleWhere((a) => a.id == '${sampleIdPrefix}portatil');
    expect(remainingAfter(portatil, portatil.nextIndex), account.balanceCents);
  });

  test('gasto de referencia: Netflix, fibra e hipoteca solo cuentan en lo fijo', () {
    final byId = {for (final a in sample.accounts) a.id: a};
    final covered = sample.movements.where((m) => coveredByRecurrence(m, sample.recurrences)).map((m) => m.note).toSet();
    expect(covered, {'Nómina', 'Aportación mensual al fondo', 'Ahorro automático', 'Netflix', 'Fibra y móvil', 'Cuota de la hipoteca'});
    final ref = spendingReference(sample.movements, byId, sample.recurrences, now)!;
    // ignore: avoid_print
    print('fijo ${ref.fixedCents} variable ${ref.variableCents} (${ref.months} meses) total ${ref.totalCents}');
    expect(ref.months, 2);
  });
}
