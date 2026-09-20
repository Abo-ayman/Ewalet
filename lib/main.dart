import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ShamCashApp());
}

class ShamCashApp extends StatelessWidget {
  const ShamCashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShamCash',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: const HomeScreen(),
    );
  }
}
