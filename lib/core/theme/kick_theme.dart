import 'dart:ui' show lerpDouble;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

class KickThemeBootstrapData {
  const KickThemeBootstrapData({
    required this.resolved,
    this.lightDynamicScheme,
    this.darkDynamicScheme,
  });

  const KickThemeBootstrapData.unresolved()
    : resolved = false,
      lightDynamicScheme = null,
      darkDynamicScheme = null;

  final bool resolved;
  final ColorScheme? lightDynamicScheme;
  final ColorScheme? darkDynamicScheme;

  static Future<KickThemeBootstrapData> load() async {
    try {
      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (corePalette != null) {
        return KickThemeBootstrapData(
          resolved: true,
          lightDynamicScheme: corePalette.toColorScheme(),
          darkDynamicScheme: corePalette.toColorScheme(brightness: Brightness.dark),
        );
      }
    } catch (_) {
      // Dynamic color is best-effort during bootstrap.
    }

    try {
      final accentColor = await DynamicColorPlugin.getAccentColor();
      if (accentColor != null) {
        return KickThemeBootstrapData(
          resolved: true,
          lightDynamicScheme: ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: Brightness.light,
          ),
          darkDynamicScheme: ColorScheme.fromSeed(
            seedColor: accentColor,
            brightness: Brightness.dark,
          ),
        );
      }
    } catch (_) {
      // Accent color is best-effort during bootstrap.
    }

    return const KickThemeBootstrapData(resolved: true);
  }
}

class KickThemeBuilder extends StatelessWidget {
  const KickThemeBuilder({
    super.key,
    required this.themeMode,
    required this.useDynamicColor,
    required this.builder,
    this.bootstrapData = const KickThemeBootstrapData.unresolved(),
  });

  final ThemeMode themeMode;
  final bool useDynamicColor;
  final Widget Function(ThemeData lightTheme, ThemeData darkTheme) builder;
  final KickThemeBootstrapData bootstrapData;

  @override
  Widget build(BuildContext context) {
    if (bootstrapData.resolved) {
      final lightScheme = useDynamicColor && bootstrapData.lightDynamicScheme != null
          ? bootstrapData.lightDynamicScheme!.harmonized()
          : KickSchemes.light;
      final darkScheme = useDynamicColor && bootstrapData.darkDynamicScheme != null
          ? bootstrapData.darkDynamicScheme!.harmonized()
          : KickSchemes.dark;
      return builder(KickThemeData.build(lightScheme), KickThemeData.build(darkScheme));
    }

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme = useDynamicColor && lightDynamic != null
            ? lightDynamic.harmonized()
            : KickSchemes.light;
        final darkScheme = useDynamicColor && darkDynamic != null
            ? darkDynamic.harmonized()
            : KickSchemes.dark;
        return builder(KickThemeData.build(lightScheme), KickThemeData.build(darkScheme));
      },
    );
  }
}

@immutable
class KickThemeTokens extends ThemeExtension<KickThemeTokens> {
  const KickThemeTokens({
    required this.pageGutter,
    required this.sectionGap,
    required this.panelRadius,
    required this.heroRadius,
    required this.pillRadius,
    required this.shortDuration,
    required this.mediumDuration,
    required this.longDuration,
    required this.standardCurve,
    required this.emphasizedCurve,
  });

  final double pageGutter;
  final double sectionGap;
  final double panelRadius;
  final double heroRadius;
  final double pillRadius;
  final Duration shortDuration;
  final Duration mediumDuration;
  final Duration longDuration;
  final Curve standardCurve;
  final Curve emphasizedCurve;

  static const fallback = KickThemeTokens(
    pageGutter: 24,
    sectionGap: 20,
    panelRadius: 28,
    heroRadius: 36,
    pillRadius: 18,
    shortDuration: Duration(milliseconds: 220),
    mediumDuration: Duration(milliseconds: 380),
    longDuration: Duration(milliseconds: 540),
    standardCurve: Curves.easeOutCubic,
    emphasizedCurve: Curves.easeOutQuart,
  );

