import '../core/money.dart';
import '../models/account.dart';
import '../models/movement.dart';
import '../models/recurrence.dart';

/// Intérprete de la línea de comandos de Nido. Convierte frases como
/// `gasto 54,30 mercadona tarjeta` o `traspaso 300 nomina > fondo` en un
/// movimiento listo para guardar, sin formularios.

sealed class CommandResult {
  const CommandResult();
}

/// Línea vacía: no hay nada que mostrar todavía.
final class EmptyCommand extends CommandResult {
  const EmptyCommand();
}

final class MovementCommand extends CommandResult {
  const MovementCommand({
    required this.kind,
    required this.amountCents,
    required this.account,
    required this.category,
    required this.note,
    required this.date,
    this.to,
  });

  final MovementKind kind;
  final int amountCents;
  final Account account;
  final Account? to;
  final String category;
  final String note;
  final DateTime date;

  Movement toMovement() => Movement(
        id: '',
        kind: kind,
        amountCents: amountCents,
        accountId: account.id,
        toAccountId: to?.id,
        category: category,
        note: note,
        date: date,
      );
}

/// Programar algo que se repite: `cada mes 12,99 netflix día 14`.
final class RecurrenceCommand extends CommandResult {
  const RecurrenceCommand({required this.frequency, required this.day, required this.movement});

  final Frequency frequency;

  /// Día del mes (1-31) o de la semana (1 = lunes), o null para empezar hoy.
  final int? day;
  final MovementCommand movement;
}

/// Ir a una pestaña: 0 resumen, 1 cuentas, 2 movimientos, 3 recurrentes, 4 objetivos.
final class NavigateCommand extends CommandResult {
  const NavigateCommand(this.tab);
  final int tab;
}

final class PrivacyCommand extends CommandResult {
  const PrivacyCommand({required this.hide});
  final bool hide;
}

final class HelpCommand extends CommandResult {
  const HelpCommand();
}

final class CommandError extends CommandResult {
  const CommandError(this.message);
  final String message;
}

