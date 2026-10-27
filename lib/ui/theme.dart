import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/account.dart';

// Sistema de diseño: cassette futurism (.claude/skills/design/SKILL.md).
// Solo tema oscuro. Paleta de la guía:
//   CRT Green #33FF00 · Phosphor Amber #FFB000 · Tape Red #CC0000
//   Charcoal #333333 · Warm Beige #D2B48C · Static Grey #999999 · Off-White #E8E0D0
// Tipografía: VT323 para la interfaz, JetBrains Mono para importes y datos.
// Forma: radio base 8 px y bordes gruesos, como el plástico de una pletina.

const _ui = 'VT323';
const _mono = 'JetBrainsMono';

abstract final class Crt {
  static const green = Color(0xFF33FF00);
  static const greenDim = Color(0xFF1E7A0A);
  static const greenDeep = Color(0xFF12300A);
  static const amber = Color(0xFFFFB000);
  static const amberDeep = Color(0xFF3D2A00);
  static const red = Color(0xFFCC0000);
  static const redText = Color(0xFFFF5A4A);
  static const beige = Color(0xFFD2B48C);
  static const grey = Color(0xFF999999);
  static const offWhite = Color(0xFFE8E0D0);
  static const navy = Color(0xFF1B2838);

  /// Fondo general: carbón profundo, nunca negro puro.
  static const background = Color(0xFF1C1D1A);

  /// Paneles: el carbón de la guía.
  static const panel = Color(0xFF2A2B27);
  static const panelHigh = Color(0xFF333333);

  /// Pantallas CRT incrustadas (lecturas grandes, gráficas).
  static const screen = Color(0xFF111410);
  static const border = Color(0xFF4A4B45);
  static const borderSoft = Color(0xFF393A35);
}

/// Colores de Nido que Material no cubre.
@immutable
class NidoPalette extends ThemeExtension<NidoPalette> {
  const NidoPalette();

  Color get positive => Crt.green;
  Color get negative => Crt.redText;
  Color get attention => Crt.amber;

  Color group(AccountGroup g) => switch (g) {
        AccountGroup.liquidity => Crt.green,
        AccountGroup.investments => Crt.amber,
        AccountGroup.belongings => Crt.beige,
        AccountGroup.debts => Crt.redText,
      };

  @override
  NidoPalette copyWith() => this;

  @override
  NidoPalette lerp(NidoPalette? other, double t) => this;
}

extension NidoThemeX on BuildContext {
  NidoPalette get nido => Theme.of(this).extension<NidoPalette>()!;
}

/// Brillo de fósforo para lecturas importantes.
List<Shadow> glow(Color color, {double blur = 10}) => [
      Shadow(color: color.withValues(alpha: .55), blurRadius: blur),
      Shadow(color: color.withValues(alpha: .25), blurRadius: blur * 2.4),
    ];

