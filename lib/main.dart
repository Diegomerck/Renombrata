import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'src/ui/home_screen.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(1280, 820),          // Default launch size
    minimumSize: Size(1000, 720),   // Hard minimum limit: prevents UI breakage
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'Renombrata',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
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
  const RenombrataApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Renombrata',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
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
