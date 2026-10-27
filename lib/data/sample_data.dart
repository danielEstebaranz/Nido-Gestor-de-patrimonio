import '../domain/portfolio.dart';
import '../domain/recurrence_engine.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../models/movement.dart';
import '../models/recurrence.dart';

/// Datos de ejemplo para explorar Nido sin introducir nada: un hogar con
/// nómina, hipoteca, ahorro e inversión. Todos los ids empiezan por
/// [sampleIdPrefix] para poder quitarlos después.
class SampleData {
  SampleData._(this.accounts, this.movements, this.goals, this.history, this.recurrences);

  /// Cuentas con el saldo *inicial*: al aplicar [movements] quedan en el final.
  final List<Account> accounts;
  final List<Movement> movements;
  final List<Goal> goals;

  /// Programaciones, suscripciones y plazos. Lo anterior a hoy ya está
  /// procesado, así no se duplica lo que ya hay en [movements].
  final List<Recurrence> recurrences;

  /// Fotos de meses anteriores (id `yyyy-MM`) para la gráfica de evolución.
  final Map<String, PortfolioTotals> history;

  factory SampleData.build(DateTime now) {
    String id(String s) => '$sampleIdPrefix$s';

    // Saldo final que verá el usuario.
    final finals = <Account>[
      Account(id: id('nomina'), name: 'Cuenta nómina', type: AccountType.bank, institution: 'BBVA', balanceCents: 348215),
      Account(id: id('colchon'), name: 'Colchón', type: AccountType.savings, institution: 'Trade Republic', balanceCents: 640000),
      Account(id: id('fondo'), name: 'Fondo indexado MSCI World', type: AccountType.investment, institution: 'MyInvestor', balanceCents: 1495230),
      Account(id: id('bitcoin'), name: 'Bitcoin', type: AccountType.crypto, institution: 'Bit2Me', balanceCents: 118460),
      Account(id: id('piso'), name: 'Piso en Valladolid', type: AccountType.property, balanceCents: 16800000),
      Account(id: id('coche'), name: 'Coche', type: AccountType.vehicle, balanceCents: 980000),
      Account(id: id('hipoteca'), name: 'Hipoteca', type: AccountType.mortgage, institution: 'BBVA', balanceCents: _mortgagePending(now)),
      Account(id: id('tarjeta'), name: 'Tarjeta de crédito', type: AccountType.creditCard, institution: 'BBVA', balanceCents: 64880),
      // Portátil a 12 meses sin intereses: lo pendiente según las cuotas ya pagadas.
      Account(id: id('portatil'), name: 'Portátil a plazos', type: AccountType.loan, balanceCents: _portatilPending(now)),
    ];
    final byId = {for (final a in finals) a.id: a};

    final movements = <Movement>[];
    var n = 0;
    void add(DateTime month, int day, MovementKind kind, int cents, String from,
        {String? to, String category = 'other', String note = ''}) {
      final date = DateTime(month.year, month.month, day, 10 + n % 9, (n * 7) % 60);
      if (date.isAfter(now)) return;
      movements.add(Movement(
        id: id('mov-${(n++).toString().padLeft(3, '0')}'),
        kind: kind,
        amountCents: cents,
        accountId: from,
        toAccountId: to,
        category: kind == MovementKind.transfer ? transferCategory.id : category,
        note: note,
        date: date,
      ));
    }

    // Tres meses de movimientos, el actual solo hasta hoy. Cada mes varía un poco.
    for (var k = 2; k >= 0; k--) {
      final m = DateTime(now.year, now.month - k);
      int v(int cents, int pct) => cents + cents * pct * (k - 1) ~/ 100;
      add(m, 1, MovementKind.income, 240000, id('nomina'), category: 'salary', note: 'Nómina');
      add(m, 2, MovementKind.transfer, 30000, id('nomina'), to: id('fondo'), note: 'Aportación mensual al fondo');
      add(m, 3, MovementKind.transfer, 25000, id('nomina'), to: id('colchon'), note: 'Ahorro automático');
      add(m, 5, MovementKind.transfer, 61240, id('nomina'), to: id('hipoteca'), note: 'Cuota de la hipoteca');
      add(m, 4, MovementKind.expense, 8500, id('nomina'), category: 'home', note: 'Comunidad de vecinos');
      add(m, 6, MovementKind.expense, v(6480, 9), id('nomina'), category: 'bills', note: 'Luz');
      add(m, 7, MovementKind.expense, v(9240, 5), id('tarjeta'), category: 'food', note: 'Compra semanal');
      add(m, 9, MovementKind.expense, 3200, id('nomina'), category: 'health', note: 'Seguro médico');
      add(m, 8, MovementKind.expense, v(8635, -6), id('tarjeta'), category: 'food', note: 'Mercadona');
      add(m, 10, MovementKind.expense, 3590, id('nomina'), category: 'subscriptions', note: 'Fibra y móvil');
      add(m, 11, MovementKind.expense, v(6890, -8), id('tarjeta'), category: 'food', note: 'Compra semanal');
      add(m, 12, MovementKind.expense, v(5210, 12), id('tarjeta'), category: 'transport', note: 'Gasolina');
      add(m, 13, MovementKind.expense, v(5500, 10), id('tarjeta'), category: 'leisure', note: 'Concierto');
      add(m, 14, MovementKind.expense, 1299, id('tarjeta'), category: 'subscriptions', note: 'Netflix');
      add(m, 15, MovementKind.expense, v(4160, 20), id('tarjeta'), category: 'restaurants', note: 'Cena con amigos');
      add(m, 16, MovementKind.expense, v(8460, 3), id('tarjeta'), category: 'food', note: 'Compra semanal');
      add(m, 17, MovementKind.expense, 2400, id('nomina'), category: 'education', note: 'Curso de inglés');
      add(m, 18, MovementKind.expense, v(7320, 4), id('tarjeta'), category: 'food', note: 'Lidl');
      add(m, 19, MovementKind.expense, v(6300, -5), id('tarjeta'), category: 'restaurants', note: 'Comida fuera');
      add(m, 20, MovementKind.transfer, v(52000, 5), id('nomina'), to: id('tarjeta'), note: 'Pago de la tarjeta');
      add(m, 22, MovementKind.expense, v(2995, -15), id('tarjeta'), category: 'leisure', note: 'Cine y libros');
      add(m, 23, MovementKind.expense, v(7150, 6), id('tarjeta'), category: 'food', note: 'Compra semanal');
      add(m, 26, MovementKind.expense, v(4800, 12), id('tarjeta'), category: 'shopping', note: 'Ropa');
      if (k == 1) add(m, 24, MovementKind.expense, 4500, id('nomina'), category: 'health', note: 'Fisioterapeuta');
      if (k == 2) add(m, 25, MovementKind.expense, 18900, id('nomina'), category: 'shopping', note: 'Abrigo de invierno');
      add(m, 27, MovementKind.income, v(1840, 3), id('colchon'), category: 'dividends', note: 'Intereses de la cuenta');
    }

    // Saldo inicial = final - efecto de los movimientos.
    final effect = <String, int>{};
    for (final mv in movements) {
      balanceChanges(mv, byId).forEach((k, d) => effect[k] = (effect[k] ?? 0) + d);
    }
    final initial = [
      for (final a in finals)
        Account(
          id: a.id,
          name: a.name,
          type: a.type,
          institution: a.institution,
          balanceCents: a.balanceCents - (effect[a.id] ?? 0),
        ),
    ];

    final goals = [
      Goal(
        id: id('meta-emergencia'),
        name: 'Fondo de emergencia',
        targetCents: 1200000,
        targetMonths: 6,
        accountIds: [id('colchon')],
        deadline: DateTime(now.year + 1, now.month, 1),
      ),
      Goal(
        id: id('meta-coche'),
        name: 'Entrada del próximo coche',
        targetCents: 600000,
        savedCents: 185000,
        deadline: DateTime(now.year + 1, now.month + 6, 1),
      ),
      Goal(
        id: id('meta-japon'),
        name: 'Viaje a Japón',
        targetCents: 420000,
        savedCents: 290000,
        deadline: DateTime(now.year, now.month + 7, 1),
      ),
    ];

    // Seis meses de historia: el patrimonio crece ~1.000 €/mes y la hipoteca baja.
    final current = totalsOf(finals);
    const growth = [0, 98000, 211000, 287000, 402000, 468000, 571000];
    final history = <String, PortfolioTotals>{
      for (var k = 1; k <= 6; k++)
        monthId(DateTime(now.year, now.month - k)): PortfolioTotals(
          assetsCents: current.assetsCents - growth[k] + 41000 * k,
          liabilitiesCents: current.liabilitiesCents + 41000 * k,
        ),
    };

    return SampleData._(initial, movements, goals, history, _recurrences(now, id));
  }
}

