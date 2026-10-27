import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/portfolio.dart';
import '../domain/recurrence_engine.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../models/movement.dart';
import '../models/recurrence.dart';
import '../models/snapshot.dart';
import 'sample_data.dart';

/// Lectura de cuentas con el origen de los datos, para no escribir la foto
/// mensual a partir de una caché local todavía vacía.
class AccountsResult {
  const AccountsResult(this.accounts, {required this.fromCache});
  final List<Account> accounts;
  final bool fromCache;
}

/// Acceso a Firestore. Todo cuelga de `users/{uid}`, así que las reglas de
/// seguridad solo tienen que comprobar que el uid es el del usuario.
///
/// Las escrituras se aplican al instante en la caché local y se sincronizan
/// cuando hay conexión; el `Future` solo se completa al confirmarlas el servidor.
class NidoRepository {
  NidoRepository(this._db, this.uid);

  final FirebaseFirestore _db;
  final String uid;

  DocumentReference<Map<String, dynamic>> get _user => _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _accounts => _user.collection('accounts');
  CollectionReference<Map<String, dynamic>> get _movements => _user.collection('movements');
  CollectionReference<Map<String, dynamic>> get _goals => _user.collection('goals');
  CollectionReference<Map<String, dynamic>> get _snapshots => _user.collection('snapshots');
  CollectionReference<Map<String, dynamic>> get _recurrences => _user.collection('recurrences');

  static final _now = FieldValue.serverTimestamp();

  // ---------- Lecturas ----------

  /// Con cambios de metadatos: así llega un aviso cuando se pierde o se
  /// recupera la conexión con el servidor, aunque los datos no cambien.
  Stream<AccountsResult> watchAccounts() => _accounts.orderBy('name').snapshots(includeMetadataChanges: true).map(
        (s) => AccountsResult(s.docs.map(Account.fromDoc).toList(), fromCache: s.metadata.isFromCache),
      );

