import 'package:flutter/material.dart';
import '../models/transaction.dart';

class TransactionCard extends StatelessWidget {
  final Transaction transaction;

  const TransactionCard({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isSend = transaction.type == TransactionType.send;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF08112E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            transaction.formattedId,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            transaction.formattedDateTime,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            transaction.name,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 10),
          Text(
            transaction.formattedAmount,
            style: TextStyle(
              color: isSend ? Colors.red : Colors.green,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