DateTime _monthDay(DateTime now, int monthOffset, int day) => DateTime(now.year, now.month + monthOffset, day);

Recurrence _portatil(DateTime now) => Recurrence(
      id: '${sampleIdPrefix}rec-portatil',
      type: RecurrenceType.installment,
      frequency: Frequency.monthly,
      startDate: _monthDay(now, -3, 15),
      accountId: '${sampleIdPrefix}portatil',
      payAccountId: '${sampleIdPrefix}nomina',
      note: 'Portátil a plazos',
      principalCents: 120000,
      rateBps: 0,
      months: 12,
    );

int _portatilPending(DateTime now) {
  final plan = _portatil(now);
  return remainingAfter(plan, occurrencesUpTo(plan, now));
}

/// Copia con lo anterior a hoy marcado como procesado.
Recurrence _processed(Recurrence r, DateTime now, {int? next}) => Recurrence(
      id: r.id,
      type: r.type,
      frequency: r.frequency,
      startDate: r.startDate,
      accountId: r.accountId,
      kind: r.kind,
      amountCents: r.amountCents,
      previousAmountCents: r.previousAmountCents,
      toAccountId: r.toAccountId,
      category: r.category,
      note: r.note,
      nextIndex: next ?? occurrencesUpTo(r, now),
      auto: r.auto,
      principalCents: r.principalCents,
      rateBps: r.rateBps,
      months: r.months,
      payAccountId: r.payAccountId,
    );

