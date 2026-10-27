import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/money.dart';

/// Lo que se ve en lugar de un importe cuando están ocultos.
const hiddenAmount = '••••• €';

/// Modo privado: oculta saldos e importes (por ejemplo, en público).
///
/// Se guarda en el propio dispositivo, no en Firebase: puedes tenerlo activado
/// en el ordenador y desactivado en el móvil.
class PrivacyController extends ValueNotifier<bool> {
  PrivacyController._(super.value, this._prefs);

  /// Sin almacenamiento (tests, o si el dispositivo no lo permite).
  PrivacyController.memory([bool hidden = false]) : this._(hidden, null);

  static const _key = 'nido.hideAmounts';
  final SharedPreferences? _prefs;

  static Future<PrivacyController> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return PrivacyController._(prefs.getBool(_key) ?? false, prefs);
    } catch (e) {
      debugPrint('Nido: preferencias no disponibles, el modo privado no se recordará ($e)');
      return PrivacyController.memory();
    }
  }

  bool get hidden => value;

  void toggle() => setHidden(!value);

  void setHidden(bool hidden) {
    value = hidden;
    _prefs?.setBool(_key, value);
  }
}

class PrivacyScope extends InheritedNotifier<PrivacyController> {
  const PrivacyScope({super.key, required PrivacyController controller, required super.child})
      : super(notifier: controller);

  static PrivacyController? maybeOf(BuildContext context, {bool listen = true}) => (listen
          ? context.dependOnInheritedWidgetOfExactType<PrivacyScope>()
          : context.getInheritedWidgetOfExactType<PrivacyScope>())
      ?.notifier;
}

extension PrivacyX on BuildContext {
  /// Si los importes están ocultos (y repinta este widget cuando cambia).
  bool get amountsHidden => PrivacyScope.maybeOf(this)?.hidden ?? false;

  /// Importe formateado, o [hiddenAmount] en modo privado. Para usar en `build`.
  String money(int cents) => amountsHidden ? hiddenAmount : formatCents(cents);

  /// Igual que [money] pero sin suscribirse: para avisos y callbacks.
  String moneyOnce(int cents) =>
      (PrivacyScope.maybeOf(this, listen: false)?.hidden ?? false) ? hiddenAmount : formatCents(cents);
}
