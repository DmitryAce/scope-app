import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Палитра веб-версии Scope: тёмная тема, фиолетовый акцент, бордовый логотип.
class C {
  static const bg = Color(0xFF0D0D12);
  static const bg2 = Color(0xFF13131A);
  static const bg3 = Color(0xFF1A1A24);
  static const elevated = Color(0xFF21212E);
  static const border = Color(0xFF2A2A3C);
  static const borderLight = Color(0xFF1F1F2E);

  static const text = Color(0xFFF4F4F6);
  static const text2 = Color(0xFF9090A0);
  static const muted = Color(0xFF5C5C6D);

  // Акцент выбирается в настройках, поэтому не const: см. [Accent] и [C.apply].
  static Color accent = accents.first.main;
  static Color accent2 = accents.first.soft;
  static Color onAccent = accents.first.on;
  static String accentId = accents.first.id;

  static void apply(String id) {
    final a = accents.firstWhere((x) => x.id == id, orElse: () => accents.first);
    accent = a.main;
    accent2 = a.soft;
    onAccent = a.on;
    accentId = a.id;
  }
  static const logo = Color(0xFF8B2942);
  static const logoDark = Color(0xFF6B1D32);

  static const low = Color(0xFF22C55E);
  static const medium = Color(0xFF3B82F6);
  static const high = Color(0xFFF59E0B);
  static const urgent = Color(0xFFEF4444);

  static Color priority(int p) => switch (p) {
        1 => low,
        3 => high,
        4 => urgent,
        _ => medium,
      };

  static const projectPalette = [
    Color(0xFF7C3AED),
    Color(0xFF8B2942),
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF64748B),
  ];
}

/// Акцентный цвет: [main] — кнопки и заливки, [soft] — текст и иконки на тёмном,
/// [on] — то, что лежит поверх [main].
class Accent {
  const Accent(this.id, this.name, this.main, this.soft, this.on);

  final String id;
  final String name;
  final Color main;
  final Color soft;
  final Color on;
}

const accents = [
  Accent('graphite', 'Графит', Color(0xFFE6E6EC), Color(0xFFE6E6EC), Color(0xFF111116)),
  Accent('wine', 'Бордо', Color(0xFFB3365B), Color(0xFFE38AA4), Colors.white),
  Accent('blue', 'Синий', Color(0xFF3D7BF0), Color(0xFF8DB4FF), Colors.white),
  Accent('mint', 'Мята', Color(0xFF34C083), Color(0xFF7FE0B4), Color(0xFF07170F)),
  Accent('amber', 'Янтарь', Color(0xFFEFA83C), Color(0xFFFFCB78), Color(0xFF1C1305)),
  Accent('lilac', 'Сирень', Color(0xFF8F84E8), Color(0xFFBDB6FF), Colors.white),
];

String hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

ThemeData buildTheme() {
  const font = 'Manrope';
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: font,
    colorScheme: ColorScheme.dark(
      primary: C.accent,
      onPrimary: C.onAccent,
      secondary: C.accent2,
      surface: C.bg2,
      onSurface: C.text,
      error: C.urgent,
      surfaceContainerHighest: C.bg3,
      outline: C.border,
    ),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text, fontFamily: font),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(fontFamily: font, fontSize: 20, fontWeight: FontWeight.w700, color: C.text),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      // На широком экране шторки не растягиваются на всё окно.
      constraints: BoxConstraints(maxWidth: 620),
      backgroundColor: C.bg2,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: C.muted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: C.bg2,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.elevated,
      contentTextStyle: TextStyle(fontFamily: font, color: C.text),
      actionTextColor: C.accent2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.bg3,
      hintStyle: const TextStyle(color: C.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: C.accent, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerTheme: const DividerThemeData(color: C.borderLight, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.bg2,
      surfaceTintColor: Colors.transparent,
      indicatorColor: C.accent.withValues(alpha: 0.22),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: font,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? C.text : C.text2,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? C.accent2 : C.text2)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: C.accent,
      foregroundColor: C.onAccent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: C.elevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: C.bg2,
      surfaceTintColor: Colors.transparent,
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: C.bg2,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: C.bg3,
      side: const BorderSide(color: C.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(fontFamily: font, color: C.text, fontWeight: FontWeight.w600),
      // Подпись выбранного чипа лежит на акценте — у светлого «Графита» она тёмная.
      secondaryLabelStyle: TextStyle(fontFamily: font, color: C.onAccent, fontWeight: FontWeight.w700),
    ),
  );
}
