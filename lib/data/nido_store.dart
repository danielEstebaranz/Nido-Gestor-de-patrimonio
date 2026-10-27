import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/portfolio.dart';
import '../domain/recurrence_engine.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../models/movement.dart';
import '../models/recurrence.dart';
import '../models/snapshot.dart';
import 'nido_repository.dart';
import 'sample_data.dart';

/// Estado de la sincronización con Firebase, para la interfaz.
enum SyncState {
  /// Todo confirmado por el servidor.
  synced,

  /// Hay cambios enviándose.
  syncing,

  /// Sin conexión: los cambios esperan en la caché local.
  offline,
}

/// Estado en memoria de la sesión, alimentado por los listeners de Firestore.
/// Cualquier cambio hecho en otro dispositivo llega aquí y repinta la interfaz.
class NidoStore extends ChangeNotifier {
  NidoStore(this.repo, {this.onError, DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final now = _clock();
    _month = DateTime(now.year, now.month);
    _subs.addAll([
      repo.watchAccounts().listen(_onAccounts, onError: _report),
      repo.watchGoals().listen((g) {
        goals = g;
        notifyListeners();
      }, onError: _report),
      repo.watchSnapshots().listen((s) {
        snapshots = s;
        _snapshotsLoaded = true;
        _syncSnapshot();
        notifyListeners();
      }, onError: _report),
    ]);
    _watchMonth();
    // Tres meses atrás para el gasto medio, el colchón y los últimos movimientos.
    _subs.add(repo.watchRecentMovements(DateTime(now.year, now.month - 3)).listen((m) {
      recent = m;
      notifyListeners();
    }, onError: _report));
    _subs.add(repo.watchRecurrences().listen((r) {
      recurrences = r;
      recurrencesLoaded = true;
      _notify();
      _processDue();
    }, onError: _report));
    // Por si la app se queda abierta de un día para otro.
    _recurrenceTimer = Timer.periodic(const Duration(minutes: 30), (_) => _processDue());
  }

  // ---------------------------------------------------------------- Programaciones

  List<Recurrence> recurrences = const [];
  bool recurrencesLoaded = false;
  bool _processing = false;
  Timer? _recurrenceTimer;

  /// Apunta las repeticiones automáticas que ya tocan. Solo con datos del
  /// servidor y de una en una; cada una va en una transacción que comprueba
  /// que nadie la ha apuntado ya (otro dispositivo), así no hay duplicados.
  Future<void> _processDue() async {
    if (_processing || _disposed || !accountsLoaded || !recurrencesLoaded || !_accountsFromServer) return;
    _processing = true;
    try {
      for (final r in recurrences.where((r) => r.auto)) {
        for (final o in dueOccurrences(r, _clock())) {
          pendingWrites++;
          _pendingChanged();
          try {
            if (!await repo.applyOccurrence(r, o.index, accountsById)) break;
          } finally {
            pendingWrites--;
            _pendingChanged();
          }
        }
      }
    } catch (e) {
      // Sin conexión la transacción falla: se reintenta en la próxima pasada.
      debugPrint('Nido: programaciones pendientes: $e');
    } finally {
      _processing = false;
    }
  }

  /// Repeticiones que esperan confirmación (programaciones no automáticas).
  List<({Recurrence r, int index, DateTime date})> get toConfirm => [
        for (final r in recurrences.where((r) => !r.auto))
          for (final o in dueOccurrences(r, _clock())) (r: r, index: o.index, date: o.date),
      ]..sort((a, b) => a.date.compareTo(b.date));

  void confirmOccurrence(Recurrence r, int index) =>
      run(repo.applyOccurrence(r, index, accountsById).then((_) {}));

  void skipOccurrence(Recurrence r, int index) => run(repo.skipOccurrence(r, index).then((_) {}));

  /// Próximas repeticiones (desde mañana hasta dentro de [days] días).
  List<({Recurrence r, int index, DateTime date})> upcoming({int days = 30}) {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final until = DateTime(today.year, today.month, today.day + days);
    final out = <({Recurrence r, int index, DateTime date})>[];
    for (final r in recurrences) {
      for (var i = r.nextIndex; i < r.nextIndex + 60 && occurrenceExists(r, i); i++) {
        final d = occurrenceDate(r, i);
        if (d.isAfter(until)) break;
        if (d.isAfter(today)) out.add((r: r, index: i, date: d));
      }
    }
    return out..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Gasto mensual de referencia: lo fijo de Recurrentes más la media de lo
  /// variable (ver spendingReference). null si no hay nada.
  SpendingReference? get spending => spendingReference(recent, accountsById, recurrences, _clock());

  int? get referenceSpending => spending?.totalCents;

  /// Importe vigente de un objetivo: el fijo, o en los dinámicos los meses de
  /// gasto de referencia (si aún no hay datos, el último importe guardado).
  int goalTarget(Goal g) {
    final months = g.targetMonths;
    final ref = referenceSpending;
    if (months == null || ref == null) return g.targetCents;
    return recommendedEmergencyFund(ref, months);
  }

  /// Cuotas de préstamos y plazos al mes entre ingresos medios al mes
  /// (0,35 = el 35 % de lo que entra se va en cuotas), o null si no aplica.
  double? get debtBurden {
    final cuotas = recurrences
        .where((r) => r.isInstallment && nextOccurrence(r) != null)
        .fold<int>(0, (s, r) => s + monthlyEquivalent(amountPerOccurrence(r), r.frequency));
    final income = averageMonthlyIncome(recent);
    if (cuotas == 0 || income == null || income <= 0) return null;
    return cuotas / income;
  }

  final NidoRepository repo;
  final void Function(Object error)? onError;
  final DateTime Function() _clock;
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<List<Movement>>? _movementsSub;

  List<Account> accounts = const [];
  Map<String, Account> accountsById = const {};
  List<Goal> goals = const [];
  List<NetWorthSnapshot> snapshots = const [];
  List<Movement> movements = const [];

  /// Movimientos de los últimos ~3 meses, más recientes primero.
  List<Movement> recent = const [];

  /// Escrituras lanzadas que el servidor aún no ha confirmado.
  int pendingWrites = 0;

  /// Última vez que llegaron datos confirmados por el servidor.
  DateTime? lastSyncedAt;
  bool _online = true;

  /// Desde cuándo hay escrituras sin confirmar (null si no hay ninguna).
  DateTime? _pendingSince;
  Timer? _pendingWatch;

  /// Si una escritura tarda más que esto, se da por perdida la conexión sin
  /// esperar a Firestore, que puede tardar 30-40 s en notarlo.
  static const offlineAfter = Duration(seconds: 8);

  SyncState get syncState {
    if (!_online) return SyncState.offline;
    if (pendingWrites == 0) return SyncState.synced;
    final since = _pendingSince;
    if (since != null && _clock().difference(since) >= offlineAfter) return SyncState.offline;
    return SyncState.syncing;
  }

  void _pendingChanged() {
    if (pendingWrites > 0) {
      _pendingSince ??= _clock();
      // Repinta al cumplirse el plazo, para pasar a "sin conexión" a tiempo.
      _pendingWatch ??= Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    } else {
      _pendingSince = null;
      _pendingWatch?.cancel();
    _recurrenceTimer?.cancel();
      _pendingWatch = null;
    }
    _notify();
  }

  bool accountsLoaded = false;
  bool movementsLoaded = false;
  bool _accountsFromServer = false;
  bool _snapshotsLoaded = false;

  late DateTime _month;
  DateTime get month => _month;

  PortfolioTotals get totals => totalsOf(accounts);
  MonthFlow get flow => monthFlow(movements);

  bool get hasSampleData => accounts.any((a) => a.sample) || goals.any((g) => g.sample);
  bool get hasOwnData => accounts.any((a) => !a.sample);
  bool sampleBusy = false;

  Future<void> loadSampleData() => _sampleTask(() => repo.loadSampleData(SampleData.build(_clock())));

  /// Quita los ejemplos. Si no queda nada propio, borra también la historia
  /// mensual que se creó con ellos.
  Future<void> removeSampleData() => _sampleTask(
        () => repo.removeSampleData(clearHistoryBefore: hasOwnData ? null : monthId(_clock())),
      );

  Future<void> _sampleTask(Future<void> Function() task) async {
    sampleBusy = true;
    pendingWrites++;
    _pendingChanged();
    try {
      // Offline la escritura queda en cola: no se espera más de unos segundos.
      await task().timeout(const Duration(seconds: 8), onTimeout: () {});
    } catch (e) {
      _report(e);
    } finally {
      sampleBusy = false;
      pendingWrites--;
      _pendingChanged();
    }
  }

  void _onAccounts(AccountsResult r) {
    accounts = r.accounts;
    accountsById = {for (final a in r.accounts) a.id: a};
    accountsLoaded = true;
    _accountsFromServer = !r.fromCache;
    // Firestore avisa (cambio de metadatos) cuando pierde o recupera el servidor.
    _online = !r.fromCache;
    if (!r.fromCache) lastSyncedAt = _clock();
    _syncSnapshot();
    _processDue();
    notifyListeners();
  }

  void selectMonth(DateTime month) {
    _month = DateTime(month.year, month.month);
    _watchMonth();
    notifyListeners();
  }

  void _watchMonth() {
    _movementsSub?.cancel();
    movementsLoaded = false;
    _movementsSub = repo.watchMovements(_month).listen((m) {
      movements = m;
      movementsLoaded = true;
      notifyListeners();
    }, onError: _report);
  }

  /// Guarda la foto del mes actual cuando cambia el patrimonio. Solo con datos
  /// confirmados por el servidor, para que un dispositivo recién instalado no
  /// sobrescriba el mes con ceros.
  void _syncSnapshot() {
    if (!_accountsFromServer || !_snapshotsLoaded) return;
    final id = monthId(_clock());
    final t = totals;
    final current = snapshots.where((s) => s.id == id).firstOrNull;
    if (current == null && accounts.isEmpty) return;
    if (current != null &&
        current.assetsCents == t.assetsCents &&
        current.liabilitiesCents == t.liabilitiesCents) {
      return;
    }
    run(repo.saveSnapshot(id, t));
  }

  /// Lanza una escritura sin esperar al servidor (funciona sin conexión) y
  /// avisa si el servidor la rechaza. Mientras no se confirma, cuenta como
  /// pendiente: es lo que hace girar las bobinas o encender el LED de REC.
  void run(Future<void> write) {
    pendingWrites++;
    _pendingChanged();
    unawaited(write.then((_) => lastSyncedAt = _clock(), onError: _report).whenComplete(() {
      pendingWrites--;
      _pendingChanged();
    }));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _report(Object error) {
    debugPrint('Nido: $error');
    onError?.call(error);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _pendingWatch?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _movementsSub?.cancel();
    super.dispose();
  }
}
