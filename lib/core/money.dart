import 'package:intl/intl.dart';

/// Todos los importes de Nido se guardan como céntimos enteros (`int`) para
/// evitar errores de redondeo de `double`.

final _euro = NumberFormat.currency(locale: 'es_ES', symbol: '€', decimalDigits: 2);
final _euroCompact = NumberFormat.compactCurrency(locale: 'es_ES', symbol: '€', decimalDigits: 0);

// `+ 0.0` convierte el -0 de JavaScript (en web) en 0.
String formatCents(int cents) => _euro.format(cents / 100 + 0.0);

String formatCentsCompact(int cents) => _euroCompact.format(cents / 100 + 0.0);

/// Formato editable para rellenar un campo de texto: `1234,56`.
String centsToInput(int cents) {
  final abs = cents.abs();
  final text = '${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}';
  return cents < 0 ? '-$text' : text;
}

/// Convierte lo que escribe el usuario a céntimos.
///
/// Acepta `1234`, `1234,5`, `1.234,56`, `1,234.56`, `12.5` y `1.234.567`.
/// Devuelve `null` si el texto no es un importe válido.
int? parseCents(String input) {
  var s = input.replaceAll(RegExp(r'[\s€]'), '');
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  }

  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  String intPart;
  var decPart = '';

  if (lastComma >= 0 && lastDot >= 0) {
    // Hay ambos separadores: el último es el decimal.
    final decSep = lastComma > lastDot ? ',' : '.';
    final thousandsSep = decSep == ',' ? '.' : ',';
    final parts = s.split(decSep);
    if (parts.length != 2) return null;
    final groups = parts[0].split(thousandsSep);
    if (groups.skip(1).any((g) => g.length != 3)) return null;
    intPart = groups.join();
    decPart = parts[1];
  } else if (lastComma >= 0 || lastDot >= 0) {
    final sep = lastComma >= 0 ? ',' : '.';
    final parts = s.split(sep);
    final looksLikeThousands = parts.length > 2 || (sep == '.' && parts.last.length == 3);
    if (looksLikeThousands) {
      if (parts.skip(1).any((p) => p.length != 3)) return null;
      intPart = parts.join();
    } else {
      intPart = parts[0];
      decPart = parts[1];
    }
  } else {
    intPart = s;
  }

  if (intPart.isEmpty) intPart = '0';
  if (!RegExp(r'^\d{1,13}$').hasMatch(intPart)) return null;
  if (!RegExp(r'^\d{0,2}$').hasMatch(decPart)) return null;

  final cents = int.parse(intPart) * 100 + int.parse(decPart.padRight(2, '0'));
  return negative ? -cents : cents;
}
