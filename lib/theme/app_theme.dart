import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PaletteSpec {
  const PaletteSpec({
    required this.id,
    required this.name,
    required this.seed,
    required this.background,
    required this.surface,
    required this.sidebar,
    required this.brightness,
  });

  final String id;
  final String name;
  final Color seed;
  final Color background;
  final Color surface;
  final Color sidebar;
  final Brightness brightness;
}

const palettes = <PaletteSpec>[
  PaletteSpec(
    id: 'yejian',
    name: '页间紫',
    seed: Color(0xFF75588E),
    background: Color(0xFFF8F6F1),
    surface: Color(0xFFFFFEFC),
    sidebar: Color(0xFFF1ECF5),
    brightness: Brightness.light,
  ),
  PaletteSpec(
    id: 'mist',
    name: '雾蓝',
    seed: Color(0xFF4F6B78),
    background: Color(0xFFF3F5F4),
    surface: Color(0xFFFCFDFC),
    sidebar: Color(0xFFE7ECEA),
    brightness: Brightness.light,
  ),
  PaletteSpec(
    id: 'paper',
    name: '纸页',
    seed: Color(0xFF79624C),
    background: Color(0xFFF5F0E7),
    surface: Color(0xFFFFFCF6),
    sidebar: Color(0xFFECE2D2),
    brightness: Brightness.light,
  ),
  PaletteSpec(
    id: 'forest',
    name: '松影',
    seed: Color(0xFF3F6654),
    background: Color(0xFFF0F4F0),
    surface: Color(0xFFFBFDFB),
    sidebar: Color(0xFFE1EAE3),
    brightness: Brightness.light,
  ),
  PaletteSpec(
    id: 'midnight',
    name: '夜航',
    seed: Color(0xFF58768A),
    background: Color(0xFFF2F5F7),
    surface: Color(0xFFFCFDFE),
    sidebar: Color(0xFFE5EBEF),
    brightness: Brightness.light,
  ),
];

PaletteSpec paletteById(String id) => palettes.firstWhere(
  (palette) => palette.id == id,
  orElse: () => palettes.first,
);

ThemeData buildTheme(
  String paletteId, {
  Brightness brightness = Brightness.light,
  String? customFontFamily,
}) {
  final palette = paletteById(paletteId);
  final dark = brightness == Brightness.dark;
  final background = dark
      ? Color.alphaBlend(
          palette.seed.withValues(alpha: .055),
          const Color(0xFF121315),
        )
      : palette.background;
  final surface = dark
      ? Color.alphaBlend(
          palette.seed.withValues(alpha: .07),
          const Color(0xFF1B1C20),
        )
      : palette.surface;
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: brightness,
    surface: surface,
  );
  final border = dark
      ? const Color(0xFF354146)
      : palette.id == 'yejian'
      ? const Color(0xFFE2D9E8)
      : const Color(0xFFD9E0DD);
  final typography = Typography.material2021(
    platform: defaultTargetPlatform,
    colorScheme: scheme,
  );
  final baseTextTheme = dark ? typography.white : typography.black;
  final textTheme = customFontFamily == null
      ? baseTextTheme
      : baseTextTheme.apply(fontFamily: customFontFamily);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: customFontFamily,
    fontFamilyFallback: const [
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    textTheme: textTheme.copyWith(
      displaySmall: textTheme.displaySmall?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.55),
    ),
    dividerColor: border,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      centerTitle: false,
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 58,
      elevation: 0,
      backgroundColor: surface,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _YejianPageTransitionsBuilder(),
        TargetPlatform.iOS: _YejianPageTransitionsBuilder(),
        TargetPlatform.macOS: _YejianPageTransitionsBuilder(),
        TargetPlatform.windows: _YejianPageTransitionsBuilder(),
        TargetPlatform.linux: _YejianPageTransitionsBuilder(),
        TargetPlatform.fuchsia: _YejianPageTransitionsBuilder(),
      },
    ),
  );
}

class _YejianPageTransitionsBuilder extends PageTransitionsBuilder {
  const _YejianPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.035, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
