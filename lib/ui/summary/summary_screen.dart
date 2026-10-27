import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/nido_store.dart';
import '../../domain/portfolio.dart';
import '../../models/account.dart';
import '../../models/movement.dart';
import '../../models/snapshot.dart';
import '../accounts/accounts_screen.dart';
import '../goals/goals_screen.dart';
import '../movements/movements_screen.dart';
import '../recurring/recurring_forms.dart';
import '../recurring/recurring_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/crt.dart';
import '../widgets/tape.dart';
import '../privacy.dart';

final _monthShort = DateFormat('MMM', 'es_ES');
final _monthLong = DateFormat('MMMM', 'es_ES');
final _monthYear = DateFormat('MMMM y', 'es_ES');
final _dayShort = DateFormat('d MMM', 'es_ES');
final _pct = NumberFormat.percentPattern('es_ES');
final _one = NumberFormat('0.0', 'es_ES');

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.onNavigate});

  /// Cambia de pestaña: 1 cuentas, 2 movimientos, 3 recurrentes, 4 objetivos.
  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    if (!store.accountsLoaded) return const Loading();
    if (store.accounts.isEmpty) return _Onboarding(onNavigate: onNavigate);

    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final banner = store.hasSampleData ? const _SampleBanner() : null;
    const hero = _NetWorthDisplay();
    const indicators = _IndicatorsPanel();
    final month = _MonthPanel(onTap: () => onNavigate(2));
    final distribution = _DistributionPanel(onTap: () => onNavigate(1));
    final goals = _GoalsPanel(onTap: () => onNavigate(4));
    final recent = _RecentPanel(onTap: () => onNavigate(2));
    final upcoming = _UpcomingPanel(onTap: () => onNavigate(3));

    if (!wide) {
      return PageBody(children: [
        ?banner,
        hero,
        const SizedBox(height: 16),
        indicators,
        const SizedBox(height: 16),
        month,
        const SizedBox(height: 16),
        upcoming,
        const SizedBox(height: 16),
        goals,
        const SizedBox(height: 16),
        distribution,
        const SizedBox(height: 16),
        recent,
      ]);
    }

    Widget column(List<Widget> items, int offset) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              Reveal(index: i + offset, child: items[i]),
            ],
          ],
        );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 112),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ?banner,
            // Composición asimétrica: la lectura principal ocupa más.
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 7, child: column([hero, indicators, month], 0)),
              const SizedBox(width: 18),
              Expanded(flex: 5, child: column([upcoming, distribution, goals, recent], 1)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SampleBanner extends StatelessWidget {
  const _SampleBanner();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        decoration: BoxDecoration(
          color: Crt.amberDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Crt.amber, width: 2),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.science_outlined, color: Crt.amber),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'DATOS DE EJEMPLO. Nada de esto es tuyo: quítalos cuando quieras empezar con lo tuyo.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Crt.amber),
                ),
              ),
            ]),
            store.sampleBusy
                ? const TapeReels(width: 60, label: null)
                : OutlinedButton(
                    onPressed: store.removeSampleData,
                    style: OutlinedButton.styleFrom(foregroundColor: Crt.amber, side: const BorderSide(color: Crt.amber, width: 1.5)),
                    child: const Text('QUITAR EJEMPLOS'),
                  ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Patrimonio

/// Lectura del patrimonio con controles de pletina: rebobinar, avanzar o
/// reproducir la historia mes a mes, como una cinta. Cada salto de mes tiene
/// su golpe de imagen VHS.
class _NetWorthDisplay extends StatefulWidget {
  const _NetWorthDisplay();

  @override
  State<_NetWorthDisplay> createState() => _NetWorthDisplayState();
}

class _NetWorthDisplayState extends State<_NetWorthDisplay> {
  /// Mes que se está mirando (índice en las fotos); null = en directo.
  int? _cursor;
  Timer? _player;

  bool get _playing => _player != null;

  @override
  void dispose() {
    _player?.cancel();
    super.dispose();
  }

  void _stopPlayer() {
    _player?.cancel();
    _player = null;
  }

  /// La última foto es la del mes en curso: en directo ya la estamos viendo.
  int _lastPast(List<NetWorthSnapshot> snaps) =>
      snaps.last.id == monthId(DateTime.now()) ? snaps.length - 2 : snaps.length - 1;

  void _rewind(List<NetWorthSnapshot> snaps) {
    _stopPlayer();
    setState(() => _cursor = _cursor == null ? _lastPast(snaps) : (_cursor! - 1).clamp(0, snaps.length - 1));
  }

  void _forward(List<NetWorthSnapshot> snaps) {
    _stopPlayer();
    setState(() => _cursor = _cursor == null || _cursor! >= _lastPast(snaps) ? null : _cursor! + 1);
  }

  void _play(List<NetWorthSnapshot> snaps) {
    if (_playing) {
      setState(_stopPlayer);
      return;
    }
    setState(() => _cursor = 0);
    _player = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (!mounted) return;
      final s = context.read<NidoStore>().snapshots;
      setState(() {
        if (_cursor == null || _cursor! >= _lastPast(s)) {
          _cursor = null;
          _stopPlayer();
        } else {
          _cursor = _cursor! + 1;
        }
      });
    });
  }

  void _stop() => setState(() {
        _stopPlayer();
        _cursor = null;
      });

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    final snaps = store.snapshots;
    if (_cursor != null && (snaps.length < 2 || _cursor! >= snaps.length)) _cursor = null;
    final snap = _cursor == null ? null : snaps[_cursor!];
    final wide = MediaQuery.sizeOf(context).width >= 700;

    final assets = snap?.assetsCents ?? store.totals.assetsCents;
    final liabilities = snap?.liabilitiesCents ?? store.totals.liabilitiesCents;
    final net = assets - liabilities;
    final color = net < 0 ? Crt.redText : (snap == null ? Crt.green : Crt.amber);

    // Variación frente al mes anterior al que se está mirando.
    final NetWorthSnapshot? previous;
    if (snap != null) {
      previous = _cursor! > 0 ? snaps[_cursor! - 1] : null;
    } else {
      final now = DateTime.now();
      previous = snaps.where((s) => s.id == monthId(DateTime(now.year, now.month - 1))).firstOrNull;
    }
    final change = previous == null ? null : net - previous.netWorthCents;

    final status = snap == null
        ? const StatusTag('En directo', color: Crt.green)
        : StatusTag(_playing ? '▶ Reproduciendo' : '◀◀ Cinta', color: Crt.amber);

    final readout = VhsGlitch(
      trigger: _cursor ?? -1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(
            snap == null ? 'PATRIMONIO NETO' : 'PATRIMONIO NETO · ${_monthYear.format(snap.month).toUpperCase()}',
            style: theme.textTheme.labelSmall,
          ),
          status,
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(context.money(net), style: crtReadout(wide ? 76 : 58, color)),
        ),
        const SizedBox(height: 8),
        if (change != null)
          StatusTag(
            '${change >= 0 ? '▲ +' : '▼ −'}${context.money(change.abs())} desde ${_monthLong.format(previous!.month)}',
            color: change >= 0 ? Crt.green : Crt.redText,
          )
        else
          Text(
            snap == null ? 'Primera lectura del mes. La variación aparece el mes que viene.' : 'Principio de la cinta.',
            style: theme.textTheme.bodySmall,
          ),
      ]),
    );

    final total = assets + liabilities;
    final split = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _Figure('Activos', assets, Crt.green)),
        Expanded(child: _Figure('Deudas', liabilities, Crt.redText, alignEnd: true)),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 10,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: flexShare(assets, total), child: const ColoredBox(color: Crt.greenDim)),
            if (liabilities > 0) ...[
              const SizedBox(width: 3),
              Expanded(flex: flexShare(liabilities, total), child: const ColoredBox(color: Crt.red)),
            ],
          ]),
        ),
      ),
    ]);

    final hasHistory = snaps.length >= 2;
    final deck = !hasHistory
        ? null
        : Row(children: [
            _DeckKey(Icons.fast_rewind, 'Mes anterior', () => _rewind(snaps)),
            const SizedBox(width: 6),
            _DeckKey(_playing ? Icons.pause : Icons.play_arrow, _playing ? 'Pausa' : 'Reproducir la evolución',
                () => _play(snaps), lit: _playing),
            const SizedBox(width: 6),
            _DeckKey(Icons.fast_forward, 'Mes siguiente', () => _forward(snaps)),
            const SizedBox(width: 6),
            _DeckKey(Icons.stop, 'Volver al directo', _stop, enabled: snap != null),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('CONTADOR', style: theme.textTheme.labelSmall),
              Text(
                '${((_cursor ?? snaps.length - 1) + 1).toString().padLeft(3, '0')}/${snaps.length.toString().padLeft(3, '0')}',
                style: mono(size: 13, weight: FontWeight.w700, color: Crt.amber),
              ),
            ]),
          ]);

    final chart = _Sparkline(store, highlight: _cursor);
    return CrtScreen(
      padding: const EdgeInsets.all(22),
      tint: snap == null ? Crt.green : Crt.amber,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (wide && hasHistory)
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(flex: 5, child: readout),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: SizedBox(height: 120, child: chart)),
          ])
        else ...[
          readout,
          if (hasHistory) ...[const SizedBox(height: 16), SizedBox(height: 90, child: chart)],
        ],
        if (deck != null) ...[const SizedBox(height: 14), deck],
        const SizedBox(height: 18),
        split,
      ]),
    );
  }
}

