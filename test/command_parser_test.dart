import 'package:flutter_test/flutter_test.dart';
import 'package:nido/domain/command_parser.dart';
import 'package:nido/models/account.dart';
import 'package:nido/models/movement.dart';
import 'package:nido/models/recurrence.dart';

const nomina = Account(id: 'nomina', name: 'Cuenta nómina', type: AccountType.bank, balanceCents: 0);
const colchon = Account(id: 'colchon', name: 'Colchón', type: AccountType.savings, balanceCents: 0);
const fondo = Account(id: 'fondo', name: 'Fondo indexado MSCI World', type: AccountType.investment, balanceCents: 0);
const tarjeta = Account(id: 'tarjeta', name: 'Tarjeta de crédito', type: AccountType.creditCard, balanceCents: 0);
const coche = Account(id: 'coche', name: 'Coche', type: AccountType.vehicle, balanceCents: 0);
const hipoteca = Account(id: 'hipoteca', name: 'Hipoteca', type: AccountType.mortgage, balanceCents: 0);
const accounts = [nomina, colchon, fondo, tarjeta, coche, hipoteca];
final now = DateTime(2026, 10, 21, 13, 30);

MovementCommand mv(String input) {
  final r = parseCommand(input, accounts: accounts, now: now);
  expect(r, isA<MovementCommand>(), reason: 'para "$input" salió $r ${r is CommandError ? r.message : ''}');
  return r as MovementCommand;
}

void main() {
  test('gasto con concepto que delata la categoría y cuenta por nombre', () {
    final m = mv('gasto 54,30 mercadona tarjeta');
    expect(m.kind, MovementKind.expense);
    expect(m.amountCents, 5430);
    expect(m.category, 'food');
    expect(m.account.id, 'tarjeta');
    expect(m.note, 'Mercadona');
  });

  test('sin verbo es un gasto, y la cuenta por defecto es la corriente', () {
    final m = mv('12,50 cena con amigos');
    expect(m.kind, MovementKind.expense);
    expect(m.amountCents, 1250);
    expect(m.category, 'restaurants');
    expect(m.account.id, 'nomina');
    expect(m.note, 'Cena con amigos');
  });

  test('"con <cuenta>" elige la cuenta', () {
    final m = mv('gasto 30 gasolina con la tarjeta');
    expect(m.account.id, 'tarjeta');
    expect(m.category, 'transport');
    expect(m.note, 'Gasolina');
  });

  test('una palabra de concepto no se confunde con una cuenta de bienes', () {
    final m = mv('gasto 45 taller coche');
    expect(m.account.id, 'nomina');
    expect(m.note, 'Taller coche');
  });

  test('ingreso de nómina', () {
    final m = mv('ingreso 2400 nomina');
    expect(m.kind, MovementKind.income);
    expect(m.amountCents, 240000);
    expect(m.category, 'salary');
    expect(m.account.id, 'nomina');
  });

  test('categoría por nombre o con #', () {
    expect(mv('gasto 20 ocio entradas').category, 'leisure');
    expect(mv('gasto 20 regalo #ocio').category, 'leisure');
    expect(mv('gasto 20 cosas varias').category, 'other');
  });

  test('traspasos con > y con "a"', () {
    final a = mv('traspaso 300 nomina > fondo');
    expect(a.kind, MovementKind.transfer);
    expect(a.account.id, 'nomina');
    expect(a.to!.id, 'fondo');
    final b = mv('traspaso 612,40 de nómina a hipoteca');
    expect(b.account.id, 'nomina');
    expect(b.to!.id, 'hipoteca');
    expect(b.amountCents, 61240);
    // Sin origen: sale de la cuenta corriente.
    expect(mv('traspaso 200 a colchon').account.id, 'nomina');
  });

  test('errores claros', () {
    expect(parseCommand('gasto mercadona', accounts: accounts, now: now), isA<CommandError>());
    expect(parseCommand('traspaso 10 nomina', accounts: accounts, now: now), isA<CommandError>());
    expect(parseCommand('traspaso 10 nomina > nomina', accounts: accounts, now: now), isA<CommandError>());
    expect(parseCommand('traspaso 10 nomina > luna', accounts: accounts, now: now), isA<CommandError>());
    expect(parseCommand('gasto 5 café', accounts: const [], now: now), isA<CommandError>());
  });

  test('fechas', () {
    expect(mv('ayer 3,20 cafe').date.day, 20);
    expect(mv('gasto 10 cine 15/10').date, DateTime(2026, 10, 15, 13, 30));
    // Sin año y en el futuro: el año pasado.
    expect(mv('gasto 10 regalo 28/12').date.year, 2025);
    expect(mv('gasto 10 cine').date, now);
  });

  test('órdenes que no son movimientos', () {
    expect(parseCommand('', accounts: accounts, now: now), isA<EmptyCommand>());
    expect((parseCommand('ir cuentas', accounts: accounts, now: now) as NavigateCommand).tab, 1);
    expect((parseCommand('objetivos', accounts: accounts, now: now) as NavigateCommand).tab, 4);
    expect((parseCommand('ir suscripciones', accounts: accounts, now: now) as NavigateCommand).tab, 3);
    expect((parseCommand('ocultar', accounts: accounts, now: now) as PrivacyCommand).hide, isTrue);
    expect((parseCommand('mostrar', accounts: accounts, now: now) as PrivacyCommand).hide, isFalse);
    expect(parseCommand('ayuda', accounts: accounts, now: now), isA<HelpCommand>());
  });

  test('programar con "cada"', () {
    final r = parseCommand('cada mes 12,99 netflix día 14', accounts: accounts, now: now) as RecurrenceCommand;
    expect(r.frequency, Frequency.monthly);
    expect(r.day, 14);
    expect(r.movement.amountCents, 1299);
    expect(r.movement.category, 'subscriptions');
    expect(r.movement.note, 'Netflix');

    final w = parseCommand('cada semana 30 compra lunes', accounts: accounts, now: now) as RecurrenceCommand;
    expect(w.frequency, Frequency.weekly);
    expect(w.day, 1);
    expect(w.movement.category, 'food');

    final y = parseCommand('cada año 49,90 amazon prime con tarjeta', accounts: accounts, now: now) as RecurrenceCommand;
    expect(y.frequency, Frequency.yearly);
    expect(y.day, isNull);
    expect(y.movement.account.id, 'tarjeta');

    final t = parseCommand('cada mes traspaso 300 nomina > fondo el 2', accounts: accounts, now: now) as RecurrenceCommand;
    expect(t.movement.kind, MovementKind.transfer);
    expect(t.day, 2);

    expect(parseCommand('cada siglo 5 cafe', accounts: accounts, now: now), isA<CommandError>());
    expect(parseCommand('cada mes netflix', accounts: accounts, now: now), isA<CommandError>());
  });
}
