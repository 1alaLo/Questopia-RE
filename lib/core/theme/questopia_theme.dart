import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../helpers/platform_helper.dart';

abstract final class QuestopiaTheme {
  // The app intentionally ships without a bundled typeface: no font files are
  // declared in pubspec.yaml, so naming one here would only fall back to the
  // platform default. The in-game text is the only surface with a font choice,
  // and it resolves through [fontFamilyFor].

  /// Lower and upper bounds applied to the in-game font size setting.
  static const double minGameFontSize = 12.0;
  static const double maxGameFontSize = 28.0;

  /// In-game typeface options resolved to real font families per platform.
  ///
  /// Index 0 means "Default system" and resolves to null so the renderer keeps
  /// the platform default font. The remaining entries line up with the labels
  /// exposed by `SettingsPickerSheets.typefaceNames`.
  // Android ships these as system families, so naming one is enough: the
  // platform font manager resolves it without a bundled font file. The list
  // obeys the same two rules as the desktop one below: every name must exist,
  // and no family may appear twice.
  static const List<String> _androidFontFamilies = <String>[
    '', // 0 - Default system
    'sans-serif', // 1 - Sans-serif
    'serif', // 2 - Serif
    'monospace', // 3 - Monospace
    'sans-serif-medium', // 4 - Medium
    'cursive', // 5 - Cursive
    'sans-serif-light', // 6 - Light
    'sans-serif-condensed', // 7 - Condensed
    'sans-serif-black', // 8 - Black
    'sans-serif-thin', // 9 - Thin
    'casual', // 10 - Casual
    'serif-monospace', // 11 - Serif monospace
  ];

  // iOS has no "sans-serif"/"monospace" aliases: naming one of the Android
  // families there silently falls back to the system font, so the typeface
  // picker looked broken. These are real families shipped with iOS/iPadOS.
  static const List<String> _iosFontFamilies = <String>[
    '', // 0 - Default system
    'Helvetica Neue', // 1 - Sans-serif
    'Georgia', // 2 - Serif
    'Menlo', // 3 - Monospace
    'Avenir Next', // 4 - Medium
    'Snell Roundhand', // 5 - Cursive
    'Optima', // 6 - Light
    'Futura', // 7 - Condensed
    'Copperplate', // 8 - Black
    'Gill Sans', // 9 - Thin
    'Marker Felt', // 10 - Casual
    'Courier New', // 11 - Serif monospace
  ];

  // Every entry must be a real, DISTINCT family name. Flutter resolves
  // `fontFamily` by family, not by face, so naming a face ("Segoe UI Semibold")
  // silently renders as the parent family and the choice looks broken. Families
  // are also duplicated nowhere: two slots pointing at one family make one of
  // the two options a no-op. Both mistakes were present here before.
  static const List<String> _desktopFontFamilies = <String>[
    '', // 0 - Default system
    'Segoe UI', // 1 - Sans-serif
    'Georgia', // 2 - Serif
    'Consolas', // 3 - Monospace
    'Calibri', // 4 - Medium
    'Segoe Script', // 5 - Cursive
    'Candara', // 6 - Light
    'Bahnschrift', // 7 - Condensed
    'Impact', // 8 - Black
    'Corbel', // 9 - Thin
    'Comic Sans MS', // 10 - Casual
    'Courier New', // 11 - Serif monospace
  ];

  /// Resolves the in-game typeface index to a platform font family.
  ///
  /// Returns null for index 0 and any out-of-range index so the game text
  /// falls back to the platform default font.
  static String? fontFamilyFor(int index) {
    final families = isDesktopPlatform
        ? _desktopFontFamilies
        : defaultTargetPlatform == TargetPlatform.iOS
            ? _iosFontFamilies
            : _androidFontFamilies;
    if (index <= 0 || index >= families.length) return null;
    return families[index];
  }

  /// Accent seeds for the legacy "Color Accent" preference.
  static const Map<String, Color> _accentSeeds = {
    'blue': Color(0xFF0061A4),
    'green': Color(0xFF2E6C38),
    'orange': Color(0xFF924C00),
    'purple': Color(0xFF77539D),
    'pink': Color(0xFF9B4061),
    'teal': Color(0xFF006A6A),
    'amber': Color(0xFFFBBD00),
    'monochrome': Color(0xFF757575),
  };

