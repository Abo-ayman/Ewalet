import 'package:flutter/material.dart';
import '../models/transaction.dart';

class WalletProvider extends ChangeNotifier {
  final List<Transaction> _transactions = [];
  double _balanceUsd = 1425.0;

  WalletProvider() {
    _seedMockData();
  }

  List<Transaction> get transactions => List.unmodifiable(_transactions);
  double get balanceUsd => _balanceUsd;

  List<Transaction> get recentTransactions {
    final list = List<Transaction>.from(_transactions);
    list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return list.take(4).toList();
  }

  void _seedMockData() {
    _transactions.addAll([
      Transaction(
        id: '447337927',
        name: 'بالس كافيه',
        dateTime: DateTime(2026, 9, 12, 20, 14, 3),
        amount: 0.5,
        currency: 'USD',
        type: TransactionType.send,
      ),
      Transaction(
        id: '447336723',
        name: 'بالس كافيه',
        dateTime: DateTime(2026, 9, 12, 20, 13, 35),
        amount: 100,
        currency: 'SYP',
        type: TransactionType.send,
      ),
      Transaction(
        id: '447280060',
        name: 'بالس كافيه',
        dateTime: DateTime(2026, 9, 12, 19, 53, 7),
        amount: 200,
        currency: 'SYP',
        type: TransactionType.send,
      ),
      Transaction(
        id: '447248816',
        name: 'ماهر ثائر موسى',
        dateTime: DateTime(2026, 9, 12, 19, 41, 55),
        amount: 430,
        currency: 'SYP',
        type: TransactionType.send,
      ),
    ]);
  }

  void _ensureLimit() {
    if (_transactions.length > 1000) {
      _transactions.removeRange(0, _transactions.length - 1000);
    }
  }

  void _checkBalanceReset() {
    if (_balanceUsd < 100) {
      _balanceUsd = 1425.0;
    }
  }

  void addSend(String name, double amount) {
    final tx = Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      dateTime: DateTime.now(),
      amount: amount,
      currency: 'USD',
      type: TransactionType.send,
    );
    _transactions.add(tx);
    _balanceUsd -= amount;
    _ensureLimit();
    _checkBalanceReset();
    notifyListeners();
  }

  void addReceive(String name, double amount) {
    final tx = Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      dateTime: DateTime.now(),
      amount: amount,
      currency: 'USD',
      type: TransactionType.receive,
    );
    _transactions.add(tx);
    _balanceUsd += amount;
    _ensureLimit();
    notifyListeners();
  }
}