  @override
  KickThemeTokens copyWith({
    double? pageGutter,
    double? sectionGap,
    double? panelRadius,
    double? heroRadius,
    double? pillRadius,
    Duration? shortDuration,
    Duration? mediumDuration,
    Duration? longDuration,
    Curve? standardCurve,
    Curve? emphasizedCurve,
  }) {
    return KickThemeTokens(
      pageGutter: pageGutter ?? this.pageGutter,
      sectionGap: sectionGap ?? this.sectionGap,
      panelRadius: panelRadius ?? this.panelRadius,
      heroRadius: heroRadius ?? this.heroRadius,
      pillRadius: pillRadius ?? this.pillRadius,
      shortDuration: shortDuration ?? this.shortDuration,
      mediumDuration: mediumDuration ?? this.mediumDuration,
      longDuration: longDuration ?? this.longDuration,
      standardCurve: standardCurve ?? this.standardCurve,
      emphasizedCurve: emphasizedCurve ?? this.emphasizedCurve,
    );
  }

  @override
  KickThemeTokens lerp(ThemeExtension<KickThemeTokens>? other, double t) {
    if (other is! KickThemeTokens) {
      return this;
    }

    return KickThemeTokens(
      pageGutter: lerpDouble(pageGutter, other.pageGutter, t) ?? pageGutter,
      sectionGap: lerpDouble(sectionGap, other.sectionGap, t) ?? sectionGap,
      panelRadius: lerpDouble(panelRadius, other.panelRadius, t) ?? panelRadius,
      heroRadius: lerpDouble(heroRadius, other.heroRadius, t) ?? heroRadius,
      pillRadius: lerpDouble(pillRadius, other.pillRadius, t) ?? pillRadius,
      shortDuration: t < 0.5 ? shortDuration : other.shortDuration,
      mediumDuration: t < 0.5 ? mediumDuration : other.mediumDuration,
      longDuration: t < 0.5 ? longDuration : other.longDuration,
      standardCurve: t < 0.5 ? standardCurve : other.standardCurve,
      emphasizedCurve: t < 0.5 ? emphasizedCurve : other.emphasizedCurve,
    );
  }
}

extension KickThemeBuildContext on BuildContext {
  KickThemeTokens get kickTokens =>
      Theme.of(this).extension<KickThemeTokens>() ?? KickThemeTokens.fallback;
}

class KickThemeData {
  static ThemeData build(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      visualDensity: VisualDensity.standard,
    );
    const tokens = KickThemeTokens.fallback;

    final textTheme = base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 0.98,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
        height: 1,
      ),
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.02,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.06,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.08,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.24,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.16,
      ),
    );

    final panelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.panelRadius),
    );
    final heroShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.heroRadius),
    );

    return base.copyWith(
      extensions: const [tokens],
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: panelShape,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: _layeredColor(scheme.primary, scheme.primaryContainer, 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return (selected ? textTheme.labelLarge : textTheme.labelMedium)?.copyWith(
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        minWidth: 82,
        minExtendedWidth: 232,
        useIndicator: true,
        indicatorColor: _layeredColor(scheme.primary, scheme.primaryContainer, 0.12),
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer, size: 24),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          backgroundColor: scheme.surfaceContainerLow,
          hoverColor: scheme.primary.withValues(alpha: 0.08),
          highlightColor: scheme.primary.withValues(alpha: 0.12),
          minimumSize: const Size.square(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.pillRadius)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: textTheme.labelLarge,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.panelRadius - 6),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: textTheme.labelLarge,
          elevation: 0,
          backgroundColor: scheme.surfaceContainerLow,
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.panelRadius - 6),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.panelRadius - 6),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.pillRadius)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.panelRadius - 6)),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: scheme.primary.withValues(alpha: 0.18));
            }
            return BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.52));
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _layeredColor(scheme.primary, scheme.primaryContainer, 0.14);
            }
            return scheme.surfaceContainerLowest;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant;
          }),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.84),
        ),
        helperStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.panelRadius - 6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.panelRadius - 6),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.52)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.panelRadius - 6),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.44),
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.pillRadius)),
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: heroShape,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.panelRadius)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.panelRadius - 8)),
        iconColor: scheme.onSurfaceVariant,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return scheme.outlineVariant.withValues(alpha: 0.55);
        }),
      ),
    );
  }

  static Color _layeredColor(Color tint, Color surface, double opacity) {
    return Color.alphaBlend(tint.withValues(alpha: opacity), surface);
  }
}

