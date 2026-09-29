import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

class AppTheme {
  const AppTheme._();

  /// System chrome for light screens (dark icons on the ivory background).
  static const SystemUiOverlayStyle lightOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  /// System chrome for immersive ink screens (onboarding, scanner).
  static const SystemUiOverlayStyle inkOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.ink,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: AppColors.goldInk,
      onPrimary: Colors.white,
      primaryContainer: AppColors.gold,
      onPrimaryContainer: AppColors.onGold,
      secondary: AppColors.inkSoft,
      onSecondary: Colors.white,
      surface: AppColors.background,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surfaceWarm,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.borderLight,
      error: AppColors.crimson,
      onError: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: _textTheme,
      primaryColor: AppColors.gold,

      // Consistent, non-jarring route transitions on every platform.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),

      cardTheme: const CardThemeData(
        color: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allLg,
          side: BorderSide(color: AppColors.borderLight),
        ),
        margin: EdgeInsets.zero,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: AppSpacing.xl,
        systemOverlayStyle: lightOverlay,
        iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
        titleTextStyle: AppTypography.sectionHeader,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        labelStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        floatingLabelStyle: AppTypography.caption.copyWith(
          color: AppColors.goldInk,
        ),
        errorStyle: AppTypography.captionSmall.copyWith(
          color: AppColors.crimson,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.base,
        ),
        border: _inputBorder(AppColors.borderLight),
        enabledBorder: _inputBorder(AppColors.border),
        focusedBorder: _inputBorder(AppColors.goldInk, width: 1.6),
        errorBorder: _inputBorder(AppColors.crimson),
        focusedErrorBorder: _inputBorder(AppColors.crimson, width: 1.6),
        disabledBorder: _inputBorder(AppColors.borderLight),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.goldInk,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 0,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.borderLight,
        thickness: 1,
        space: 1,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTypography.titleSmall,
        unselectedLabelStyle: AppTypography.titleSmall.copyWith(
          fontWeight: FontWeight.w500,
        ),
        indicatorColor: AppColors.gold,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.borderLight,
        overlayColor: WidgetStatePropertyAll(
          AppColors.gold.withValues(alpha: 0.08),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.inkSoft,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: Colors.white,
        ),
        actionTextColor: AppColors.gold,
        elevation: 6,
        insetPadding: const EdgeInsets.all(AppSpacing.base),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allXl),
        titleTextStyle: AppTypography.sectionHeader,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),

      listTileTheme: ListTileThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
        titleTextStyle: AppTypography.bodyLarge,
        subtitleTextStyle: AppTypography.caption,
        iconColor: AppColors.textSecondary,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.goldInk
              : AppColors.border,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gold,
        linearTrackColor: AppColors.borderLight,
        circularTrackColor: AppColors.borderLight,
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.goldInk,
          textStyle: AppTypography.titleSmall,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.allSm),
          minimumSize: const Size(48, 44),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(style: premiumButtonStyle()),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(44, 44),
        ),
      ),

      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),

      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.inkSoft,
          borderRadius: AppRadius.allXs,
        ),
        textStyle: AppTypography.captionSmall.copyWith(color: Colors.white),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: AppRadius.allMd,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme get _textTheme => TextTheme(
    displayLarge: AppTypography.displayLarge,
    displayMedium: AppTypography.heroTitle,
    displaySmall: AppTypography.sectionHeader,
    headlineMedium: AppTypography.sectionHeader,
    headlineSmall: AppTypography.titleMedium,
    titleLarge: AppTypography.sectionHeader,
    titleMedium: AppTypography.titleMedium,
    titleSmall: AppTypography.titleSmall,
    bodyLarge: AppTypography.bodyLarge,
    bodyMedium: AppTypography.bodyMedium,
    bodySmall: AppTypography.caption,
    labelLarge: AppTypography.buttonText,
    labelMedium: AppTypography.caption,
    labelSmall: AppTypography.captionSmall,
  );

  /// Resting card elevation. Prefer [AppShadows] directly in new code.
  static List<BoxShadow> get premiumShadow => AppShadows.level1;

  /// Filled button style. Defaults to the gold surface with ink text — white on
  /// gold only reaches 2.1:1 contrast, so ink is used instead (8.1:1).
  static ButtonStyle premiumButtonStyle({
    Color? backgroundColor,
    Color? foregroundColor,
    BorderSide? side,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor ?? AppColors.gold,
      foregroundColor: foregroundColor ?? AppColors.onGold,
      disabledBackgroundColor: AppColors.border,
      disabledForegroundColor: AppColors.textSecondary,
      shadowColor: Colors.transparent,
      elevation: 0,
      textStyle: AppTypography.buttonText,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.base,
      ),
      minimumSize: const Size(0, 48),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
      side: side,
    );
  }
}
