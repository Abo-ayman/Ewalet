import 'package:flutter/material.dart';
import '../models/transaction.dart';

class RecentTransferItem extends StatelessWidget {
  final Transaction transaction;

  const RecentTransferItem({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isSend = transaction.type == TransactionType.send;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF08112E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // الاسم
          Text(
            transaction.name,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),

          // المبلغ
          Text(
            transaction.formattedAmount,
            style: TextStyle(
              color: isSend ? Colors.red : Colors.green,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
