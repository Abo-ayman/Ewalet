import 'package:flutter/material.dart';
import '../widgets/balance_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ShamCash'),
      ),
      body: const Center(
        child: BalanceCard(),
      ),
    );
  }
}
