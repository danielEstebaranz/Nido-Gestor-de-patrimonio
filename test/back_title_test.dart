import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nido/ui/widgets/common.dart';

void main() {
  testWidgets('el "<" del título de un formulario cierra la hoja', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => FormFrame(title: 'Editar objetivo', onSave: () {}, children: const [Text('campo')]),
          ),
          child: const Text('abrir'),
        ),
      ),
    ));
    // Cursor parpadeante: pumpAndSettle no acabaría nunca.
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('EDITAR OBJETIVO'), findsOneWidget);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('EDITAR OBJETIVO'), findsNothing);
  });
}
