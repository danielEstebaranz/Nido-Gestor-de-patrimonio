import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/nido_store.dart';
import '../theme.dart';
import 'crt.dart';
import '../privacy.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

void showMessage(String text) {
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String firestoreErrorMessage(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => 'El servidor ha rechazado el cambio. Revisa las reglas de Firestore.',
      'unavailable' => 'Sin conexión: los cambios se sincronizarán al volver.',
      _ => 'Error de sincronización (${error.code}).',
    };
  }
  return 'Error de sincronización.';
}

class NidoLogo extends StatelessWidget {
  const NidoLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    // El mismo dibujo que el icono de la app (tool/make_icon.ps1).
    return Image.asset('assets/icon/nido_icon.png', width: size, height: size, filterQuality: FilterQuality.medium);
  }
}

/// Logo + nombre en verde fósforo.
class NidoWordmark extends StatelessWidget {
  const NidoWordmark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      NidoLogo(size: size),
      SizedBox(width: size * .35),
      Text('NIDO', style: crtReadout(size * 1.05, Crt.green).copyWith(letterSpacing: 4)),
    ]);
  }
}

/// Centra el contenido con un ancho máximo cómodo en escritorio.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1100});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
          children: [for (var i = 0; i < children.length; i++) Reveal(index: i, child: children[i])],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: PromptLabel(title, trailing: trailing),
    );
  }
}

/// Panel con título de terminal: el bloque básico de cada pantalla.
class Panel extends StatelessWidget {
  const Panel({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (title != null) ...[PromptLabel(title!, trailing: trailing), const SizedBox(height: 14)],
          child,
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Crt.screen,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Crt.border, width: 2),
          ),
          child: Icon(icon, size: 40, color: Crt.amber, shadows: glow(Crt.amber, blur: 8)),
        ),
        const SizedBox(height: 18),
        Text(title.toUpperCase(), style: theme.textTheme.titleLarge?.copyWith(color: Crt.green), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: Crt.grey), textAlign: TextAlign.center),
        ),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ]),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key, this.label = 'LEYENDO CINTA'});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(48), child: Center(child: TapeReels(label: label)));
}

/// Importe con signo y color: verde si suma, rojo si resta.
class SignedAmount extends StatelessWidget {
  const SignedAmount(this.cents, {super.key, this.size = 15, this.neutral = false});

  final int cents;
  final double size;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    // En web los int son números de JS y `-0` se pintaría como "-0,00 €".
    final value = cents == 0 ? 0 : cents;
    final palette = context.nido;
    final color = neutral || value == 0 ? Crt.offWhite : (value < 0 ? palette.negative : palette.positive);
    final text = neutral ? context.money(value) : '${value > 0 ? '+' : ''}${context.money(value)}';
    return Text(text, style: mono(size: size, weight: FontWeight.w700, color: color));
  }
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'Eliminar'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title.toUpperCase()),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Crt.red, foregroundColor: Crt.offWhite),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action.toUpperCase()),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Formularios: hoja inferior en móvil, diálogo en pantallas anchas.
///
/// Los diálogos viven en el navegador raíz, fuera del Provider de la sesión,
/// así que se les vuelve a pasar el [NidoStore].
Future<T?> showForm<T>(BuildContext context, Widget child) {
  final form = ChangeNotifierProvider<NidoStore>.value(value: context.read<NidoStore>(), child: child);
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<T>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540), child: form),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: form,
    ),
  );
}

/// Contenedor común de los formularios.
class FormFrame extends StatelessWidget {
  const FormFrame({super.key, required this.title, required this.children, required this.onSave, this.onDelete});

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 18), child: BackTitle(title)),
          for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 14), child: c),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (onDelete != null)
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('ELIMINAR'),
                  style: TextButton.styleFrom(foregroundColor: Crt.redText),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: Crt.grey),
                child: const Text('CANCELAR'),
              ),
              FilledButton(onPressed: onSave, child: const Text('GUARDAR')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Título de una hoja o pantalla secundaria. El "<" de delante vuelve atrás.
class BackTitle extends StatelessWidget {
  const BackTitle(this.title, {super.key, this.style, this.cursor = true});

  final String title;

  /// Por defecto, el de los formularios (headlineSmall en verde).
  final TextStyle? style;
  final bool cursor;

  @override
  Widget build(BuildContext context) {
    final s = style ?? Theme.of(context).textTheme.headlineSmall?.copyWith(color: Crt.green, shadows: glow(Crt.green, blur: 6));
    return Row(children: [
      Tooltip(
        message: 'Volver',
        child: Semantics(
          button: true,
          label: 'Volver',
          child: InkWell(
            onTap: () => Navigator.maybePop(context),
            borderRadius: BorderRadius.circular(4),
            // Zona táctil de 44 px de alto aunque el carácter sea estrecho.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: ExcludeSemantics(child: Text('<', style: s?.copyWith(color: Crt.green))),
              ),
            ),
          ),
        ),
      ),
      Flexible(child: Text(title.toUpperCase(), style: s, overflow: TextOverflow.ellipsis)),
      if (cursor) ...[const SizedBox(width: 8), BlinkingCursor(size: (s?.fontSize ?? 22).clamp(14, 22))],
    ]);
  }
}

/// Etiqueta encima del campo, como pide el sistema de diseño.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
      const SizedBox(height: 6),
      child,
      if (hint != null) ...[
        const SizedBox(height: 4),
        Text(hint!, style: theme.textTheme.bodySmall),
      ],
    ]);
  }
}

/// Campo de importe en euros que valida con [parseCents].
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.allowNegative = false,
    this.allowZero = true,
    this.autofocus = false,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final bool allowNegative;
  final bool allowZero;
  final bool autofocus;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      hint: hint,
      child: TextFormField(
        controller: controller,
        autofocus: autofocus,
        style: mono(size: 18, weight: FontWeight.w700, color: Crt.green),
        decoration: const InputDecoration(hintText: '0,00', suffixText: '€'),
        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: allowNegative),
        validator: (v) {
          final cents = parseCents(v ?? '');
          if (cents == null) return 'Escribe un importe, por ejemplo 1.250,00';
          if (!allowNegative && cents < 0) return 'No puede ser negativo';
          if (!allowZero && cents == 0) return 'Debe ser mayor que 0';
          return null;
        },
      ),
    );
  }
}

/// Flex para barras proporcionales: parte por mil del total, mínimo 1.
/// (Los importes en céntimos son demasiado grandes para usarlos como flex.)
int flexShare(int part, int total) => total <= 0 || part <= 0 ? 1 : (part * 1000 / total).round().clamp(1, 1000);

String? requiredText(String? v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null;