/// Tecla de pletina: baja 1 px al pulsarla, como una tecla con recorrido.
class _DeckKey extends StatefulWidget {
  const _DeckKey(this.icon, this.tooltip, this.onPressed, {this.lit = false, this.enabled = true});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool lit;
  final bool enabled;

  @override
  State<_DeckKey> createState() => _DeckKeyState();
}

class _DeckKeyState extends State<_DeckKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final color = !widget.enabled ? Crt.border : (widget.lit ? Crt.amber : Crt.beige);
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: widget.enabled
              ? (_) {
                  setState(() => _down = false);
                  widget.onPressed();
                }
              : null,
          child: MouseRegion(
            cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
              width: 44,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _down ? Crt.panel : Crt.panelHigh,
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  top: const BorderSide(color: Crt.border),
                  left: const BorderSide(color: Crt.border),
                  right: const BorderSide(color: Crt.border),
                  bottom: BorderSide(color: Crt.border, width: _down ? 1 : 3),
                ),
              ),
              child: Icon(widget.icon, size: 20, color: color, shadows: widget.lit ? glow(Crt.amber, blur: 6) : null),
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.cents, this.color, {this.alignEnd = false});

  final String label;
  final int cents;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 2),
      FittedBox(child: Text(context.money(cents), style: mono(size: 17, weight: FontWeight.w700, color: color))),
    ]);
  }
}

