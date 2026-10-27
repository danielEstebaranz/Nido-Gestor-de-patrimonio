import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

// Piezas del sistema cassette futurism: scanlines, cursor de terminal,
// bobinas de cinta, indicadores analógicos y barras LED.

bool _reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Líneas de escaneo y viñeta de monitor CRT sobre toda la app.
class CrtOverlay extends StatelessWidget {
  const CrtOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      const Positioned.fill(
        child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _ScanlinePainter()))),
      ),
    ]);
  }
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter({this.opacity = .07, this.vignette = true});

  final double opacity;
  final bool vignette;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = Colors.black.withValues(alpha: opacity);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    if (vignette) {
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: 1.2,
            colors: [Colors.transparent, Colors.black.withValues(alpha: .28)],
            stops: const [.62, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.opacity != opacity || old.vignette != vignette;
}

/// Pantalla incrustada: fondo de tubo, borde grueso y sus propias scanlines.
class CrtScreen extends StatelessWidget {
  const CrtScreen({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.tint = Crt.green});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Crt.border, width: 2),
        // Un resplandor leve de fósforo hacia arriba a la izquierda.
        gradient: RadialGradient(
          center: const Alignment(-.5, -.8),
          radius: 1.1,
          colors: [Color.alphaBlend(tint.withValues(alpha: .045), Crt.screen), Crt.screen],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          foregroundPainter: const _ScanlinePainter(opacity: .22, vignette: false),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Cursor de bloque que parpadea, como en un terminal.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key, this.color = Crt.green, this.size = 20});

  final Color color;
  final double size;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1060));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Opacity(
        opacity: _c.value < .5 ? 1 : 0,
        child: Container(
          width: widget.size * .5,
          height: widget.size * .9,
          decoration: BoxDecoration(color: widget.color, boxShadow: [
            BoxShadow(color: widget.color.withValues(alpha: .5), blurRadius: 6),
          ]),
        ),
      ),
    );
  }
}

/// Título de sección en forma de línea de comandos: `> MOVIMIENTOS █`.
class PromptLabel extends StatelessWidget {
  const PromptLabel(this.text, {super.key, this.cursor = false, this.color = Crt.beige, this.trailing});

  final String text;
  final bool cursor;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(color: color, fontSize: 18);
    final label = Text(text.toUpperCase(), style: style, overflow: TextOverflow.ellipsis);
    return Row(children: [
      Text('> ', style: style.copyWith(color: Crt.green)),
      // Con acción a la derecha el título ocupa todo el hueco (sin Spacer que se lo reparta).
      if (trailing != null) Expanded(child: label) else Flexible(child: label),
      if (cursor) ...[const SizedBox(width: 6), BlinkingCursor(size: 18, color: color)],
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ]);
  }
}

/// Dos bobinas con cinta entre ellas: sustituye a los spinners. Con
/// [spinning] a false se quedan quietas (por ejemplo, todo sincronizado).
class TapeReels extends StatefulWidget {
  const TapeReels({super.key, this.width = 120, this.label = 'CARGANDO', this.spinning = true, this.labelColor});

  final double width;
  final String? label;
  final bool spinning;
  final Color? labelColor;

  @override
  State<TapeReels> createState() => _TapeReelsState();
}

class _TapeReelsState extends State<TapeReels> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TapeReels old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.spinning && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.spinning && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: widget.width,
        height: widget.width * .42,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) =>
              CustomPaint(painter: _ReelsPainter(_reduceMotion(context) ? 0 : _c.value * 2 * math.pi)),
        ),
      ),
      if (widget.label != null) ...[
        const SizedBox(height: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.label!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: widget.labelColor)),
          if (widget.spinning) ...[
            const SizedBox(width: 6),
            BlinkingCursor(size: 14, color: widget.labelColor ?? Crt.beige),
          ],
        ]),
      ],
    ]);
  }
}