  Stream<List<Movement>> watchMovements(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return _movements
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Movement.fromDoc).toList());
  }

  /// Movimientos desde [since], más recientes primero (indicadores y "últimos
  /// movimientos"). Sin límite: si se cortara, el mes más antiguo saldría
  /// incompleto y bajaría el gasto medio.
  Stream<List<Movement>> watchRecentMovements(DateTime since) => _movements
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
      .orderBy('date', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Movement.fromDoc).toList());

  Stream<List<Goal>> watchGoals() =>
      _goals.orderBy('name').snapshots().map((s) => s.docs.map(Goal.fromDoc).toList());

  /// Últimos 24 meses, del más antiguo al más reciente. Se ordena en ascendente
  /// (el emulador no admite orden descendente por id) y se recorta aquí: es un
  /// documento pequeño por mes.
  Stream<List<NetWorthSnapshot>> watchSnapshots() =>
      _snapshots.orderBy(FieldPath.documentId).snapshots().map((s) {
        final all = s.docs.map(NetWorthSnapshot.fromDoc).toList();
        return all.length > 24 ? all.sublist(all.length - 24) : all;
      });

  // ---------- Cuentas ----------

  Future<void> createAccount({
    required String name,
    required AccountType type,
    required String institution,
    required int balanceCents,
  }) =>
      _accounts.doc().set({
        'name': name,
        'type': type.name,
        'institution': institution,
        'balanceCents': balanceCents,
        'createdAt': _now,
        'updatedAt': _now,
      });

  Future<void> updateAccount(
    String id, {
    required String name,
    required AccountType type,
    required String institution,
    required int balanceCents,
  }) =>
      _accounts.doc(id).update({
        'name': name,
        'type': type.name,
        'institution': institution,
        'balanceCents': balanceCents,
        'updatedAt': _now,
      });

  /// Borra la cuenta y la desvincula de los objetivos. Los movimientos se
  /// conservan como historial.
  Future<void> deleteAccount(String id, Iterable<Goal> goals) {
    final batch = _db.batch()..delete(_accounts.doc(id));
    for (final g in goals.where((g) => g.accountIds.contains(id))) {
      batch.update(_goals.doc(g.id), {
        'accountIds': FieldValue.arrayRemove([id]),
        'updatedAt': _now,
      });
    }
    return batch.commit();
  }

  // ---------- Movimientos ----------
  //
  // Cada movimiento ajusta los saldos con FieldValue.increment dentro del mismo
  // batch: si dos dispositivos registran gastos a la vez sin conexión, al
  // sincronizar se suman ambos en lugar de pisarse.

  Future<void> addMovement(Movement m, Map<String, Account> accounts) {
    final batch = _db.batch()
      ..set(_movements.doc(), {...m.toMap(), 'createdAt': _now, 'updatedAt': _now});
    _applyChanges(batch, balanceChanges(m, accounts));
    return batch.commit();
  }

  Future<void> updateMovement(Movement before, Movement after, Map<String, Account> accounts) {
    final batch = _db.batch()..update(_movements.doc(before.id), {...after.toMap(), 'updatedAt': _now});
    _applyChanges(batch, diffChanges(balanceChanges(before, accounts), balanceChanges(after, accounts)));
    return batch.commit();
  }

  Future<void> deleteMovement(Movement m, Map<String, Account> accounts) {
    final batch = _db.batch()..delete(_movements.doc(m.id));
    _applyChanges(batch, balanceChanges(m, accounts).map((id, v) => MapEntry(id, -v)));
    return batch.commit();
  }

  void _applyChanges(WriteBatch batch, Map<String, int> changes) {
    changes.forEach((id, delta) {
      batch.update(_accounts.doc(id), {'balanceCents': FieldValue.increment(delta), 'updatedAt': _now});
    });
  }

  // ---------- Objetivos ----------

  Map<String, dynamic> _goalFields(String name, int targetCents, int savedCents, List<String> accountIds,
          DateTime? deadline, [int? targetMonths]) =>
      {
        'name': name,
        'targetCents': targetCents,
        'targetMonths': targetMonths,
        'savedCents': savedCents,
        'accountIds': accountIds,
        'deadline': deadline == null ? null : Timestamp.fromDate(deadline),
        'updatedAt': _now,
      };

  Future<void> createGoal({
    required String name,
    required int targetCents,
    required int savedCents,
    required List<String> accountIds,
    DateTime? deadline,
    int? targetMonths,
  }) =>
      _goals.doc().set({..._goalFields(name, targetCents, savedCents, accountIds, deadline, targetMonths), 'createdAt': _now});

  Future<void> updateGoal(
    String id, {
    required String name,
    required int targetCents,
    required int savedCents,
    required List<String> accountIds,
    DateTime? deadline,
    int? targetMonths,
  }) =>
      _goals.doc(id).update(_goalFields(name, targetCents, savedCents, accountIds, deadline, targetMonths));

  Future<void> contributeToGoal(String id, int cents) =>
      _goals.doc(id).update({'savedCents': FieldValue.increment(cents), 'updatedAt': _now});

  Future<void> deleteGoal(String id) => _goals.doc(id).delete();

  // ---------- Programaciones y plazos ----------

  Stream<List<Recurrence>> watchRecurrences() =>
      _recurrences.snapshots().map((s) => s.docs.map(Recurrence.fromDoc).toList());

  Map<String, dynamic> _recurrenceFields(Recurrence r) {
    final inst = r.isInstallment;
    return {
      'type': r.type.name,
      'frequency': r.frequency.name,
      'startDate': Timestamp.fromDate(r.startDate),
      'accountId': r.accountId,
      'kind': inst ? null : r.kind.name,
      'amountCents': inst ? null : r.amountCents,
      'previousAmountCents': r.previousAmountCents,
      'toAccountId': !inst && r.kind == MovementKind.transfer ? r.toAccountId : null,
      'category': inst ? null : r.category,
      'note': r.note,
      'count': r.count,
      'endDate': r.endDate == null ? null : Timestamp.fromDate(r.endDate!),
      'nextIndex': r.nextIndex,
      'auto': r.auto,
      'principalCents': inst ? r.principalCents : null,
      'rateBps': inst ? r.rateBps : null,
      'months': inst ? r.months : null,
      'payAccountId': inst ? r.payAccountId : null,
      'updatedAt': _now,
    };
  }

  Future<void> createRecurrence(Recurrence r) =>
      _recurrences.doc().set({..._recurrenceFields(r), 'createdAt': _now});

  /// Guarda cambios. Si cambia el importe, recuerda el anterior (para avisar
  /// de subidas de precio). El contador de procesadas nunca retrocede.
  Future<void> updateRecurrence(Recurrence before, Recurrence after) {
    final previous = after.amountCents != before.amountCents ? before.amountCents : before.previousAmountCents;
    final fields = _recurrenceFields(after)
      ..['previousAmountCents'] = previous
      ..['nextIndex'] = after.nextIndex < before.nextIndex ? before.nextIndex : after.nextIndex;
    return _recurrences.doc(before.id).update(fields);
  }

  Future<void> deleteRecurrence(String id) => _recurrences.doc(id).delete();

  /// Crea un plan a plazos. Con [newDebtName], crea también la cuenta de deuda
  /// con [debtBalanceCents] pendientes; si no, usa la cuenta del plan.
  Future<void> createInstallment(Recurrence plan, {String? newDebtName, AccountType debtType = AccountType.loan, int debtBalanceCents = 0}) {
    final batch = _db.batch();
    var accountId = plan.accountId;
    if (newDebtName != null) {
      final ref = _accounts.doc();
      accountId = ref.id;
      batch.set(ref, {
        'name': newDebtName,
        'type': debtType.name,
        'institution': '',
        'balanceCents': debtBalanceCents,
        'createdAt': _now,
        'updatedAt': _now,
      });
    }
    final fields = _recurrenceFields(plan)..['accountId'] = accountId;
    batch.set(_recurrences.doc(), {...fields, 'createdAt': _now});
    return batch.commit();
  }

  /// Apunta la repetición [index] de [r]: sus movimientos, el efecto en los
  /// saldos y el avance del contador, todo en una transacción. Si otro
  /// dispositivo ya la apuntó (el contador ya no es [index]), no hace nada y
  /// devuelve false. Sin conexión la transacción falla y se reintenta luego.
  Future<bool> applyOccurrence(Recurrence r, int index, Map<String, Account> accounts) {
    final movements = occurrenceMovements(r, index);
    return _db.runTransaction<bool>((tx) async {
      final ref = _recurrences.doc(r.id);
      final snap = await tx.get(ref);
      final current = (snap.data()?['nextIndex'] as num?)?.toInt();
      if (!snap.exists || current != index) return false;
      final changes = <String, int>{};
      for (final m in movements) {
        tx.set(_movements.doc(m.id), {...m.toMap(), 'createdAt': _now, 'updatedAt': _now});
        balanceChanges(m, accounts).forEach((id, d) => changes[id] = (changes[id] ?? 0) + d);
      }
      changes.forEach((id, delta) {
        if (delta != 0) {
          tx.update(_accounts.doc(id), {'balanceCents': FieldValue.increment(delta), 'updatedAt': _now});
        }
      });
      tx.update(ref, {'nextIndex': index + 1, 'updatedAt': _now});
      return true;
    });
  }

  /// Salta la repetición [index] sin apuntarla (por ejemplo, un mes sin cargo).
  Future<bool> skipOccurrence(Recurrence r, int index) => _db.runTransaction<bool>((tx) async {
        final ref = _recurrences.doc(r.id);
        final snap = await tx.get(ref);
        if (!snap.exists || (snap.data()?['nextIndex'] as num?)?.toInt() != index) return false;
        tx.update(ref, {'nextIndex': index + 1, 'updatedAt': _now});
        return true;
      });

  // ---------- Datos de ejemplo ----------

  /// Escribe [sample] en un solo batch. Las cuentas se crean con el saldo
  /// inicial y los movimientos lo llevan al final, igual que en uso real.
  Future<void> loadSampleData(SampleData sample) {
    final batch = _db.batch();
    final finals = <String, int>{for (final a in sample.accounts) a.id: a.balanceCents};
    final byId = {for (final a in sample.accounts) a.id: a};
    for (final m in sample.movements) {
      balanceChanges(m, byId).forEach((id, d) => finals[id] = finals[id]! + d);
      batch.set(_movements.doc(m.id), {...m.toMap(), 'createdAt': _now, 'updatedAt': _now});
    }
    for (final a in sample.accounts) {
      batch.set(_accounts.doc(a.id), {
        'name': a.name,
        'type': a.type.name,
        'institution': a.institution,
        'balanceCents': finals[a.id],
        'createdAt': _now,
        'updatedAt': _now,
      });
    }
    for (final g in sample.goals) {
      batch.set(_goals.doc(g.id), {
        ..._goalFields(g.name, g.targetCents, g.savedCents, g.accountIds, g.deadline, g.targetMonths),
        'createdAt': _now,
      });
    }
    for (final r in sample.recurrences) {
      batch.set(_recurrences.doc(r.id), {..._recurrenceFields(r), 'createdAt': _now});
    }
    sample.history.forEach((month, totals) {
      batch.set(_snapshots.doc(month), {
        'assetsCents': totals.assetsCents,
        'liabilitiesCents': totals.liabilitiesCents,
        'updatedAt': _now,
      });
    });
    return batch.commit();
  }

  /// Borra todo lo que tenga id `ejemplo-…`. Con [clearHistoryBefore] borra
  /// también las fotos de meses anteriores (solo si no queda nada propio).
  Future<void> removeSampleData({String? clearHistoryBefore}) async {
    final batch = _db.batch();
    for (final col in [_accounts, _movements, _goals, _recurrences]) {
      final docs = await col
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: sampleIdPrefix)
          .where(FieldPath.documentId, isLessThan: '$sampleIdPrefix\uf8ff')
          .get();
      for (final d in docs.docs) {
        batch.delete(d.reference);
      }
    }
    if (clearHistoryBefore != null) {
      final old = await _snapshots.where(FieldPath.documentId, isLessThan: clearHistoryBefore).get();
      for (final d in old.docs) {
        batch.delete(d.reference);
      }
    }
    await batch.commit();
  }

  // ---------- Evolución ----------

  Future<void> saveSnapshot(String monthId, PortfolioTotals totals) => _snapshots.doc(monthId).set({
        'assetsCents': totals.assetsCents,
        'liabilitiesCents': totals.liabilitiesCents,
        'updatedAt': _now,
      });
}