class KickSchemes {
  static const light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xff50653e),
    onPrimary: Color(0xffffffff),
    primaryContainer: Color(0xffd3e8bc),
    onPrimaryContainer: Color(0xff394b2a),
    secondary: Color(0xff7a6144),
    onSecondary: Color(0xffffffff),
    secondaryContainer: Color(0xffffddb8),
    onSecondaryContainer: Color(0xff61492d),
    tertiary: Color(0xff6a5d2f),
    onTertiary: Color(0xffffffff),
    tertiaryContainer: Color(0xfff4e29b),
    onTertiaryContainer: Color(0xff51461a),
    error: Color(0xffba1a1a),
    onError: Color(0xffffffff),
    errorContainer: Color(0xffffdad6),
    onErrorContainer: Color(0xff93000a),
    surface: Color(0xfffbfaf2),
    onSurface: Color(0xff21201b),
    onSurfaceVariant: Color(0xff5a584f),
    outline: Color(0xff8b887d),
    outlineVariant: Color(0xffddd9cc),
    shadow: Color(0xff000000),
    scrim: Color(0xff000000),
    inverseSurface: Color(0xff31302a),
    onInverseSurface: Color(0xfff4f0e6),
    inversePrimary: Color(0xffb8cea1),
    surfaceTint: Color(0xff50653e),
    surfaceDim: Color(0xffddd9d0),
    surfaceBright: Color(0xfffbfaf2),
    surfaceContainerLowest: Color(0xffffffff),
    surfaceContainerLow: Color(0xfff6f3e8),
    surfaceContainer: Color(0xfff0ede3),
    surfaceContainerHigh: Color(0xffebe7dd),
    surfaceContainerHighest: Color(0xffe5e2d7),
  );

  static const dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xffb8cea1),
    onPrimary: Color(0xff223016),
    primaryContainer: Color(0xff394b2a),
    onPrimaryContainer: Color(0xffd3e8bc),
    secondary: Color(0xffebc79f),
    onSecondary: Color(0xff46311a),
    secondaryContainer: Color(0xff61492d),
    onSecondaryContainer: Color(0xffffddb8),
    tertiary: Color(0xffd7c686),
    onTertiary: Color(0xff393005),
    tertiaryContainer: Color(0xff51461a),
    onTertiaryContainer: Color(0xfff4e29b),
    error: Color(0xffffb4ab),
    onError: Color(0xff690005),
    errorContainer: Color(0xff93000a),
    onErrorContainer: Color(0xffffdad6),
    surface: Color(0xff171813),
    onSurface: Color(0xffe6e3d8),
    onSurfaceVariant: Color(0xffc7c3b7),
    outline: Color(0xff928f84),
    outlineVariant: Color(0xff47483f),
    shadow: Color(0xff000000),
    scrim: Color(0xff000000),
    inverseSurface: Color(0xffe6e3d8),
    onInverseSurface: Color(0xff2c2d27),
    inversePrimary: Color(0xff50653e),
    surfaceTint: Color(0xffb8cea1),
    surfaceDim: Color(0xff171813),
    surfaceBright: Color(0xff3a3b34),
    surfaceContainerLowest: Color(0xff11120d),
    surfaceContainerLow: Color(0xff1d1e19),
    surfaceContainer: Color(0xff21221d),
    surfaceContainerHigh: Color(0xff2b2c27),
    surfaceContainerHighest: Color(0xff363731),
  );
}
