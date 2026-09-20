import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'transfers_screen.dart';
import 'services_screen.dart';
import 'account_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int index = 0;

  final screens = const [
    HomeScreen(),
    TransfersScreen(),
    ServicesScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[index],
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        color: const Color(0xFF08112E),
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              navItem(Icons.home, 'الرئيسية', 0),
              navItem(Icons.swap_horiz, 'التحويلات', 1),
              navItem(Icons.miscellaneous_services, 'الخدمات', 2),
              navItem(Icons.person, 'حسابي', 3),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00BFA5),
        child: const Icon(Icons.qr_code_scanner),
        onPressed: () {},
      ),
    );
  }

  Widget navItem(IconData icon, String label, int i) {
    final selected = index == i;
    return InkWell(
      onTap: () => setState(() => index = i),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: selected ? Colors.white : Colors.grey),
          Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