List<Recurrence> _recurrences(DateTime now, String Function(String) id) {
  Recurrence mv(String key, MovementKind kind, int cents, String account, String note, DateTime start,
          {String category = 'other', String? to, Frequency frequency = Frequency.monthly, int? previous, bool auto = true}) =>
      Recurrence(
        id: id('rec-$key'),
        type: RecurrenceType.movement,
        frequency: frequency,
        startDate: start,
        accountId: id(account),
        kind: kind,
        amountCents: cents,
        previousAmountCents: previous,
        toAccountId: to == null ? null : id(to),
        category: kind == MovementKind.transfer ? transferCategory.id : category,
        note: note,
        auto: auto,
      );

  final mortgage = _mortgagePlan(now);

  return [
    _processed(mv('nomina', MovementKind.income, 240000, 'nomina', 'Nómina', _monthDay(now, -2, 1), category: 'salary'), now),
    _processed(mv('fondo', MovementKind.transfer, 30000, 'nomina', 'Aportación mensual al fondo', _monthDay(now, -2, 2), to: 'fondo'), now),
    _processed(mv('colchon', MovementKind.transfer, 25000, 'nomina', 'Ahorro automático', _monthDay(now, -2, 3), to: 'colchon'), now),
    _processed(mv('netflix', MovementKind.expense, 1299, 'tarjeta', 'Netflix', _monthDay(now, -2, 14),
        category: 'subscriptions', previous: 1199), now),
    _processed(mv('fibra', MovementKind.expense, 3590, 'nomina', 'Fibra y móvil', _monthDay(now, -2, 10), category: 'subscriptions'), now),
    mv('spotify', MovementKind.expense, 1099, 'tarjeta', 'Spotify', _monthDay(now, 1, 3), category: 'subscriptions'),
    mv('prime', MovementKind.expense, 4990, 'tarjeta', 'Amazon Prime', _monthDay(now, 2, 8),
        category: 'subscriptions', frequency: Frequency.yearly),
    // Pide confirmación y ya toca: para ver cómo se confirma o se salta.
    mv('padel', MovementKind.expense, 4500, 'nomina', 'Clases de pádel', _monthDay(now, 0, 1), category: 'leisure', auto: false),
    mortgage,
    _processed(_portatil(now), now),
  ];
}

/// Hipoteca de 163.456 € al 2,10 % a 30 años (cuota de unos 612 €), con las
/// cuotas pagadas hasta dejar unos 121.400 € pendientes. La cuenta de la
/// hipoteca usa exactamente lo pendiente según este plan.
Recurrence _mortgagePlan(DateTime now) {
  const principal = 16345600;
  const rate = 210;
  const months = 360;
  final rows = amortization(principal, rate, months);
  var paid = 1;
  for (var k = 1; k <= rows.length; k++) {
    if ((rows[k - 1].remainingCents - 12138055).abs() < (rows[paid - 1].remainingCents - 12138055).abs()) paid = k;
  }
  final lastPaid = now.day >= 5 ? DateTime(now.year, now.month) : DateTime(now.year, now.month - 1);
  return Recurrence(
    id: '${sampleIdPrefix}rec-hipoteca',
    type: RecurrenceType.installment,
    frequency: Frequency.monthly,
    startDate: DateTime(lastPaid.year, lastPaid.month - (paid - 1), 5),
    accountId: '${sampleIdPrefix}hipoteca',
    payAccountId: '${sampleIdPrefix}nomina',
    note: 'Hipoteca',
    principalCents: principal,
    rateBps: rate,
    months: months,
    nextIndex: paid,
  );
}

int _mortgagePending(DateTime now) {
  final plan = _mortgagePlan(now);
  return remainingAfter(plan, plan.nextIndex);
}