  static Color seedFor(String accent, Brightness brightness) {
    if (accent == 'dynamic' && brightness == Brightness.light) {
      return const Color(0xff4d5f9f);
    }
    if (accent == 'dynamic') {
      return const Color(0xffbbc6ff);
    }
    return _accentSeeds[accent] ??
        (brightness == Brightness.light
            ? const Color(0xff4d5f9f)
            : const Color(0xffbbc6ff));
  }

  static ThemeData light(
      {String accent = 'dynamic', ColorScheme? dynamicScheme}) {
    if (accent == 'monochrome') {
      return _themeWithScheme(
          Brightness.light, _monochromeScheme(Brightness.light));
    }
    return _theme(
      Brightness.light,
      seedFor(accent, Brightness.light),
      dynamicScheme: accent == 'dynamic' ? dynamicScheme : null,
    );
  }

  static ThemeData dark({
    String accent = 'dynamic',
    bool amoled = false,
    ColorScheme? dynamicScheme,
  }) {
    final surf = amoled ? Colors.black : null;
    if (accent == 'monochrome') {
      return _themeWithScheme(
          Brightness.dark, _monochromeScheme(Brightness.dark, surface: surf));
    }
    return _theme(
      Brightness.dark,
      seedFor(accent, Brightness.dark),
      surface: surf,
      dynamicScheme: accent == 'dynamic' ? dynamicScheme : null,
    );
  }

