import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../privacy.dart';
import '../theme.dart';

/// Opción de un desplegable de cuentas. Con varias cuentas del mismo nombre
/// (dos "Cuenta de ahorro" de la plantilla) añade la entidad y el saldo, y si
/// aun así coinciden, un número, para que se puedan distinguir.
DropdownMenuItem<String> accountMenuItem(BuildContext context, Account a, List<Account> all) {
  final (:name, :detail) = _label(context, a, all);
  return DropdownMenuItem(
    value: a.id,
    child: Row(children: [
      Icon(a.type.icon, size: 20, color: a.isLiability ? Crt.redText : Crt.green),
      const SizedBox(width: 12),
      Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
      if (detail.isNotEmpty) ...[
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            detail.join(' · '),
            overflow: TextOverflow.ellipsis,
            style: mono(size: 13, color: Crt.grey),
          ),
        ),
      ],
    ]),
  );
}

/// Lo mismo en una sola línea, para chips y textos.
String accountLabel(BuildContext context, Account a, List<Account> all) {
  final (:name, :detail) = _label(context, a, all);
  return detail.isEmpty ? name : '$name · ${detail.join(' · ')}';
}

({String name, List<String> detail}) _label(BuildContext context, Account a, List<Account> all) {
  final same = all.where((o) => o.name.trim().toLowerCase() == a.name.trim().toLowerCase()).toList();
  final detail = <String>[
    if (a.institution.isNotEmpty) a.institution,
    if (same.length > 1) context.money(a.balanceCents),
  ];
  final twins = same.where((o) => o.institution == a.institution && o.balanceCents == a.balanceCents).toList();
  return (name: twins.length > 1 ? '${a.name} ${twins.indexOf(a) + 1}' : a.name, detail: detail);
}

/// [base], o "[base] 2", "[base] 3"… si ya hay una cuenta con ese nombre.
String uniqueAccountName(String base, Iterable<Account> accounts) {
  final taken = accounts.map((a) => a.name.trim().toLowerCase()).toSet();
  if (!taken.contains(base.toLowerCase())) return base;
  var n = 2;
  while (taken.contains('$base $n'.toLowerCase())) {
    n++;
  }
  return '$base $n';
}