/// Importes y datos técnicos: JetBrains Mono (monoespaciada, columnas cuadradas).
TextStyle mono({double size = 15, FontWeight weight = FontWeight.w500, Color? color, double? height}) =>
    TextStyle(
      fontFamily: _mono,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Lectura grande tipo pantalla CRT (patrimonio, totales).
TextStyle crtReadout(double size, Color color) => TextStyle(
      fontFamily: _ui,
      fontSize: size,
      height: 1,
      color: color,
      letterSpacing: 1,
      shadows: glow(color, blur: size / 5),
    );

ThemeData nidoTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Crt.green,
    onPrimary: Color(0xFF0E140B),
    primaryContainer: Crt.greenDeep,
    onPrimaryContainer: Color(0xFFA6FF8C),
    secondary: Crt.amber,
    onSecondary: Color(0xFF1E1600),
    secondaryContainer: Crt.amberDeep,
    onSecondaryContainer: Color(0xFFFFD98A),
    tertiary: Crt.beige,
    onTertiary: Color(0xFF231A0C),
    error: Crt.redText,
    onError: Color(0xFF1A0000),
    errorContainer: Color(0xFF3A0B07),
    onErrorContainer: Color(0xFFFFB4A8),
    surface: Crt.panel,
    onSurface: Crt.offWhite,
    onSurfaceVariant: Crt.grey,
    outline: Crt.border,
    outlineVariant: Crt.borderSoft,
    surfaceContainerLowest: Crt.background,
    surfaceContainerLow: Crt.panel,
    surfaceContainer: Color(0xFF23241F),
    surfaceContainerHigh: Crt.panelHigh,
    surfaceContainerHighest: Color(0xFF3B3C37),
    inverseSurface: Crt.offWhite,
    onInverseSurface: Crt.background,
    inversePrimary: Crt.greenDim,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  // VT323 tiene poca altura de x: la escala va unos puntos por encima de Material.
  TextStyle ui(double size, {Color color = Crt.offWhite, double spacing = 0.3, double height = 1.15}) =>
      TextStyle(fontFamily: _ui, fontSize: size, color: color, letterSpacing: spacing, height: height);

  final textTheme = TextTheme(
    displayLarge: ui(64, height: 1),
    displayMedium: ui(52, height: 1),
    displaySmall: ui(44, height: 1),
    headlineLarge: ui(38),
    headlineMedium: ui(32),
    headlineSmall: ui(28),
    titleLarge: ui(26),
    titleMedium: ui(23),
    titleSmall: ui(21),
    bodyLarge: ui(21, height: 1.3),
    bodyMedium: ui(19, height: 1.3),
    bodySmall: ui(17, color: Crt.grey, height: 1.3),
    labelLarge: ui(20, spacing: 1.2),
    labelMedium: ui(18, spacing: 1.2),
    // Etiquetas en mayúsculas.
    labelSmall: ui(16, color: Crt.beige, spacing: 2),
  );

  final radius = BorderRadius.circular(8);
  final buttonText = textTheme.labelLarge!;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: _ui,
    textTheme: textTheme,
    extensions: const [NidoPalette()],
    scaffoldBackgroundColor: Crt.background,
    splashFactory: InkSparkle.splashFactory,
    cardTheme: CardThemeData(
      elevation: 0,
      color: Crt.panel,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: Crt.border, width: 2)),
    ),
    appBarTheme: AppBarTheme(
      // Barras del sistema (Android) oscuras con iconos claros.
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Crt.background,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Crt.panel,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      backgroundColor: Crt.background,
      foregroundColor: Crt.offWhite,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.headlineSmall?.copyWith(color: Crt.green, shadows: glow(Crt.green, blur: 6)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Crt.panel,
      indicatorColor: Crt.greenDeep,
      surfaceTintColor: Colors.transparent,
      indicatorShape: RoundedRectangleBorder(borderRadius: radius),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Crt.green : Crt.grey),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => textTheme.labelMedium!.copyWith(color: s.contains(WidgetState.selected) ? Crt.green : Crt.grey),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Crt.panel,
      indicatorColor: Crt.greenDeep,
      indicatorShape: RoundedRectangleBorder(borderRadius: radius),
      selectedIconTheme: const IconThemeData(color: Crt.green),
      unselectedIconTheme: const IconThemeData(color: Crt.grey),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: Crt.green),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: Crt.grey),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Crt.green,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      highlightElevation: 0,
      extendedTextStyle: buttonText,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    // Botón principal: relleno verde y texto carbón (la guía pide texto ámbar,
    // pero ámbar sobre verde no se lee; se mantiene el contraste).
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Crt.green,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: Crt.greenDim,
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Crt.green,
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: const BorderSide(color: Crt.grey, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Crt.green,
        textStyle: buttonText,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Crt.beige)),
    // Las etiquetas van encima del campo (ver LabeledField), sin etiquetas flotantes.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Crt.screen,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: textTheme.bodyMedium?.copyWith(color: Crt.grey.withValues(alpha: .6)),
      suffixStyle: mono(size: 15, color: Crt.beige),
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Crt.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Crt.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Crt.green, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Crt.redText)),
      focusedErrorBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: Crt.redText, width: 2)),
      errorStyle: textTheme.bodySmall?.copyWith(color: Crt.redText),
      counterStyle: textTheme.bodySmall,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: textTheme.bodyLarge),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Crt.screen,
        foregroundColor: Crt.grey,
        selectedBackgroundColor: Crt.greenDeep,
        selectedForegroundColor: Crt.green,
        side: const BorderSide(color: Crt.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: textTheme.labelMedium,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Crt.screen,
      selectedColor: Crt.greenDeep,
      checkmarkColor: Crt.green,
      side: const BorderSide(color: Crt.border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: radius),
      labelStyle: textTheme.labelMedium,
    ),
    dividerTheme: const DividerThemeData(color: Crt.borderSoft, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      titleTextStyle: textTheme.bodyLarge,
      subtitleTextStyle: textTheme.bodySmall,
      iconColor: Crt.beige,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Crt.green,
      linearTrackColor: Crt.screen,
      circularTrackColor: Crt.screen,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Crt.panel,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: Crt.border, width: 2)),
      titleTextStyle: textTheme.headlineSmall?.copyWith(color: Crt.green),
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Crt.panel,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Crt.grey,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        side: BorderSide(color: Crt.border, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Crt.panelHigh,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Crt.amber),
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: Crt.amber)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: Crt.panelHigh, borderRadius: radius, border: Border.all(color: Crt.border)),
      textStyle: textTheme.bodySmall?.copyWith(color: Crt.offWhite),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Crt.panel,
      headerBackgroundColor: Crt.screen,
      headerForegroundColor: Crt.green,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: Crt.border, width: 2)),
    ),
  );
}
