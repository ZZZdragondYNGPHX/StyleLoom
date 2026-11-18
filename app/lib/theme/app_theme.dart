import 'package:material_ui/material_ui.dart';

/// 方案 A「织机画册 · Warm Gallery Editorial」语义色板扩展
class EditorialColors extends ThemeExtension<EditorialColors> {
  const EditorialColors({
    required this.isNight,
    required this.bg,
    required this.bgGlow,
    required this.surface,
    required this.surfaceGlass,
    required this.surfaceHover,
    required this.trough,
    required this.troughDeep,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.hairline,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.celadon,
    required this.celadonSoft,
    required this.warn,
    required this.warnSoft,
    required this.museumBg,
    required this.shadowColor,
  });

  final bool isNight;
  final Color bg;
  final Color bgGlow;
  final Color surface;
  final Color surfaceGlass;
  final Color surfaceHover;
  final Color trough;
  final Color troughDeep;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color hairline;
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color celadon;
  final Color celadonSoft;
  final Color warn;
  final Color warnSoft;
  final Color museumBg;
  final Color shadowColor;

  /// 日间暖砂宣纸调
  static const EditorialColors day = EditorialColors(
    isNight: false,
    bg: Color(0xFFF6F3EC),
    bgGlow: Color(0x29D4B892),
    surface: Color(0xFFFFFEFA),
    surfaceGlass: Color(0xCCFFFEFA),
    surfaceHover: Color(0xFFFFFFFF),
    trough: Color(0xFFEFEAE0),
    troughDeep: Color(0xFFE5DEC9),
    ink: Color(0xFF1C1A17),
    muted: Color(0xFF78736A),
    faint: Color(0x0F1C1A17),
    hairline: Color(0x141C1A17),
    accent: Color(0xFFC45630),
    accentHover: Color(0xFFAE4723),
    accentSoft: Color(0x1CC45630),
    celadon: Color(0xFF2B6E5B),
    celadonSoft: Color(0x1F2B6E5B),
    warn: Color(0xFFB8601C),
    warnSoft: Color(0x21B8601C),
    museumBg: Color(0xFF161412),
    shadowColor: Color(0xFF1C1A17),
  );

  /// 夜间暖炭夜读调
  static const EditorialColors night = EditorialColors(
    isNight: true,
    bg: Color(0xFF171614),
    bgGlow: Color(0x12C45630),
    surface: Color(0xFF211F1C),
    surfaceGlass: Color(0xD1211F1C),
    surfaceHover: Color(0xFF292622),
    trough: Color(0xFF2B2823),
    troughDeep: Color(0xFF37332C),
    ink: Color(0xFFF3EFE7),
    muted: Color(0xFF9D9589),
    faint: Color(0x12F3EFE7),
    hairline: Color(0x1AF3EFE7),
    accent: Color(0xFFE0734B),
    accentHover: Color(0xFFEC845D),
    accentSoft: Color(0x29E0734B),
    celadon: Color(0xFF4DB699),
    celadonSoft: Color(0x294DB699),
    warn: Color(0xFFE8964A),
    warnSoft: Color(0x2EE8964A),
    museumBg: Color(0xFF100F0D),
    shadowColor: Color(0xFF000000),
  );

