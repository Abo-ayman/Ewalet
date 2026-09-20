import 'package:flutter/material.dart';

class BalanceCard extends StatelessWidget {
  final double balance;

  const BalanceCard({super.key, required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF08112E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "USD",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            balance.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Icon(Icons.remove_red_eye, color: Colors.white70),
              SizedBox(width: 8),
              Text("إخفاء الرصيد", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }
}
