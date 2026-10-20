import 'package:flutter/material.dart';

// The Morsel palette. Roles, rules and measured contrast are in docs/DESIGN.md.

/// The reserved health scale. Only food evaluations use these colours, and they
/// always appear with an icon and a word, never colour alone.
enum Evaluation {
  good('Good', Icons.check_circle),
  caution('Moderate', Icons.error),
  bad('Poor', Icons.cancel),
  unknown('Unknown', Icons.help);

  const Evaluation(this.label, this.icon);
  final String label;
  final IconData icon;
}

class MorselColors extends ThemeExtension<MorselColors> {
  const MorselColors({
    required this.good,
    required this.caution,
    required this.bad,
    required this.unknown,
    required this.inkMuted,
  });

  final Color good;
  final Color caution;
  final Color bad;
  final Color unknown;
  final Color inkMuted;

  static const light = MorselColors(
    good: Color(0xFF1F8A3B),
    caution: Color(0xFFB86E00),
    bad: Color(0xFFD23C32),
    unknown: Color(0xFF857E89),
    inkMuted: Color(0xFF6F6872),
  );
  static const dark = MorselColors(
    good: Color(0xFF5CCB7A),
    caution: Color(0xFFF0B44A),
    bad: Color(0xFFFF7B6E),
    unknown: Color(0xFF958D98),
    inkMuted: Color(0xFFA39AA3),
  );

  Color forEvaluation(Evaluation e) => switch (e) {
        Evaluation.good => good,
        Evaluation.caution => caution,
        Evaluation.bad => bad,
        Evaluation.unknown => unknown,
      };

  static MorselColors of(BuildContext context) =>
      Theme.of(context).extension<MorselColors>()!;

  @override
  MorselColors copyWith({Color? good, Color? caution, Color? bad, Color? unknown, Color? inkMuted}) =>
      MorselColors(
        good: good ?? this.good,
        caution: caution ?? this.caution,
        bad: bad ?? this.bad,
        unknown: unknown ?? this.unknown,
        inkMuted: inkMuted ?? this.inkMuted,
      );

  @override
  MorselColors lerp(MorselColors? other, double t) {
    if (other == null) return this;
    return MorselColors(
      good: Color.lerp(good, other.good, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      unknown: Color.lerp(unknown, other.unknown, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
    );
  }
}

/// Nutri-Score keeps its official fills; the letter colour is whichever of
/// white or ink measured above 3:1 on that fill.
const nutriScoreFills = {
  'a': Color(0xFF038141),
  'b': Color(0xFF85BB2F),
  'c': Color(0xFFFECB02),
  'd': Color(0xFFEE8100),
  'e': Color(0xFFE63E11),
};
const nutriScoreInk = {
  'a': Colors.white,
  'b': ink,
  'c': ink,
  'd': ink,
  'e': Colors.white,
};

const plum = Color(0xFF6A3D8F);
const ink = Color(0xFF1E1A1F);

ThemeData morselTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: plum,
    brightness: brightness,
    primary: light ? plum : const Color(0xFFCFAEEA),
    onPrimary: light ? Colors.white : const Color(0xFF34174A),
    surface: light ? const Color(0xFFFAF7F2) : const Color(0xFF141114),
    onSurface: light ? ink : const Color(0xFFEEE8EE),
    onSurfaceVariant: light ? const Color(0xFF5F5862) : const Color(0xFFBDB4BD),
    surfaceContainerLow: light ? Colors.white : const Color(0xFF1E1A1E),
    surfaceContainer: light ? const Color(0xFFF1ECE4) : const Color(0xFF272227),
    outlineVariant: light ? const Color(0xFFDDD5CA) : const Color(0xFF3B353B),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [light ? MorselColors.light : MorselColors.dark],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}

/// Tabular figures keep nutrient values aligned in columns.
const tabular = [FontFeature.tabularFigures()];