  /// Pure 100% grayscale monochrome color scheme (zero saturation across all roles).
  static ColorScheme _monochromeScheme(Brightness brightness,
      {Color? surface}) {
    if (brightness == Brightness.light) {
      return ColorScheme(
        brightness: Brightness.light,
        primary: const Color(0xFF1F1F1F),
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFE0E0E0),
        onPrimaryContainer: const Color(0xFF1F1F1F),
        secondary: const Color(0xFF424242),
        onSecondary: const Color(0xFFFFFFFF),
        secondaryContainer: const Color(0xFFE0E0E0),
        onSecondaryContainer: const Color(0xFF1F1F1F),
        tertiary: const Color(0xFF616161),
        onTertiary: const Color(0xFFFFFFFF),
        tertiaryContainer: const Color(0xFFEEEEEE),
        onTertiaryContainer: const Color(0xFF212121),
        error: const Color(0xFFB3261E),
        onError: const Color(0xFFFFFFFF),
        errorContainer: const Color(0xFFF9DEDC),
        onErrorContainer: const Color(0xFF410E0B),
        surface: surface ?? const Color(0xFFF8F8F8),
        onSurface: const Color(0xFF1F1F1F),
        onSurfaceVariant: const Color(0xFF616161),
        outline: const Color(0xFF888888),
        outlineVariant: const Color(0xFFD6D6D6),
        shadow: const Color(0xFF000000),
        scrim: const Color(0xFF000000),
        inverseSurface: const Color(0xFF303030),
        onInverseSurface: const Color(0xFFF0F0F0),
        inversePrimary: const Color(0xFFD0D0D0),
        surfaceContainerLowest: surface ?? const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF3F3F3),
        surfaceContainer: const Color(0xFFEFEFEF),
        surfaceContainerHigh: const Color(0xFFE8E8E8),
        surfaceContainerHighest: const Color(0xFFE0E0E0),
      );
    } else {
      final isBlack = surface == Colors.black;
      final baseSurface = surface ?? const Color(0xFF121212);
      return ColorScheme(
        brightness: Brightness.dark,
        primary: const Color(0xFFE2E2E2),
        onPrimary: const Color(0xFF181818),
        primaryContainer: const Color(0xFF383838),
        onPrimaryContainer: const Color(0xFFE2E2E2),
        secondary: const Color(0xFFCCCCCC),
        onSecondary: const Color(0xFF222222),
        secondaryContainer: const Color(0xFF333333),
        onSecondaryContainer: const Color(0xFFE2E2E2),
        tertiary: const Color(0xFFAAAAAA),
        onTertiary: const Color(0xFF1E1E1E),
        tertiaryContainer: const Color(0xFF2C2C2C),
        onTertiaryContainer: const Color(0xFFE0E0E0),
        error: const Color(0xFFF2B8B5),
        onError: const Color(0xFF601410),
        errorContainer: const Color(0xFF8C1D18),
        onErrorContainer: const Color(0xFFF9DEDC),
        surface: baseSurface,
        onSurface: const Color(0xFFE2E2E2),
        onSurfaceVariant: const Color(0xFFCCCCCC),
        outline: const Color(0xFF888888),
        outlineVariant: const Color(0xFF444444),
        shadow: const Color(0xFF000000),
        scrim: const Color(0xFF000000),
        inverseSurface: const Color(0xFFE2E2E2),
        onInverseSurface: const Color(0xFF222222),
        inversePrimary: const Color(0xFF757575),
        surfaceContainerLowest:
            isBlack ? Colors.black : const Color(0xFF0C0C0C),
        surfaceContainerLow:
            isBlack ? const Color(0xFF121212) : const Color(0xFF161618),
        surfaceContainer:
            isBlack ? const Color(0xFF181818) : const Color(0xFF1C1C1E),
        surfaceContainerHigh:
            isBlack ? const Color(0xFF222222) : const Color(0xFF242426),
        surfaceContainerHighest:
            isBlack ? const Color(0xFF2C2C2C) : const Color(0xFF2E2E30),
      );
    }
  }

  /// Single Source of Truth slider theme for every M3E slider in the app.
  ///
  /// The stock M3E slider narrows its handle from 4px to 2px while pressed,
  /// which on a desktop pointer reads as the handle collapsing under the
  /// cursor instead of a deliberate press cue. Pinning the pressed width to the
  /// resting width keeps the handle steady while dragging.
  static final M3ESliderTheme sliderTheme =
      M3ESliderTheme.defaults.copyWith(
    pressedHandleWidth: 4,
  );

  /// Builds the M3E theme data every M3ETheme host in the app shares, so the
  /// color scheme bridge and the slider overrides cannot drift apart between
  /// screens.
  static M3EThemeData m3eThemeDataFrom(ThemeData theme) {
    return M3EThemeData(
      colorScheme: m3eColorSchemeFrom(theme.colorScheme),
      sliderTheme: sliderTheme,
    );
  }

  /// Single Source of Truth helper converting Flutter's [ColorScheme] into [M3EColorScheme].
  static M3EColorScheme m3eColorSchemeFrom(ColorScheme scheme) {
    return M3EColorScheme(
      brightness: scheme.brightness == Brightness.dark
          ? Brightness.dark
          : Brightness.light,
      primary: scheme.primary,
      onPrimary: scheme.onPrimary,
      primaryContainer: scheme.primaryContainer,
      onPrimaryContainer: scheme.onPrimaryContainer,
      secondary: scheme.secondary,
      onSecondary: scheme.onSecondary,
      secondaryContainer: scheme.secondaryContainer,
      onSecondaryContainer: scheme.onSecondaryContainer,
      tertiary: scheme.tertiary,
      onTertiary: scheme.onTertiary,
      tertiaryContainer: scheme.tertiaryContainer,
      onTertiaryContainer: scheme.onTertiaryContainer,
      error: scheme.error,
      onError: scheme.onError,
      errorContainer: scheme.errorContainer,
      onErrorContainer: scheme.onErrorContainer,
      surface: scheme.surface,
      onSurface: scheme.onSurface,
      onSurfaceVariant: scheme.onSurfaceVariant,
      surfaceContainerLowest: scheme.surfaceContainerLowest,
      surfaceContainerLow: scheme.surfaceContainerLow,
      surfaceContainer: scheme.surfaceContainer,
      surfaceContainerHigh: scheme.surfaceContainerHigh,
      surfaceContainerHighest: scheme.surfaceContainerHighest,
      surfaceDim: scheme.surfaceDim,
      surfaceBright: scheme.surfaceBright,
      inverseSurface: scheme.inverseSurface,
      onInverseSurface: scheme.onInverseSurface,
      inversePrimary: scheme.inversePrimary,
      outline: scheme.outline,
      outlineVariant: scheme.outlineVariant,
      shadow: scheme.shadow,
      scrim: scheme.scrim,
      surfaceTint: scheme.surfaceTint,
      emphasis: scheme.primary,
      onEmphasis: scheme.onPrimary,
      info: scheme.primary,
      success: scheme.secondary,
      warning: scheme.tertiary,
      danger: scheme.error,
      surfaceStrong: scheme.surfaceContainerHighest,
      onSurfaceStrong: scheme.onSurface,
      outlineStrong: scheme.outline,
    );
  }

  static ThemeData _themeWithScheme(Brightness brightness, ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.onSecondaryContainer);
          }
          return IconThemeData(color: scheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          );
        }),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  static ThemeData _theme(
    Brightness brightness,
    Color seed, {
    Color? surface,
    ColorScheme? dynamicScheme,
  }) {
    final base = dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
          surface: surface,
        );

    final scheme = surface != null
        ? base.copyWith(surface: surface, surfaceContainerLowest: surface)
        : base;

    return _themeWithScheme(brightness, scheme);
  }
}
