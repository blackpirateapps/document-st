import 'package:flutter/cupertino.dart';

/// Cupertino dark theme matching the web app's design tokens.
class AppTheme {
  AppTheme._();

  // ── Colors ──
  static const Color bgPrimary = Color(0xFF000000);
  static const Color bgSecondary = Color(0xFF1C1C1E);
  static const Color bgTertiary = Color(0xFF2C2C2E);
  static const Color bgElevated = Color(0xFF2C2C2E);

  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0x99EBEBF5); // 60%
  static const Color textTertiary = Color(0x4DEBEBF5); // 30%

  static const Color separator = Color(0xA654545F); // ~65%
  static const Color borderColor = Color(0x14FFFFFF); // 8%

  static const Color accentBlue = Color(0xFF0A84FF);
  static const Color accentBlueHover = Color(0xFF409CFF);
  static const Color accentBlueDim = Color(0x260A84FF);
  static const Color dangerRed = Color(0xFFFF453A);
  static const Color systemOrange = Color(0xFFFF9F0A);
  static const Color systemGreen = Color(0xFF30D158);

  static const Color fillTertiary = Color(0x3D78788A); // 24%
  static const Color fillQuaternary = Color(0x2E78788A); // 18%

  // ── Cupertino Theme ──
  static CupertinoThemeData get darkTheme {
    return const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: accentBlue,
      scaffoldBackgroundColor: bgPrimary,
      barBackgroundColor: Color(0xD91C1C1E),
      textTheme: CupertinoTextThemeData(
        primaryColor: accentBlue,
        textStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 17,
          letterSpacing: -0.4,
          color: textPrimary,
        ),
        navTitleTextStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: textPrimary,
        ),
        navLargeTitleTextStyle: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: textPrimary,
        ),
      ),
    );
  }
}
