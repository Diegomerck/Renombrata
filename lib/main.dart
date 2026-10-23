import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'src/ui/home_screen.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(1280, 820),          // Default launch size
    minimumSize: Size(1100, 720),   // Hard minimum limit: prevents UI breakage
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'Renombrata',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setMinimumSize(const Size(1100, 720));
    await windowManager.show();
    await windowManager.focus();
  });

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode');
  
  if (isDark != null) {
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  runApp(const RenombrataApp());
}

class RenombrataApp extends StatelessWidget {
  const RenombrataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Renombrata',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
            scaffoldBackgroundColor: const Color(0xFFE9EDF4),
            cardColor: const Color(0xFFF7F8FA),
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFBCC4D2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFBCC4D2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.deepPurple, width: 1.5),
              ),
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
            scaffoldBackgroundColor: const Color(0xFF131316),
            cardColor: const Color(0xFF1E1E24),
            inputDecorationTheme: const InputDecorationTheme(
              fillColor: Color(0xFF16161A),
              filled: true,
            ),
            useMaterial3: true,
          ),
          themeMode: currentMode,
          home: const HomeScreen(),
        );
      },
    );
  }
}
