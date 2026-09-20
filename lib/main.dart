import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/wallet_provider.dart';
import 'screens/main_navigation.dart';

void main() {
  runApp(const ShamCashApp());
}

class ShamCashApp extends StatelessWidget {
  const ShamCashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WalletProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "ShamCash",
        theme: ThemeData(
          fontFamily: "Tajawal",
          scaffoldBackgroundColor: const Color(0xFF0A122F),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0A122F),
            brightness: Brightness.dark,
          ),
        ),
        home: const MainNavigation(),
      ),
    );
  }
}
