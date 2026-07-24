import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_flavor.dart';
import 'collector_design_system.dart';
import 'household_design_system.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  static const _storageKey = 'binlink_theme_mode';

  ThemeMode get themeMode => _themeMode;
  bool get isDark => HouseholdColors.isDark;

  /// HouseholdColors getters are static, so the palette flag must be flipped
  /// before the tree rebuilds.
  void _applyPalette() {
    final dark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        PlatformDispatcher.instance.platformBrightness == Brightness.dark,
    };
    HouseholdColors.isDark = dark;
    CollectorColors.isDark = dark;
    // Status-bar icons must invert with the theme.
    SystemChrome.setSystemUIOverlayStyle(
      dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );
  }

  Future<void> toggleTheme() async {
    await setThemeMode(
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _applyPalette();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, mode.name);
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    _themeMode = switch (stored) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      // No saved preference: collector keeps its classic green-on-black look,
      // household starts green-on-white.
      _ => FlavorConfig.isCollector ? ThemeMode.dark : ThemeMode.light,
    };
    _applyPalette();
    notifyListeners();
  }
}
