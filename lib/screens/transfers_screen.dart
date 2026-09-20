import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../widgets/transaction_card.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = Provider.of<WalletProvider>(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  "آخر التحويلات",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  "متقدم",
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ],
            ),

            const SizedBox(height: 6),
            const Text(
              "اضغط مطولاً لعرض الإيصال",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: wallet.transactions.length,
                itemBuilder: (context, index) {
                  return TransactionCard(transaction: wallet.transactions[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