String _norm(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

const _expenseVerbs = {'gasto', 'gaste', 'gastos', 'pago', 'pague', 'compra', 'compre', 'g', '-'};
const _incomeVerbs = {'ingreso', 'ingrese', 'ingresos', 'cobro', 'cobre', 'i', '+'};
const _transferVerbs = {'traspaso', 'traspasa', 'transferencia', 'transfiero', 'transferir', 'mover', 'muevo', 't'};
const _stopwords = {'de', 'del', 'en', 'con', 'el', 'la', 'los', 'las', 'un', 'una', 'por', 'para', 'y', 'euros', 'euro', 'eur', '€'};
const _accountMarkers = {'con', 'en', 'desde', 'de', 'del'};
const _transferSplit = {'>', '->', '=>', 'a', 'al', 'hacia'};

const _tabs = {
  'resumen': 0, 'inicio': 0, 'cuentas': 1, 'cuenta': 1, 'movimientos': 2, 'gastos': 2,
  'recurrentes': 3, 'suscripciones': 3, 'plazos': 3, 'programaciones': 3, 'fijos': 3, 'prestamos': 3,
  'objetivos': 4, 'metas': 4,
};

const _frequencies = {
  'semana': Frequency.weekly, 'semanal': Frequency.weekly,
  'mes': Frequency.monthly, 'mensual': Frequency.monthly,
  'trimestre': Frequency.quarterly, 'trimestral': Frequency.quarterly,
  'año': Frequency.yearly, 'ano': Frequency.yearly, 'anual': Frequency.yearly,
};

const _weekdays = {'lunes': 1, 'martes': 2, 'miercoles': 3, 'jueves': 4, 'viernes': 5, 'sabado': 6, 'domingo': 7};

/// Palabras que delatan la categoría de un gasto.
const _expenseKeywords = <String, String>{
  'mercadona': 'food', 'lidl': 'food', 'carrefour': 'food', 'aldi': 'food', 'dia': 'food', 'eroski': 'food',
  'alcampo': 'food', 'consum': 'food', 'supermercado': 'food', 'super': 'food', 'compra': 'food', 'fruta': 'food',
  'fruteria': 'food', 'panaderia': 'food', 'carniceria': 'food', 'comida': 'food',
  'restaurante': 'restaurants', 'bar': 'restaurants', 'cena': 'restaurants', 'cenar': 'restaurants',
  'comer': 'restaurants', 'cafe': 'restaurants', 'cafeteria': 'restaurants', 'desayuno': 'restaurants',
  'menu': 'restaurants', 'pizza': 'restaurants', 'burger': 'restaurants', 'kebab': 'restaurants',
  'glovo': 'restaurants', 'justeat': 'restaurants', 'tapas': 'restaurants', 'cañas': 'restaurants', 'canas': 'restaurants',
  'gasolina': 'transport', 'gasoil': 'transport', 'diesel': 'transport', 'repsol': 'transport', 'cepsa': 'transport',
  'metro': 'transport', 'bus': 'transport', 'autobus': 'transport', 'taxi': 'transport', 'uber': 'transport',
  'cabify': 'transport', 'renfe': 'transport', 'tren': 'transport', 'parking': 'transport', 'peaje': 'transport',
  'itv': 'transport', 'bicimad': 'transport',
  'luz': 'bills', 'agua': 'bills', 'gas': 'bills', 'iberdrola': 'bills', 'endesa': 'bills', 'naturgy': 'bills',
  'electricidad': 'bills', 'butano': 'bills',
  'netflix': 'subscriptions', 'spotify': 'subscriptions', 'hbo': 'subscriptions', 'max': 'subscriptions',
  'disney': 'subscriptions', 'prime': 'subscriptions', 'youtube': 'subscriptions', 'icloud': 'subscriptions',
  'movil': 'subscriptions', 'fibra': 'subscriptions', 'internet': 'subscriptions', 'telefono': 'subscriptions',
  'alquiler': 'home', 'comunidad': 'home', 'muebles': 'home', 'ikea': 'home', 'reforma': 'home', 'fontanero': 'home',
  'farmacia': 'health', 'medico': 'health', 'dentista': 'health', 'fisio': 'health', 'fisioterapeuta': 'health',
  'optica': 'health', 'seguro': 'health',
  'cine': 'leisure', 'concierto': 'leisure', 'libro': 'leisure', 'libros': 'leisure', 'juego': 'leisure',
  'steam': 'leisure', 'viaje': 'leisure', 'hotel': 'leisure', 'gimnasio': 'leisure', 'gym': 'leisure',
  'entradas': 'leisure', 'teatro': 'leisure', 'museo': 'leisure',
  'ropa': 'shopping', 'zara': 'shopping', 'primark': 'shopping', 'zapatillas': 'shopping', 'amazon': 'shopping',
  'regalo': 'shopping', 'decathlon': 'shopping', 'mediamarkt': 'shopping',
  'curso': 'education', 'academia': 'education', 'matricula': 'education', 'universidad': 'education',
  'impuesto': 'taxes', 'impuestos': 'taxes', 'irpf': 'taxes', 'ibi': 'taxes', 'hacienda': 'taxes', 'multa': 'taxes',
};

const _incomeKeywords = <String, String>{
  'nomina': 'salary', 'sueldo': 'salary', 'salario': 'salary', 'paga': 'salary',
  'factura': 'freelance', 'freelance': 'freelance', 'extra': 'freelance', 'proyecto': 'freelance',
  'dividendo': 'dividends', 'dividendos': 'dividends', 'intereses': 'dividends', 'interes': 'dividends',
  'cupon': 'dividends',
  'alquiler': 'rent', 'inquilino': 'rent',
  'regalo': 'gift', 'cumpleaños': 'gift', 'cumpleanos': 'gift',
};

class _Token {
  _Token(this.raw) : n = _norm(raw);
  final String raw;
  final String n;
  bool used = false;
}

CommandResult parseCommand(String input, {required List<Account> accounts, required DateTime now}) {
  final tokens = input.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).map(_Token.new).toList();
  if (tokens.isEmpty) return const EmptyCommand();
  final first = tokens.first.n;

  // "cada mes 12,99 netflix día 14": una programación.
  if (first == 'cada') {
    final frequency = tokens.length > 1 ? _frequencies[tokens[1].n] : null;
    if (frequency == null) return const CommandError('¿Cada cuánto? Prueba "cada mes", "cada semana" o "cada año".');
    final rest = tokens.skip(2).toList();
    int? day;
    for (var i = 0; i < rest.length; i++) {
      final weekday = _weekdays[rest[i].n];
      if (frequency == Frequency.weekly && weekday != null) {
        day = weekday;
        rest.removeAt(i);
        break;
      }
      if ({'dia', 'el', 'los'}.contains(rest[i].n) && i + 1 < rest.length) {
        final n = int.tryParse(rest[i + 1].n);
        if (n != null && n >= 1 && n <= 31) {
          day = n;
          rest.removeRange(i, i + 2);
          break;
        }
      }
    }
    final inner = parseCommand(rest.map((t) => t.raw).join(' '), accounts: accounts, now: now);
    return switch (inner) {
      final MovementCommand m => RecurrenceCommand(frequency: frequency, day: day, movement: m),
      EmptyCommand() => const CommandError('Falta el importe. Ejemplo: cada mes 12,99 netflix día 14'),
      CommandError() => inner,
      _ => const CommandError('Solo se pueden programar gastos, ingresos y traspasos.'),
    };
  }

  // Órdenes que no son movimientos.
  if ({'ayuda', 'help', '?', 'comandos'}.contains(first)) return const HelpCommand();
  if ({'ocultar', 'oculta', 'esconder', 'privado'}.contains(first)) return const PrivacyCommand(hide: true);
  if ({'mostrar', 'muestra', 'enseñar', 'ensenar'}.contains(first)) return const PrivacyCommand(hide: false);
  if ({'ir', 've', 'abre', 'abrir'}.contains(first) || (tokens.length == 1 && _tabs.containsKey(first))) {
    final target = tokens.map((t) => _tabs[t.n]).whereType<int>().firstOrNull;
    return target == null
        ? const CommandError('¿A dónde? Prueba "ir cuentas", "ir movimientos" u "ir objetivos".')
        : NavigateCommand(target);
  }

  // Tipo de movimiento: por el verbo; sin verbo, un gasto.
  var kind = MovementKind.expense;
  if (_expenseVerbs.contains(first)) {
    tokens.first.used = true;
  } else if (_incomeVerbs.contains(first)) {
    kind = MovementKind.income;
    tokens.first.used = true;
  } else if (_transferVerbs.contains(first)) {
    kind = MovementKind.transfer;
    tokens.first.used = true;
  }

  // Fecha.
  var date = now;
  for (final t in tokens.where((t) => !t.used)) {
    final d = _parseDate(t.n, now);
    if (d != null) {
      date = DateTime(d.year, d.month, d.day, now.hour, now.minute);
      t.used = true;
      break;
    }
  }

  // Importe: la primera palabra que se lea como dinero.
  int? amount;
  for (final t in tokens.where((t) => !t.used)) {
    if (!RegExp(r'\d').hasMatch(t.n)) continue;
    final c = parseCents(t.raw.replaceAll('€', ''));
    if (c != null) {
      amount = c.abs();
      t.used = true;
      break;
    }
  }
  if (amount == null) return const CommandError('Falta el importe. Ejemplo: gasto 12,50 café');
  if (amount == 0) return const CommandError('El importe debe ser mayor que 0.');
  if (accounts.isEmpty) return const CommandError('Crea primero una cuenta en la pestaña Cuentas.');

  if (kind == MovementKind.transfer) return _transfer(tokens, amount, date, accounts);

  final keywords = kind == MovementKind.expense ? _expenseKeywords : _incomeKeywords;
  final categories = categoriesFor(kind);

  // Categoría: #ocio, el nombre de una categoría o una palabra que la delate.
  String? category;
  for (final t in tokens.where((t) => !t.used)) {
    final word = t.n.startsWith('#') ? t.n.substring(1) : t.n;
    final byLabel = categories.where((c) => _norm(c.label).split(' ').first == word || c.id == word).firstOrNull;
    if (byLabel != null && byLabel.id != 'other') {
      category = byLabel.id;
      t.used = true; // el nombre de la categoría no forma parte del concepto
      break;
    }
  }
  category ??= tokens.where((t) => !t.used).map((t) => keywords[t.n]).whereType<String>().firstOrNull;

  // Cuenta: @nombre, "con/en/desde <nombre>" o una palabra que solo encaje con una cuenta.
  final eligible = accounts.where((a) => kind == MovementKind.expense
      ? (a.group == AccountGroup.liquidity || a.type == AccountType.creditCard)
      : (a.group == AccountGroup.liquidity || a.group == AccountGroup.investments)).toList();
  Account? account;
  for (var i = 0; i < tokens.length && account == null; i++) {
    final t = tokens[i];
    if (t.used) continue;
    if (t.n.startsWith('@')) {
      account = _matchAccount([t.n.substring(1)], accounts);
      if (account != null) t.used = true;
    } else if (_accountMarkers.contains(t.n) && i + 1 < tokens.length) {
      for (var len = 3; len >= 1 && account == null; len--) {
        final slice = tokens.skip(i + 1).take(len).where((x) => !x.used).toList();
        if (slice.length != len) continue;
        final found = _matchAccount(slice.map((x) => x.n).toList(), accounts);
        if (found != null) {
          account = found;
          t.used = true;
          for (final x in slice) {
            x.used = true;
          }
        }
      }
    }
  }
  if (account == null) {
    for (final t in tokens.where((t) => !t.used && !keywords.containsKey(t.n) && !_stopwords.contains(t.n))) {
      final found = _matchAccount([t.n], eligible);
      if (found != null) {
        account = found;
        t.used = true;
        break;
      }
    }
  }
  account ??= _defaultAccount(accounts);

  return MovementCommand(
    kind: kind,
    amountCents: amount,
    account: account,
    category: category ?? 'other',
    note: _note(tokens),
    date: date,
  );
}

