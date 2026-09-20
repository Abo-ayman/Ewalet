enum TransactionType { send, receive }

class Transaction {
  final String id;
  final String name;
  final DateTime dateTime;
  final double amount;
  final String currency;
  final TransactionType type;

  Transaction({
    required this.id,
    required this.name,
    required this.dateTime,
    required this.amount,
    required this.currency,
    required this.type,
  });

  String get formattedId => '#$id';

  String get formattedDateTime =>
      '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')}'
      ' - ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';

  String get formattedAmount {
    if (currency == 'USD') {
      return '\$${amount.toStringAsFixed(2)} ${type == TransactionType.send ? '–' : '+'}';
    }
    return '${amount.toStringAsFixed(0)} ل.س ${type == TransactionType.send ? '–' : '+'}';
  }

  bool get isSend => type == TransactionType.send;
}
