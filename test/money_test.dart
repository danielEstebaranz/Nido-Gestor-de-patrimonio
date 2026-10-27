import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nido/core/money.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_ES'));

  group('parseCents', () {
    final cases = <String, int?>{
      '1234': 123400,
      '1234,5': 123450,
      '1234,56': 123456,
      '1.234,56': 123456,
      '1,234.56': 123456,
      '1.234': 123400,
      '1.234.567': 123456700,
      '12.5': 1250,
      '0,99': 99,
      ',5': 50,
      ' 15 € ': 1500,
      '-20,10': -2010,
      '': null,
      'abc': null,
      '1,234': null,
      '1,2,3': null,
      '12,345': null,
      '1.23.45': null,
      '1.234,5.6': null,
    };
    cases.forEach((input, expected) {
      test('"$input" -> $expected', () => expect(parseCents(input), expected));
    });
  });

  test('centsToInput vuelve a leerse igual', () {
    for (final cents in [0, 5, 99, 100, 123456, -2010]) {
      expect(parseCents(centsToInput(cents)), cents);
    }
  });

  test('formatCents usa formato español', () {
    expect(formatCents(123456).replaceAll(' ', ' '), '1.234,56 €');
    expect(formatCents(12345678).replaceAll(' ', ' '), '123.456,78 €');
  });
}