/// Evolución mensual del patrimonio neto. Resalta el mes que se está mirando
/// en la pletina ([highlight]) o, en directo, el último.
class _Sparkline extends StatelessWidget {
  const _Sparkline(this.store, {this.highlight});

  final NidoStore store;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final snaps = store.snapshots;
    final spots = [for (var i = 0; i < snaps.length; i++) FlSpot(i.toDouble(), snaps[i].netWorthCents / 100)];
    final ys = spots.map((s) => s.y);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * .15 + 1;
    final label = mono(size: 11, color: Crt.grey);

    return LineChart(LineChartData(
      minY: minY - pad,
      maxY: maxY + pad,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: ((maxY - minY).abs() / 2).clamp(1, double.infinity),
        getDrawingHorizontalLine: (_) => FlLine(color: Crt.green.withValues(alpha: .08), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 20,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (value != i || i < 0 || i >= snaps.length) return const SizedBox.shrink();
              return SideTitleWidget(meta: meta, child: Text(_monthShort.format(snaps[i].month).toUpperCase(), style: label));
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Crt.panelHigh,
          tooltipBorder: const BorderSide(color: Crt.green),
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${_monthLong.format(snaps[s.x.toInt()].month).toUpperCase()}\n${context.money((s.y * 100).round())}',
                mono(size: 12, color: Crt.green),
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: Crt.green,
          barWidth: 2.5,
          shadow: Shadow(color: Crt.green.withValues(alpha: .6), blurRadius: 8),
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, bar) => spot.x == (highlight?.toDouble() ?? bar.spots.last.x),
            getDotPainter: (_, _, _, _) =>
                FlDotCirclePainter(radius: 4.5, color: Crt.amber, strokeWidth: 2, strokeColor: Crt.screen),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Crt.green.withValues(alpha: .22), Crt.green.withValues(alpha: 0)],
            ),
          ),
        ),
      ],
    ));
  }
}

// ---------------------------------------------------------------- Indicadores

class _IndicatorsPanel extends StatelessWidget {
  const _IndicatorsPanel();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    // Mismo gasto de referencia que el fondo de emergencia dinámico.
    final reference = store.spending;
    final months = emergencyMonths(store.accounts, reference?.totalCents);
    final debt = debtRatio(store.totals);
    final burden = store.debtBurden;
    final saving = store.flow.savingsRate;