CommandResult _transfer(List<_Token> tokens, int amount, DateTime date, List<Account> accounts) {
  final rest = tokens.where((t) => !t.used).toList();
  final split = rest.indexWhere((t) => _transferSplit.contains(t.n));
  if (split < 0) return const CommandError('Indica origen y destino: traspaso 300 nómina > fondo');
  bool keep(_Token t) => !{'de', 'del', 'desde', 'la', 'el', 'mi'}.contains(t.n);
  final fromWords = rest.take(split).where(keep).map((t) => t.n).toList();
  final toWords = rest.skip(split + 1).where(keep).map((t) => t.n).toList();
  final from = fromWords.isEmpty ? _defaultAccount(accounts) : _matchAccount(fromWords, accounts);
  final to = toWords.isEmpty ? null : _matchAccount(toWords, accounts);
  if (from == null) return CommandError('No encuentro la cuenta de origen "${fromWords.join(' ')}".');
  if (to == null) return CommandError('No encuentro la cuenta de destino "${toWords.join(' ')}".');
  if (from.id == to.id) return const CommandError('El origen y el destino son la misma cuenta.');
  return MovementCommand(
    kind: MovementKind.transfer,
    amountCents: amount,
    account: from,
    to: to,
    category: transferCategory.id,
    note: '',
    date: date,
  );
}

