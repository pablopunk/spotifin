import 'package:flutter/material.dart';

abstract final class SpotifinColors {
  static const voidBlack = Color(0xFF0B0D12);
  static const background = Color(0xFF111319);
  static const surface = Color(0xFF181B22);
  static const interactive = Color(0xFF20232C);
  static const raised = Color(0xFF292D38);
  static const hover = Color(0xFF303541);
  static const border = Color(0xFF454B59);
  static const borderStrong = Color(0xFF71798A);
  static const accent = Color(0xFF39F4D1);
  static const brandBlue = Color(0xFF33BFFF);
  static const brandViolet = Color(0xFF9B68FF);
  static const text = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFB8BECA);
  static const negative = Color(0xFFF3727F);
  static const warning = Color(0xFFFFA42B);
  static const announcement = Color(0xFF539DF5);
}

abstract final class SpotifinGradients {
  static const brand = LinearGradient(
    colors: [
      SpotifinColors.accent,
      SpotifinColors.brandBlue,
      SpotifinColors.brandViolet,
    ],
  );
}

abstract final class SpotifinRadii {
  static const small = 4.0;
  static const card = 8.0;
  static const panel = 12.0;
  static const pill = 999.0;
}

abstract final class SpotifinShadows {
  static const elevated = BoxShadow(
    color: Color(0x4D000000),
    offset: Offset(0, 8),
    blurRadius: 8,
  );
  static const dialog = BoxShadow(
    color: Color(0x80000000),
    offset: Offset(0, 8),
    blurRadius: 24,
  );
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: SpotifinColors.accent,
    onPrimary: Colors.black,
    primaryContainer: SpotifinColors.interactive,
    onPrimaryContainer: SpotifinColors.text,
    secondary: SpotifinColors.text,
    onSecondary: Colors.black,
    surface: SpotifinColors.surface,
    onSurface: SpotifinColors.text,
    error: SpotifinColors.negative,
    onError: Colors.black,
    outline: SpotifinColors.border,
    outlineVariant: Color(0xFF303030),
  );
  const textTheme = TextTheme(
    headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
    headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: SpotifinColors.textMuted,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: .14,
    ),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
  );
  final pill = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(SpotifinRadii.pill),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: SpotifinColors.background,
    canvasColor: SpotifinColors.background,
    fontFamily: 'Manrope',
    fontFamilyFallback: const [
      'Helvetica Neue',
      'Helvetica',
      'Arial',
      'sans-serif',
    ],
    textTheme: textTheme,
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    focusColor: const Color(0x6639F4D1),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: SpotifinColors.background,
      foregroundColor: SpotifinColors.text,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: SpotifinColors.text,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(
      color: SpotifinColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(SpotifinRadii.card)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: SpotifinColors.textMuted,
      textColor: SpotifinColors.text,
      titleTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      subtitleTextStyle: TextStyle(
        fontSize: 12,
        color: SpotifinColors.textMuted,
      ),
      minTileHeight: 64,
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(SpotifinRadii.small)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SpotifinColors.accent,
        foregroundColor: Colors.black,
        disabledBackgroundColor: SpotifinColors.border,
        disabledForegroundColor: SpotifinColors.textMuted,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: textTheme.labelLarge,
        shape: pill,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SpotifinColors.text,
        minimumSize: const Size(48, 44),
        side: const BorderSide(color: SpotifinColors.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        textStyle: textTheme.labelLarge,
        shape: pill,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SpotifinColors.text,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: textTheme.labelLarge,
        shape: pill,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: SpotifinColors.textMuted,
        hoverColor: SpotifinColors.hover,
        highlightColor: SpotifinColors.interactive,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SpotifinColors.interactive,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      labelStyle: const TextStyle(color: SpotifinColors.textMuted),
      hintStyle: const TextStyle(color: SpotifinColors.textMuted),
      prefixIconColor: SpotifinColors.textMuted,
      suffixIconColor: SpotifinColors.textMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SpotifinRadii.pill),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SpotifinRadii.pill),
        borderSide: const BorderSide(color: SpotifinColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SpotifinRadii.pill),
        borderSide: const BorderSide(color: SpotifinColors.text, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SpotifinRadii.pill),
        borderSide: const BorderSide(color: SpotifinColors.negative),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: const WidgetStatePropertyAll(SpotifinColors.interactive),
      hintStyle: const WidgetStatePropertyAll(
        TextStyle(color: SpotifinColors.textMuted),
      ),
      elevation: const WidgetStatePropertyAll(0),
      side: const WidgetStatePropertyAll(
        BorderSide(color: SpotifinColors.border),
      ),
      shape: WidgetStatePropertyAll(pill),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.black,
      indicatorColor: SpotifinColors.interactive,
      height: 72,
      elevation: 8,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? SpotifinColors.text
              : SpotifinColors.textMuted,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? SpotifinColors.text
              : SpotifinColors.textMuted,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.black,
      indicatorColor: SpotifinColors.interactive,
      selectedIconTheme: IconThemeData(color: SpotifinColors.text),
      unselectedIconTheme: IconThemeData(color: SpotifinColors.textMuted),
      selectedLabelTextStyle: TextStyle(
        color: SpotifinColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: SpotifinColors.textMuted,
        fontSize: 14,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorColor: SpotifinColors.accent,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: SpotifinColors.text,
      unselectedLabelColor: SpotifinColors.textMuted,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 14),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: SpotifinColors.text,
      inactiveTrackColor: SpotifinColors.border,
      thumbColor: SpotifinColors.text,
      overlayColor: Color(0x3339F4D1),
      trackHeight: 4,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF303030),
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SpotifinColors.accent,
      linearTrackColor: SpotifinColors.border,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? SpotifinColors.accent
            : SpotifinColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? SpotifinColors.accent.withValues(alpha: .35)
            : SpotifinColors.border,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? SpotifinColors.accent
            : SpotifinColors.textMuted,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: SpotifinColors.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(SpotifinRadii.panel)),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: SpotifinColors.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(SpotifinRadii.card)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: SpotifinColors.surface,
      modalBackgroundColor: SpotifinColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: SpotifinColors.text,
      contentTextStyle: TextStyle(color: Colors.black),
      behavior: SnackBarBehavior.floating,
      shape: StadiumBorder(),
    ),
  );
}
