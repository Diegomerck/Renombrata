import 'package:flutter/material.dart';
import 'src/ui/home_screen.dart';

void main() {
  runApp(const RenombrataApp());
}

class RenombrataApp extends StatelessWidget {
  const RenombrataApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Renombrata',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
