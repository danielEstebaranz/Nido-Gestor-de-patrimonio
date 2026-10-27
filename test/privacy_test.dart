import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nido/ui/privacy.dart';
import 'package:nido/ui/theme.dart';
import 'package:nido/ui/widgets/common.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_ES'));

  Widget app(PrivacyController privacy) => PrivacyScope(
        controller: privacy,
        child: MaterialApp(
          theme: nidoTheme(),
          // `const` a propósito: debe repintarse igual al cambiar el modo privado.
          home: const Scaffold(body: Column(children: [SignedAmount(123456), _Balance()])),
        ),
      );

  testWidgets('el ojo oculta y vuelve a mostrar los importes', (tester) async {
    final privacy = PrivacyController.memory();
    await tester.pumpWidget(app(privacy));
    expect(find.textContaining('1.234,56'), findsNWidgets(2));
    expect(find.textContaining(hiddenAmount), findsNothing);

    privacy.toggle();
    await tester.pump();
    expect(find.textContaining('1.234,56'), findsNothing);
    expect(find.textContaining(hiddenAmount), findsNWidgets(2));

    privacy.toggle();
    await tester.pump();
    expect(find.textContaining('1.234,56'), findsNWidgets(2));
  });

  test('sin PrivacyScope los importes se ven', () {
    expect(PrivacyController.memory().hidden, isFalse);
  });
}

class _Balance extends StatelessWidget {
  const _Balance();

  @override
  Widget build(BuildContext context) => Text(context.money(123456));
}
