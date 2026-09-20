import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/wallet_provider.dart';
import 'screens/main_navigation.dart';

void main() {
  runApp(const EWalletApp());
}

class EWalletApp extends StatelessWidget {
  const EWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark();

    final theme = base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF020824),
      textTheme: GoogleFonts.tajawalTextTheme(base.textTheme),
      colorScheme: base.colorScheme.copyWith(
        primary: const Color(0xFF0D47A1),
        secondary: const Color(0xFF00BFA5),
        surface: const Color(0xFF08112E),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF08112E),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
      ),
    );

    return ChangeNotifierProvider(
      create: (_) => WalletProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        theme: theme,
        home: const MainNavigationScreen(),
      ),
    );
  }
}