    final gauges = [
      _Indicator(
        title: 'Colchón de seguridad',
        reading: months == null ? '—' : '${_one.format(months)} MESES',
        value: months == null ? 0 : months / 12,
        caption: months == null || reference == null
            ? 'Registra gastos o programa recibos para calcular cuántos meses cubre tu liquidez.'
            : '${months >= 6 ? 'Tu liquidez cubre más de 6 meses de gastos.' : months >= 3 ? 'Cubres 3 meses o más. El objetivo habitual es 6.' : 'Menos de 3 meses de gastos cubiertos.'}\n'
                'Gasto de ${context.money(reference.totalCents)}/mes: '
                '${context.money(reference.fixedCents)} fijo + ${context.money(reference.variableCents)} variable.',
      ),
      // Con planes a plazos, lo que cuenta es cuánto de lo que entra se va en
      // cuotas (escala hasta el 60 %; rojo desde el 35 %, como los bancos).
      if (burden != null)
        _Indicator(
          title: 'Cuotas / ingresos',
          reading: _pct.format(burden),
          value: burden / .6,
          zones: const [(0.0, Crt.green), (0.42, Crt.amber), (0.58, Crt.redText)],
          caption: burden > .35
              ? 'Más del 35 % de lo que entra se va en cuotas.'
              : 'Parte de tus ingresos que se va en cuotas. El límite sano está en el 35 %.',
        )
      else
        _Indicator(
          title: 'Endeudamiento',
          reading: debt == null ? '—' : _pct.format(debt),
          value: debt ?? 0,
          // Aquí mejor cuanto más bajo.
          zones: const [(0.0, Crt.green), (0.4, Crt.amber), (0.7, Crt.redText)],
          caption: debt == null ? 'Sin activos todavía.' : 'Deudas sobre el total de lo que tienes.',
        ),
      _Indicator(
        title: 'Tasa de ahorro',
        reading: saving == null ? '—' : _pct.format(saving),
        value: saving == null ? 0 : (saving / .4).clamp(0, 1),
        zones: const [(0.0, Crt.redText), (0.25, Crt.amber), (0.5, Crt.green)],
        caption: saving == null ? 'Aparece cuando registras ingresos este mes.' : 'Parte de los ingresos del mes que no se ha gastado.',
      ),
    ];

    return Panel(
      title: 'Indicadores',
      child: LayoutBuilder(builder: (context, c) {
        // Los tres en fila o los tres apilados: ninguno se queda solo.
        final perRow = c.maxWidth >= 430 ? 3 : 1;
        final w = (c.maxWidth - 12 * (perRow - 1)) / perRow;
        return Wrap(spacing: 12, runSpacing: 22, children: [for (final g in gauges) SizedBox(width: w, child: g)]);
      }),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.title,
    required this.reading,
    required this.value,
    required this.caption,
    this.zones = const [(0.0, Crt.redText), (0.25, Crt.amber), (0.5, Crt.green)],
  });

  final String title;
  final String reading;
  final double value;
  final String caption;
  final List<(double, Color)> zones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Text(title.toUpperCase(), style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, c) => AnalogGauge(value: value, label: reading, size: c.maxWidth.clamp(110, 160), zones: zones),
      ),
      const SizedBox(height: 8),
      Text(caption, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
    ]);
  }
}

// ---------------------------------------------------------------- Mes

class _MonthPanel extends StatelessWidget {
  const _MonthPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final flow = store.flow;
    final categories = expensesByCategory(store.movements).take(5).toList();
    final theme = Theme.of(context);

    return Panel(
      title: 'Mes de ${_monthLong.format(store.month)}',
      trailing: TextButton(onPressed: onTap, child: const Text('VER MOVIMIENTOS')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _FlowFigure('Ingresos', SignedAmount(flow.incomeCents, size: 17))),
          Expanded(child: _FlowFigure('Gastos', SignedAmount(-flow.expenseCents, size: 17))),
          Expanded(child: _FlowFigure('Balance', SignedAmount(flow.balanceCents, size: 17))),
        ]),
        const SizedBox(height: 18),
        if (categories.isEmpty)
          Text('Sin gastos registrados este mes.', style: theme.textTheme.bodySmall)
        else ...[
          Text('EN QUÉ SE VA EL DINERO', style: theme.textTheme.labelSmall),
          const SizedBox(height: 10),
          for (final c in categories) ...[
            CategoryBar(category: categoryOf(MovementKind.expense, c.key), cents: c.value, total: flow.expenseCents),
            const SizedBox(height: 10),
          ],
        ],
      ]),
    );
  }
}

