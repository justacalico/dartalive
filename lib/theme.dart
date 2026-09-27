import 'package:flutter/material.dart';

/// NLE-grade dark theme: dense, flat, near-black panels with hairline
/// separators and a warm accent. Not stock Material.
class AppTheme {
  static const bg = Color(0xff141417);
  static const panel = Color(0xff1c1c20);
  static const panelAlt = Color(0xff202027);
  static const header = Color(0xff17171b);
  static const border = Color(0xff2c2c33);
  static const text = Color(0xffd8d8de);
  static const textDim = Color(0xff8b8b96);
  static const accent = Color(0xffe8b32c);
  static const videoClip = Color(0xff4a7fb5);
  static const audioClip = Color(0xff3f8f63);
  static const danger = Color(0xffd05050);

  static ThemeData build({Color? accentColor}) {
    final acc = accentColor ?? accent;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.dark(
        surface: panel,
        primary: acc,
        onPrimary: Colors.black,
        secondary: acc,
      ),
      dividerColor: border,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: text, fontSize: 12.5),
        bodySmall: TextStyle(color: textDim, fontSize: 11.5),
        titleSmall: TextStyle(
            color: text, fontSize: 12, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: textDim, fontSize: 10.5),
      ),
      iconTheme: const IconThemeData(color: textDim, size: 16),
      sliderTheme: const SliderThemeData(
        trackHeight: 2,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xff3a3a44)),
        thickness: WidgetStateProperty.all(8),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xff2a2a30),
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: text, fontSize: 11),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Color(0xff232329),
        textStyle: TextStyle(color: text, fontSize: 12.5),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xff1e1e23),
        titleTextStyle: TextStyle(
            color: text, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Color(0xff141418),
        border: OutlineInputBorder(
            borderSide: BorderSide(color: border),
            borderRadius: BorderRadius.all(Radius.circular(4))),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        labelStyle: TextStyle(color: textDim, fontSize: 11.5),
      ),
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}
