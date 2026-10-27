import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

// Piezas de pletina: LED de grabación, salto de imagen VHS y cinta de casete.

bool _reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// LED rojo de grabación que parpadea, con su rótulo.
class RecLed extends StatefulWidget {
  const RecLed({super.key, this.label = 'REC', this.color = Crt.redText, this.size = 10});

  final String? label;
  final Color color;
  final double size;

  @override
  State<RecLed> createState() => _RecLedState();
}

class _RecLedState extends State<RecLed> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.value = 0;
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
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final on = _c.value < .6;
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? widget.color : widget.color.withValues(alpha: .25),
              boxShadow: on ? [BoxShadow(color: widget.color.withValues(alpha: .7), blurRadius: 8)] : null,
            ),
          );
        },
      ),
      if (widget.label != null) ...[
        const SizedBox(width: 6),
        Text(widget.label!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: widget.color)),
      ],
    ]);
  }
}

/// Salto de imagen VHS: cada vez que cambia [trigger], la imagen tiembla en
/// horizontal y pasan unas bandas de ruido (unos 300 ms). Solo transform y pintura.
class VhsGlitch extends StatefulWidget {
  const VhsGlitch({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<VhsGlitch> createState() => _VhsGlitchState();
}

class _VhsGlitchState extends State<VhsGlitch> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  int _seed = 0;

  @override
  void didUpdateWidget(VhsGlitch old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !_reduceMotion(context)) {
      _seed++;
      _c.forward(from: 0);
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
      child: widget.child,
      builder: (context, child) {
        if (!_c.isAnimating) return child!;
        final t = _c.value;
        final dx = math.sin(t * math.pi * 7) * 7 * (1 - t);
        return Stack(children: [
          Transform.translate(offset: Offset(dx, 0), child: Opacity(opacity: .85 + .15 * t, child: child)),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _VhsBandsPainter(t, _seed)))),
        ]);
      },
    );
  }
}

class _VhsBandsPainter extends CustomPainter {
  _VhsBandsPainter(this.t, this.seed);

  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final fade = 1 - t;
    for (var i = 0; i < 3; i++) {
      final y = (rnd.nextDouble() + t * (0.6 + i * .2)) % 1 * size.height;
      final h = 4 + rnd.nextDouble() * 14;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, h),
        Paint()..color = (i.isEven ? Crt.offWhite : Crt.green).withValues(alpha: .09 * fade),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y + h, size.width, 1.5),
        Paint()..color = Crt.offWhite.withValues(alpha: .22 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_VhsBandsPainter old) => old.t != t || old.seed != seed;
}

/// Cinta de casete cuyo progreso es la cinta ya pasada a la bobina derecha:
/// al 0 % la izquierda está llena; al 100 %, toda la cinta está a la derecha.
/// Al aparecer, la cinta corre hasta su posición y las bobinas giran.
class CassetteTape extends StatelessWidget {
  const CassetteTape({
    super.key,
    required this.progress,
    required this.title,
    this.stripe = Crt.amber,
    this.side = 'A',
    this.counter,
    this.width = 240,
  });

  final double progress;
  final String title;

  /// Color de la franja de la etiqueta (estado del objetivo).
  final Color stripe;
  final String side;

  /// Contador de cinta (por ejemplo, el porcentaje con tres cifras).
  final String? counter;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: width * .63,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: p),
        duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _CassettePainter(
            progress: value,
            // Las bobinas giran mientras la cinta corre y se paran al llegar.
            angle: value * 14 * math.pi,
            title: title,
            stripe: stripe,
            side: side,
            counter: counter,
          ),
        ),
      ),
    );
  }
}

class _CassettePainter extends CustomPainter {
  _CassettePainter({
    required this.progress,
    required this.angle,
    required this.title,
    required this.stripe,
    required this.side,
    required this.counter,
  });

  final double progress;
  final double angle;
  final String title;
  final Color stripe;
  final String side;
  final String? counter;

