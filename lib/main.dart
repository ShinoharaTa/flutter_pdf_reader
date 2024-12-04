import 'package:flutter/material.dart';
import 'screens/library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'store/settings_store.dart';

void main() {
  runApp(ProviderScope(child: MyApp()));
}

final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  useMaterial3: true, // Material 3 を有効化
  colorScheme: ColorScheme.fromSeed(
    seedColor: Color(0xFF1B4B72),
    primary: Color(0xFF1B4B72),
    secondary: Color(0xFF3498DB),
    surface: Colors.white,
    background: Color(0xFFF5F9FC),
    brightness: Brightness.light,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Color(0xFF1B4B72),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24), // より大きな角丸
      ),
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
  ),
  tabBarTheme: TabBarTheme(
    labelColor: Color(0xFF3498DB),
    unselectedLabelColor: Color(0xFF666666),
    labelStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    unselectedLabelStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
    ),
  ),
  listTileTheme: ListTileThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  sliderTheme: SliderThemeData(
    activeTrackColor: Color(0xFF3498DB),
    inactiveTrackColor: Color(0xFFE0E0E0),
    trackHeight: 10.0,
    trackShape: RoundedRectSliderTrackShape(),
    thumbColor: Colors.white,
    thumbShape: RoundSliderThumbShape(
      enabledThumbRadius: 12.0,
      elevation: 2.0,
      pressedElevation: 4.0,
    ),
    overlayColor: Color(0xFF3498DB).withOpacity(0.2),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 24.0),
  ),
);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true, // Material 3 を有効化
  colorScheme: ColorScheme.fromSeed(
    seedColor: Color(0xFF1B4B72),
    primary: Color(0xFF3498DB),
    secondary: Color(0xFF1B4B72),
    surface: Color(0xFF1E1E1E),
    background: Color(0xFF121212),
    brightness: Brightness.dark,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Color(0xFF3498DB),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24), // より大きな角丸
      ),
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
  ),
  tabBarTheme: TabBarTheme(
    labelColor: Color(0xFF3498DB),
    unselectedLabelColor: Color(0xFF8F9BA8),
    labelStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    unselectedLabelStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
    ),
  ),
  listTileTheme: ListTileThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  sliderTheme: SliderThemeData(
    activeTrackColor: Color(0xFF3498DB),
    inactiveTrackColor: Color(0xFF505050),
    trackHeight: 10.0,
    trackShape: RoundedRectSliderTrackShape(),
    thumbColor: Colors.white,
    thumbShape: RoundSliderThumbShape(
      enabledThumbRadius: 12.0,
      elevation: 2.0,
      pressedElevation: 4.0,
    ),
    overlayColor: Color(0xFF3498DB).withOpacity(0.2),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 24.0),
  ),
);

class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsStoreProvider).themeMode;
    return MaterialApp(
      title: 'Flexta PDF Reader',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: LibraryScreen(),
    );
  }
}
