import 'package:flutter/material.dart';

/// Destaque único da marca. Verde/vermelho só para lucro/prejuízo e alertas.
const indigo = Color(0xFF5E5CE6);
const indigoEscuro = Color(0xFF7D7AFF);

const verde = Color(0xFF16A34A);
const vermelho = Color(0xFFDC2626);
const amarelo = Color(0xFFF59E0B);

/// Valores em R$ e gramas não "dançam" quando mudam.
const tabular = [FontFeature.tabularFigures()];

ThemeData temaCubo3(Brightness brilho) {
  final escuro = brilho == Brightness.dark;
  // Neutros cinza-zinco (escala do Tailwind).
  final fundo = escuro ? const Color(0xFF09090B) : const Color(0xFFFAFAFA);
  final superficie = escuro ? const Color(0xFF18181B) : Colors.white;
  final borda = escuro ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
  final texto = escuro ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);
  final textoFraco = escuro ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
  final primaria = escuro ? indigoEscuro : indigo;

  final esquema = ColorScheme(
    brightness: brilho,
    primary: primaria,
    onPrimary: Colors.white,
    primaryContainer: primaria.withValues(alpha: 0.14),
    onPrimaryContainer: primaria,
    secondary: primaria,
    onSecondary: Colors.white,
    secondaryContainer: primaria.withValues(alpha: 0.14),
    onSecondaryContainer: texto,
    error: vermelho,
    onError: Colors.white,
    surface: fundo,
    onSurface: texto,
    onSurfaceVariant: textoFraco,
    surfaceContainerLowest: superficie,
    surfaceContainerLow: superficie,
    surfaceContainer: superficie,
    surfaceContainerHigh: escuro ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
    surfaceContainerHighest: escuro ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
    outline: escuro ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
    outlineVariant: borda,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: fundo,
    appBarTheme: AppBarTheme(
      backgroundColor: fundo,
      foregroundColor: texto,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borda)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: superficie,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borda)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borda)),
    ),
    dividerTheme: DividerThemeData(color: borda, space: 1),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: superficie, indicatorColor: esquema.primaryContainer),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: superficie, indicatorColor: esquema.primaryContainer),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: primaria, foregroundColor: Colors.white),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
  );
}
