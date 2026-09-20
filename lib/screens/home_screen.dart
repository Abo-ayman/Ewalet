import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../widgets/balance_card.dart';
import '../widgets/recent_transfer_item.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = Provider.of<WalletProvider>(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // أعلى الشاشة: الإشعارات + العنوان
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "E-Walet",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Stack(
                  children: [
                    const Icon(Icons.notifications, color: Colors.white, size: 28),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          "1",
                          style: TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                    )
                  ],
                )
              ],
            ),

            const SizedBox(height: 20),

            // بطاقة الرصيد
            BalanceCard(balance: wallet.balanceUsd),

            const SizedBox(height: 20),

            // أزرار إرسال / استقبال
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _receiveDialog(context),
                    child: const Text(
                      "استقبال",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _sendDialog(context),
                    child: const Text(
                      "إرسال",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            // شبكة الخدمات
            const Text(
              "الخدمات",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _serviceItem(Icons.payment, "مدفوعات"),
                _serviceItem(Icons.list_alt, "خدماتي"),
                _serviceItem(Icons.receipt_long, "فواتير"),
              ],
            ),

            const SizedBox(height: 30),

            // آخر التحويلات
            const Text(
              "آخر التحويلات",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 12),

            Column(
              children: wallet.recentTransactions
                  .map((tx) => RecentTransferItem(transaction: tx))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // عنصر الخدمة
  Widget _serviceItem(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF08112E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  // نافذة إرسال الأموال
  void _sendDialog(BuildContext context) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF08112E),
        title: const Text("إرسال", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "الاسم",
                labelStyle: TextStyle(color: Colors.white),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "المبلغ",
                labelStyle: TextStyle(color: Colors.white),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text.trim()) ?? 0;

              if (name.isNotEmpty && amount > 0) {
                Provider.of<WalletProvider>(context, listen: false)
                    .addSend(name, amount);

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("تم التحويل", textAlign: TextAlign.center),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text("إرسال", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // نافذة استقبال الأموال
  void _receiveDialog(BuildContext context) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF08112E),
        title: const Text("استقبال", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "الاسم",
                labelStyle: TextStyle(color: Colors.white),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "المبلغ",
                labelStyle: TextStyle(color: Colors.white),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text.trim()) ?? 0;

              if (name.isNotEmpty && amount > 0) {
                Provider.of<WalletProvider>(context, listen: false)
                    .addReceive(name, amount);

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("تم الاستقبال", textAlign: TextAlign.center),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text("استقبال", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