  static const _shell = Color(0xFF34352F);
  static const _shellDark = Color(0xFF26271F);
  static const _paper = Crt.beige;
  static const _ink = Color(0xFF2A2218);
  static const _tape = Color(0xFF4A3524);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shell = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * .035));
    canvas.drawRRect(shell, Paint()..color = _shell);
    canvas.drawRRect(
      shell.deflate(1),
      Paint()
        ..color = Crt.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Tornillos de las esquinas.
    final screw = Paint()..color = const Color(0xFF6B6B63);
    final slot = Paint()
      ..color = _shellDark
      ..strokeWidth = 1.4;
    for (final o in [Offset(w * .045, h * .07), Offset(w * .955, h * .07), Offset(w * .045, h * .93), Offset(w * .955, h * .93)]) {
      canvas.drawCircle(o, w * .016, screw);
      canvas.drawLine(o - Offset(w * .01, 0), o + Offset(w * .01, 0), slot);
    }

    // Etiqueta de papel con franja de color, lado y título escrito.
    final label = RRect.fromRectAndRadius(Rect.fromLTRB(w * .08, h * .09, w * .92, h * .66), Radius.circular(w * .02));
    canvas.drawRRect(label, Paint()..color = _paper);
    canvas.save();
    canvas.clipRRect(label);
    canvas.drawRect(Rect.fromLTRB(w * .08, h * .09, w * .92, h * .2), Paint()..color = stripe);
    canvas.restore();
    _text(canvas, side, Offset(w * .11, h * .085), h * .12, _ink, maxWidth: w * .1);
    _text(canvas, title.toUpperCase(), Offset(w * .19, h * .2), h * .11, _ink, maxWidth: w * .7);
    // Rayas de escribir a mano en la etiqueta.
    final rule = Paint()
      ..color = _ink.withValues(alpha: .18)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(w * .12, h * .33), Offset(w * .88, h * .33), rule);

    // Ventana con las dos bobinas.
    final window = RRect.fromRectAndRadius(Rect.fromLTRB(w * .22, h * .37, w * .78, h * .62), Radius.circular(h * .06));
    canvas.drawRRect(window, Paint()..color = Crt.screen);
    final cy = h * .495;
    final left = Offset(w * .33, cy);
    final right = Offset(w * .67, cy);
    final hubR = h * .055;
    final maxR = h * .16;
    final leftR = hubR + (maxR - hubR) * (1 - progress);
    final rightR = hubR + (maxR - hubR) * progress;

    canvas.save();
    canvas.clipRRect(window);
    final tape = Paint()..color = _tape;
    canvas.drawCircle(left, leftR, tape);
    canvas.drawCircle(right, rightR, tape);
    // Brillo de la cinta enrollada.
    final sheen = Paint()
      ..color = Crt.amber.withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (c, r) in [(left, leftR), (right, rightR)]) {
      for (var k = .4; k < 1; k += .2) {
        if (r * k > hubR) canvas.drawCircle(c, r * k, sheen);
      }
    }
    canvas.restore();

    for (final c in [left, right]) {
      canvas.drawCircle(c, hubR, Paint()..color = Crt.offWhite);
      final tooth = Paint()
        ..color = Crt.screen
        ..strokeWidth = hubR * .28
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 6; i++) {
        final a = angle + i * math.pi / 3;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + d * hubR * .45, c + d * hubR * .85, tooth);
      }
    }

    // Zona de cabezales: trapecio inferior con la cinta pasando.
    final head = Path()
      ..moveTo(w * .2, h)
      ..lineTo(w * .26, h * .74)
      ..lineTo(w * .74, h * .74)
      ..lineTo(w * .8, h)
      ..close();
    canvas.drawPath(head, Paint()..color = _shellDark);
    final run = Paint()
      ..color = _tape
      ..strokeWidth = 2.2;
    canvas.drawLine(Offset(w * .27, h * .78), Offset(w * .73, h * .78), run);
    for (final x in [w * .36, w * .5, w * .64]) {
      canvas.drawCircle(Offset(x, h * .88), h * .028, Paint()..color = Crt.background);
    }

    if (counter != null) {
      _text(canvas, counter!, Offset(w * .82, h * .76), h * .09, Crt.amber, maxWidth: w * .14, mono: true);
    }
  }

  void _text(Canvas canvas, String s, Offset at, double size, Color color, {required double maxWidth, bool mono = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: mono ? 'JetBrainsMono' : 'VT323',
          fontSize: size,
          color: color,
          fontWeight: mono ? FontWeight.w700 : FontWeight.w400,
          letterSpacing: mono ? 0 : 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_CassettePainter old) =>
      old.progress != progress || old.title != title || old.stripe != stripe || old.counter != counter;
}