  /// 安全获取扩展色板（单测若运行于裸 MaterialApp 时自动回落到日间宣纸调）
  static EditorialColors of(BuildContext context) {
    return Theme.of(context).extension<EditorialColors>() ?? day;
  }

  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isNight ? 0.34 : 0.06),
      blurRadius: isNight ? 36 : 28,
      offset: const Offset(0, 12),
    ),
  ];

  List<BoxShadow> get cardHoverShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isNight ? 0.46 : 0.11),
      blurRadius: isNight ? 48 : 40,
      offset: const Offset(0, 18),
    ),
  ];

  List<BoxShadow> get pillDockShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isNight ? 0.36 : 0.08),
      blurRadius: 30,
      offset: const Offset(0, 10),
    ),
  ];

  List<BoxShadow> get modalShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isNight ? 0.62 : 0.18),
      blurRadius: 72,
      offset: const Offset(0, 28),
    ),
  ];

  @override
  EditorialColors copyWith({
    bool? isNight,
    Color? bg,
    Color? bgGlow,
    Color? surface,
    Color? surfaceGlass,
    Color? surfaceHover,
    Color? trough,
    Color? troughDeep,
    Color? ink,
    Color? muted,
    Color? faint,
    Color? hairline,
    Color? accent,
    Color? accentHover,
    Color? accentSoft,
    Color? celadon,
    Color? celadonSoft,
    Color? warn,
    Color? warnSoft,
    Color? museumBg,
    Color? shadowColor,
  }) {
    return EditorialColors(
      isNight: isNight ?? this.isNight,
      bg: bg ?? this.bg,
      bgGlow: bgGlow ?? this.bgGlow,
      surface: surface ?? this.surface,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      trough: trough ?? this.trough,
      troughDeep: troughDeep ?? this.troughDeep,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      hairline: hairline ?? this.hairline,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentSoft: accentSoft ?? this.accentSoft,
      celadon: celadon ?? this.celadon,
      celadonSoft: celadonSoft ?? this.celadonSoft,
      warn: warn ?? this.warn,
      warnSoft: warnSoft ?? this.warnSoft,
      museumBg: museumBg ?? this.museumBg,
      shadowColor: shadowColor ?? this.shadowColor,
    );
  }

  @override
  EditorialColors lerp(ThemeExtension<EditorialColors>? other, double t) {
    if (other is! EditorialColors) return this;
    return EditorialColors(
      isNight: t < 0.5 ? isNight : other.isNight,
      bg: Color.lerp(bg, other.bg, t) ?? bg,
      bgGlow: Color.lerp(bgGlow, other.bgGlow, t) ?? bgGlow,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceGlass: Color.lerp(surfaceGlass, other.surfaceGlass, t) ?? surfaceGlass,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t) ?? surfaceHover,
      trough: Color.lerp(trough, other.trough, t) ?? trough,
      troughDeep: Color.lerp(troughDeep, other.troughDeep, t) ?? troughDeep,
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      faint: Color.lerp(faint, other.faint, t) ?? faint,
      hairline: Color.lerp(hairline, other.hairline, t) ?? hairline,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentHover: Color.lerp(accentHover, other.accentHover, t) ?? accentHover,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t) ?? accentSoft,
      celadon: Color.lerp(celadon, other.celadon, t) ?? celadon,
      celadonSoft: Color.lerp(celadonSoft, other.celadonSoft, t) ?? celadonSoft,
      warn: Color.lerp(warn, other.warn, t) ?? warn,
      warnSoft: Color.lerp(warnSoft, other.warnSoft, t) ?? warnSoft,
      museumBg: Color.lerp(museumBg, other.museumBg, t) ?? museumBg,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t) ?? shadowColor,
    );
  }
}

class StyleLoomTheme {
  static const List<String> _serifFallback = [
    'Songti SC',
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'Source Han Serif CN',
    'SimSun',
    'serif',
  ];

  static const List<String> _monoFallback = [
    'SFMono-Regular',
    'Consolas',
    'Liberation Mono',
    'Menlo',
    'monospace',
  ];

  /// 衬线体排版样式（画册标题、品牌字标、平台丝带）
  static TextStyle serifStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Georgia',
      fontFamilyFallback: _serifFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// 等宽表格数字排版样式
  static TextStyle monoStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'SFMono-Regular',
      fontFamilyFallback: _monoFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData light() => _build(EditorialColors.day, Brightness.light);

  static ThemeData night() => _build(EditorialColors.night, Brightness.dark);

  static ThemeData _build(EditorialColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      surface: c.surface,
    ).copyWith(
      primary: c.accent,
      onPrimary: const Color(0xFFFFFEFA),
      secondary: c.celadon,
      onSecondary: const Color(0xFFFFFEFA),
      surface: c.surface,
      onSurface: c.ink,
      surfaceContainerHighest: c.trough,
      outlineVariant: c.hairline,
      error: c.accent,
    );

    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c.accent, width: 1.5),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      extensions: [c],
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: c.ink,
        displayColor: c.ink,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.hairline),
        ),
        titleTextStyle: serifStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.trough,
        isDense: true,
        hintStyle: TextStyle(color: c.muted, fontSize: 13),
        labelStyle: TextStyle(color: c.muted, fontSize: 13),
        border: baseBorder,
        enabledBorder: baseBorder,
        focusedBorder: focusedBorder,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: const Color(0xFFFFFEFA),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.trough,
          side: BorderSide.none,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.trough,
        selectedColor: c.accentSoft,
        side: BorderSide.none,
        labelStyle: TextStyle(fontSize: 12, color: c.ink),
        shape: const StadiumBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        elevation: 8,
        shadowColor: c.shadowColor.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: TextStyle(color: c.bg, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