class _FlowFigure extends StatelessWidget {
  const _FlowFigure(this.label, this.value);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 4),
      FittedBox(child: value),
    ]);
  }
}

// ---------------------------------------------------------------- Distribución

class _DistributionPanel extends StatelessWidget {
  const _DistributionPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final totals = groupTotals(store.accounts);
    final assets = store.totals.assetsCents;
    final palette = context.nido;
    final theme = Theme.of(context);
    final groups = AccountGroup.values.where((g) => g != AccountGroup.debts && totals[g]! > 0).toList();

    return Panel(
      title: 'Dónde está tu dinero',
      trailing: TextButton(onPressed: onTap, child: const Text('CUENTAS')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (groups.isEmpty)
          Text('Sin activos con saldo positivo.', style: theme.textTheme.bodySmall)
        else ...[
          // Barra apilada con la composición de los activos.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 14,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(flex: flexShare(totals[groups[i]]!, assets), child: ColoredBox(color: palette.group(groups[i]))),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 14),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Icon(g.icon, size: 20, color: palette.group(g)),
                const SizedBox(width: 10),
                Expanded(child: Text(g.label.toUpperCase(), style: theme.textTheme.bodyLarge)),
                Text(_pct.format(totals[g]! / assets), style: mono(size: 13, color: Crt.grey)),
                const SizedBox(width: 14),
                Text(context.money(totals[g]!), style: mono(size: 14, weight: FontWeight.w700, color: Crt.offWhite)),
              ]),
            ),
        ],
        if (totals[AccountGroup.debts]! > 0) ...[
          const Divider(height: 24),
          Row(children: [
            Icon(AccountGroup.debts.icon, size: 20, color: palette.negative),
            const SizedBox(width: 10),
            Expanded(child: Text('DEUDAS', style: theme.textTheme.bodyLarge)),
            Text('−${context.money(totals[AccountGroup.debts]!)}',
                style: mono(size: 14, weight: FontWeight.w700, color: palette.negative)),
          ]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- Objetivos

class _GoalsPanel extends StatelessWidget {
  const _GoalsPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    return Panel(
      title: 'Objetivos',
      trailing: TextButton(onPressed: onTap, child: const Text('VER TODOS')),
      child: store.goals.isEmpty
          ? Row(children: [
              Expanded(child: Text('Ponte una meta: un colchón, una entrada, un viaje.', style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: () => openGoalForm(context), child: const Text('CREAR')),
            ])
          : Column(children: [
              for (final g in store.goals.take(3)) ...[
                GoalProgressRow(goal: g),
                const SizedBox(height: 14),
              ],
            ]),
    );
  }
}

// ---------------------------------------------------------------- Próximos cargos

/// Lo que se va a apuntar solo en los próximos 14 días, y lo que espera confirmación.
class _UpcomingPanel extends StatelessWidget {
  const _UpcomingPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    final next = store.upcoming(days: 14).take(5).toList();
    final pending = store.toConfirm.length;
    return Panel(
      title: 'Próximos cargos',
      trailing: TextButton(onPressed: onTap, child: const Text('RECURRENTES')),
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InkWell(
              onTap: onTap,
              child: StatusTag('$pending por confirmar', color: Crt.amber),
            ),
          ),
        if (store.recurrences.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(
                child: Text('Programa la nómina, el alquiler o tus suscripciones y Nido los apunta solo.',
                    style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: () => openProgramChooser(context), child: const Text('PROGRAMAR')),
            ]),
          )
        else if (next.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Nada previsto en las próximas dos semanas.', style: theme.textTheme.bodySmall),
          )
        else
          for (final u in next) UpcomingRow(u.r, u.date),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Recientes

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    final items = store.recent.take(6).toList();
    return Panel(
      title: 'Últimos movimientos',
      trailing: TextButton(onPressed: onTap, child: const Text('TODOS')),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Aún no hay movimientos. Pulsa + MOVIMIENTO en la pestaña Movimientos.', style: theme.textTheme.bodySmall),
            )
          : Column(children: [
              for (final m in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox(width: 58, child: Text(_dayShort.format(m.date).toUpperCase(), style: mono(size: 12, color: Crt.grey))),
                    Icon(categoryOf(m.kind, m.category).icon, size: 18, color: Crt.beige),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        m.note.isEmpty ? categoryOf(m.kind, m.category).label : m.note,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    movementAmount(m, size: 14),
                  ]),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------- Inicio

const _templates = <(String, AccountType)>[
  ('Cuenta corriente', AccountType.bank),
  ('Cuenta de ahorro', AccountType.savings),
  ('Fondo indexado', AccountType.investment),
  ('Vivienda', AccountType.property),
  ('Coche', AccountType.vehicle),
  ('Hipoteca', AccountType.mortgage),
  ('Tarjeta de crédito', AccountType.creditCard),
];

class _Onboarding extends StatelessWidget {
  const _Onboarding({required this.onNavigate});

  final void Function(int) onNavigate;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NidoStore>();
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final welcome = CrtScreen(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PATRIMONIO NETO', style: theme.textTheme.labelSmall),
        const SizedBox(height: 6),
        Row(children: [
          Text(formatCents(0), style: crtReadout(wide ? 72 : 54, Crt.green)),
          const SizedBox(width: 10),
          BlinkingCursor(size: wide ? 60 : 46),
        ]),
        const SizedBox(height: 14),
        Text(
          'Tu nido está vacío. Apunta lo que tienes y lo que debes, y Nido calcula tu patrimonio neto, '
          'tu colchón de seguridad y cómo evoluciona mes a mes.',
          style: theme.textTheme.bodyLarge?.copyWith(color: Crt.beige),
        ),
      ]),
    );

    final steps = Panel(
      title: 'Primeros pasos',
      child: Column(children: const [
        _Step(1, Icons.account_balance_wallet_outlined, 'Añade tus cuentas y bienes',
            'Cuenta corriente, ahorro, fondos, vivienda… y también hipoteca o tarjeta.'),
        _Step(2, Icons.swap_vert, 'Registra lo que entra y sale', 'Los saldos se ajustan solos con cada movimiento.'),
        _Step(3, Icons.flag_outlined, 'Ponte un objetivo', 'Vincúlalo a una cuenta y Nido mide el progreso.'),
      ]),
    );

    final quick = Panel(
      title: 'Añade rápido',
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (name, type) in _templates)
          HoverLift(
            child: ActionChip(
              avatar: Icon(type.icon, size: 18, color: type.liability ? Crt.redText : Crt.green),
              label: Text(name.toUpperCase()),
              onPressed: () => openAccountForm(context, presetType: type, presetName: name),
            ),
          ),
      ]),
    );

    final demo = Panel(
      title: 'O míralo funcionando',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Carga un hogar de ejemplo: nómina, hipoteca, un fondo indexado, tres meses de gastos y tres objetivos. '
          'Va marcado como ejemplo y se quita con un botón.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: store.sampleBusy
              ? const TapeReels(width: 90, label: 'GRABANDO EJEMPLOS')
              : FilledButton.icon(
                  onPressed: store.loadSampleData,
                  style: FilledButton.styleFrom(backgroundColor: Crt.amber, foregroundColor: theme.colorScheme.onSecondary),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('EXPLORAR CON DATOS DE EJEMPLO'),
                ),
        ),
      ]),
    );

    if (!wide) {
      return PageBody(children: [welcome, const SizedBox(height: 16), steps, const SizedBox(height: 16), quick, const SizedBox(height: 16), demo]);
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 112),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Reveal(child: welcome),
            const SizedBox(height: 18),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 6, child: Reveal(index: 1, child: steps)),
              const SizedBox(width: 18),
              Expanded(
                flex: 5,
                child: Column(children: [
                  Reveal(index: 2, child: quick),
                  const SizedBox(height: 18),
                  Reveal(index: 3, child: demo),
                ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.icon, this.title, this.text);

  final int number;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Crt.screen,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Crt.green, width: 1.5),
          ),
          child: Text('$number', style: crtReadout(26, Crt.green)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: Crt.beige),
              const SizedBox(width: 8),
              Flexible(child: Text(title.toUpperCase(), style: theme.textTheme.titleSmall?.copyWith(color: Crt.offWhite))),
            ]),
            const SizedBox(height: 2),
            Text(text, style: theme.textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}