class _ReelsPainter extends CustomPainter {
  _ReelsPainter(this.angle);

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final left = Offset(r, r);
    final right = Offset(size.width - r, r);
    final tape = Paint()
      ..color = Crt.beige.withValues(alpha: .7)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(left.dx, size.height - 1), Offset(right.dx, size.height - 1), tape);
    for (final (center, wound) in [(left, .85), (right, .55)]) {
      canvas.drawCircle(center, r * wound, Paint()..color = const Color(0xFF3A2E22));
      canvas.drawCircle(
        center,
        r - 1,
        Paint()
          ..color = Crt.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final hub = Paint()..color = Crt.offWhite;
      canvas.drawCircle(center, r * .32, hub);
      final spoke = Paint()
        ..color = Crt.screen
        ..strokeWidth = r * .1
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final a = angle + i * 2 * math.pi / 3;
        canvas.drawLine(
          center + Offset(math.cos(a), math.sin(a)) * r * .08,
          center + Offset(math.cos(a), math.sin(a)) * r * .28,
          spoke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ReelsPainter old) => old.angle != angle;
}

/// Indicador analógico de aguja (0 a 1). Las zonas van de rojo a verde.
class AnalogGauge extends StatelessWidget {
  const AnalogGauge({
    super.key,
    required this.value,
    required this.label,
    this.size = 150,
    this.zones = const [(0.0, Crt.redText), (0.34, Crt.amber), (0.67, Crt.green)],
  });

  final double value;
  final String label;
  final double size;

  /// Inicio de cada zona (0-1) y su color.
  final List<(double, Color)> zones;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: size,
          height: size * .56,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v),
            duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 900),
            curve: Curves.easeOutBack,
            builder: (context, animated, _) => CustomPaint(painter: _GaugePainter(animated, zones)),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(label, style: mono(size: (size * .12).clamp(13, 20), weight: FontWeight.w700, color: Crt.offWhite)),
        ),
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value, this.zones);

  final double value;
  final List<(double, Color)> zones;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 6;
    final center = Offset(size.width / 2, r + 6);
    final rect = Rect.fromCircle(center: center, radius: r);
    final band = r * .14;

    for (var i = 0; i < zones.length; i++) {
      final start = zones[i].$1;
      final end = i + 1 < zones.length ? zones[i + 1].$1 : 1.0;
      canvas.drawArc(
        rect.deflate(band / 2),
        math.pi + start * math.pi,
        (end - start) * math.pi,
        false,
        Paint()
          ..color = zones[i].$2.withValues(alpha: .75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = band,
      );
    }
    final tick = Paint()
      ..color = Crt.grey
      ..strokeWidth = 1.5;
    for (var i = 0; i <= 10; i++) {
      final a = math.pi + i / 10 * math.pi;
      final dir = Offset(math.cos(a), math.sin(a));
      final inner = i % 5 == 0 ? r - band - 10 : r - band - 5;
      canvas.drawLine(center + dir * inner, center + dir * (r - band - 1), tick);
    }
    final a = math.pi + value * math.pi;
    final needle = Paint()
      ..color = Crt.offWhite
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center + Offset(math.cos(a), math.sin(a)) * (r - band * 1.4), needle);
    canvas.drawCircle(center, 6, Paint()..color = Crt.amber);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}

/// Barra de LEDs segmentada (0 a 1).
class LedBar extends StatelessWidget {
  const LedBar({super.key, required this.value, this.color = Crt.green, this.segments = 24, this.height = 12});

  final double value;
  final Color color;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final lit = (v * segments).round();
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < segments; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: i < lit ? color : color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(1.5),
                boxShadow: i < lit ? [BoxShadow(color: color.withValues(alpha: .45), blurRadius: 4)] : null,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Entrada: aparece subiendo 16 px en 480 ms, escalonada 100 ms por índice.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 480 + 100 * index.clamp(0, 8)),
      curve: Interval((100 * index.clamp(0, 8)) / (480 + 100 * index.clamp(0, 8)), 1, curve: Curves.easeOut),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
    );
  }
}

/// Elevación al pasar el ratón (escritorio): escala 1,03 y sombra.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.scale = 1.03});

  final Widget child;
  final double scale;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? widget.scale : 1,
        duration: const Duration(milliseconds: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: _hover ? [BoxShadow(color: Crt.green.withValues(alpha: .14), blurRadius: 18)] : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Etiqueta de estado con borde, en mayúsculas.
class StatusTag extends StatelessWidget {
  const StatusTag(this.text, {super.key, this.color = Crt.green});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(4),
        color: color.withValues(alpha: .08),
      ),
      child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall!.copyWith(color: color)),
    );
  }
}