/// La cuenta cuyo nombre contiene todas las palabras (como prefijo de alguna
/// de sus palabras). Si hay varias, la que coincide palabra por palabra.
Account? _matchAccount(List<String> words, List<Account> accounts) {
  final query = words.where((w) => w.length >= 2 && !_stopwords.contains(w)).toList();
  if (query.isEmpty) return null;
  final hits = accounts.where((a) {
    final nameWords = _norm(a.name).split(RegExp(r'[\s\-_/.,]+'));
    return query.every((q) => nameWords.any((w) => w.length >= 2 && w.startsWith(q) && (q.length >= 3 || w == q)));
  }).toList();
  if (hits.length == 1) return hits.single;
  if (hits.isEmpty) return null;
  final exact = hits.where((a) => query.every((q) => _norm(a.name).split(RegExp(r'\s+')).contains(q))).toList();
  return exact.length == 1 ? exact.single : null;
}

/// Cuenta por defecto: la corriente; si no hay, otra de liquidez; si no, la primera.
Account _defaultAccount(List<Account> accounts) =>
    accounts.where((a) => a.type == AccountType.bank).firstOrNull ??
    accounts.where((a) => a.group == AccountGroup.liquidity).firstOrNull ??
    accounts.first;

DateTime? _parseDate(String word, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  switch (word) {
    case 'hoy':
      return today;
    case 'ayer':
      return today.subtract(const Duration(days: 1));
    case 'anteayer':
      return today.subtract(const Duration(days: 2));
  }
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?$').firstMatch(word);
  if (m == null) return null;
  final day = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  var year = m[3] == null ? now.year : int.parse(m[3]!);
  if (year < 100) year += 2000;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime(year, month, day);
  // Sin año y en el futuro: se refiere al año pasado (p. ej. 28/12 en enero).
  if (m[3] == null && d.isAfter(today)) return DateTime(year - 1, month, day);
  return d;
}

/// Lo que sobra es el concepto. Se quitan preposiciones sueltas al principio
/// y al final, pero no las de dentro: "cena con amigos" se queda entera.
String _note(List<_Token> tokens) {
  final rest = tokens.where((t) => !t.used).toList();
  while (rest.isNotEmpty && _stopwords.contains(rest.first.n)) {
    rest.removeAt(0);
  }
  while (rest.isNotEmpty && _stopwords.contains(rest.last.n)) {
    rest.removeLast();
  }
  if (rest.isEmpty) return '';
  final text = rest.map((t) => t.raw).join(' ');
  return text[0].toUpperCase() + text.substring(1);
}
