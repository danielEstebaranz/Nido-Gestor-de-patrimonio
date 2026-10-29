import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nido/models/account.dart';
import 'package:nido/ui/widgets/account_item.dart';

Account acc(String id, String name, int cents, {String institution = ''}) =>
    Account(id: id, name: name, type: AccountType.savings, balanceCents: cents, institution: institution);

void main() {
  Future<List<String>> labels(WidgetTester tester, List<Account> all) async {
    late List<String> out;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        out = [for (final a in all) accountLabel(context, a, all)];
        return const SizedBox();
      }),
    ));
    return out;
  }

  testWidgets('dos cuentas con el mismo nombre se distinguen por saldo y entidad', (tester) async {
    final out = await labels(tester, [
      acc('a', 'Cuenta de ahorro', 120000, institution: 'ING'),
      acc('b', 'Cuenta de ahorro', 5000),
      acc('c', 'Efectivo', 3000),
    ]);
    expect(out[0], startsWith('Cuenta de ahorro · ING · 1.200'));
    expect(out[1], startsWith('Cuenta de ahorro · 50'));
    // Sin nombre repetido no se añade nada.
    expect(out[2], 'Efectivo');
  });

  testWidgets('si coinciden en todo, se numeran', (tester) async {
    final out = await labels(tester, [acc('a', 'Cuenta de ahorro', 0), acc('b', 'Cuenta de ahorro', 0)]);
    expect(out[0], startsWith('Cuenta de ahorro 1 · '));
    expect(out[1], startsWith('Cuenta de ahorro 2 · '));
  });

  test('las plantillas numeran el nombre si ya existe', () {
    final existing = [acc('a', 'Cuenta de ahorro', 0), acc('b', 'Cuenta de ahorro 2', 0)];
    expect(uniqueAccountName('Cuenta de ahorro', existing), 'Cuenta de ahorro 3');
    expect(uniqueAccountName('Efectivo', existing), 'Efectivo');
  });
}
