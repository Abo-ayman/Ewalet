import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// الألوان والثوابت
// ─────────────────────────────────────────────
const kBg = Color(0xFF0D1225);
const kAccent = Color(0xFF4C8DF6);
const kRed = Color(0xFFFF4D4D);
const kGreen = Color(0xFF3FCB7C);
const kTeal = Color(0xFF5B98A4);
const kPurple = Color(0xFF7D609E);
// تدرّج زري استقبال/إرسال (يبدأ فاتح من الزاوية العلوية اليسرى وينتهي أغمق
// في الزاوية السفلية اليمنى) مأخوذ من الصورتين المرجعيتين.
const kTealGradient = [Color(0xFF63A3AF), Color(0xFF477F91)];
const kPurpleGradient = [Color(0xFF8B6BAE), Color(0xFF624588)];
const kGlass = Color(0x1FFFFFFF);
const kGlassStrong = Color(0x2EFFFFFF);
const kDialogBg = Color(0xFF1B2A6B);

/// مسار صورتك الخاصة للأفاتار (أعلى اليمين).
/// اتركه فارغاً لاستخدام الأيقونة الافتراضية، وعند الانتهاء ضع مثلاً:
/// 'assets/images/avatar.png' (وفعّل قسم assets في pubspec.yaml)
const String kAvatarAsset = '';

const Map<String, double> kInitialBalances = {
  'USD': 433.0,
  'EUR': 50.0,
  'SYP': 500000.0,
};

/// عندما ينزل رصيد الدولار إلى هذا الحد أو أقل يعود تلقائياً لقيمته الأصلية
const double kUsdResetThreshold = 10;

const List<String> kCurrencies = ['EUR', 'USD', 'SYP'];

TextStyle ts(double size, {Color color = Colors.white}) => TextStyle(
      fontFamily: 'Tajawal',
      // ملاحظة: عائلة خط Tajawal ما فيها وزن 600 (SemiBold) أصلاً ضمن
      // إصداراتها الرسمية (الأوزان المتوفرة: 200/300/400/500/700/800/900)،
      // فطلب w600 بيخلي Flutter يستخدم أقرب وزن أثقل متوفر وهو 700 (Bold).
      // يعني النتيجة البصرية = نفس Bold تقريبًا. إذا حابب وزن أخف من Bold
      // بوضوح، الأقرب الفعلي التالي هو Medium (500).
      fontWeight: FontWeight.w600,
      fontSize: size,
      color: color,
    );

// ─────────────────────────────────────────────
// دوال مساعدة
// ─────────────────────────────────────────────
String money(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  final parts = s.split('.');
  final intPart =
      parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
}

String amountLabel(double v, String c) {
  switch (c) {
    case 'USD':
      return '\$${money(v)}';
    case 'EUR':
      return '€${money(v)}';
    default:
      return '${money(v)} ل.س';
  }
}

String p2(int n) => n.toString().padLeft(2, '0');

String fmtDate(String iso) {
  final d = DateTime.parse(iso);
  return '${d.year}/${p2(d.month)}/${p2(d.day)} - '
      '${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}';
}

String toEnglishDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var o = s.replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.');
  for (var i = 0; i < 10; i++) {
    o = o.replaceAll(ar[i], '$i');
  }
  return o;
}

// ─────────────────────────────────────────────
// النموذج والحالة (بيانات وهمية + حفظ محلي)
// ─────────────────────────────────────────────
class Transfer {
  final String id;
  final String name;
  final String currency;
  final double amount;
  final String at; // ISO 8601
  final String type; // 'out' = حوالة صادرة (افتراضي)، 'in' = حوالة مستقبَلة

  Transfer({
    required this.id,
    required this.name,
    required this.currency,
    required this.amount,
    required this.at,
    this.type = 'out',
  });

  bool get isIncoming => type == 'in';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currency': currency,
        'amount': amount,
        'at': at,
        'type': type,
      };

  factory Transfer.fromJson(Map<String, dynamic> j) => Transfer(
        id: j['id'] as String,
        name: j['name'] as String,
        currency: j['currency'] as String,
        amount: (j['amount'] as num).toDouble(),
        at: j['at'] as String,
        // بيانات محفوظة قديمًا ما فيها هذا الحقل، فنعتبرها صادرة (السلوك
        // القديم قبل إضافة الاستقبال الحقيقي).
        type: j['type'] as String? ?? 'out',
      );
}

class WalletState extends ChangeNotifier {
  Map<String, double> balances = Map.of(kInitialBalances);
  List<Transfer> transfers = [];
  String currency = 'USD';
  bool hidden = false;
  bool loaded = false;

  double get balance => balances[currency] ?? 0;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final b = p.getString('balances');
    final t = p.getString('transfers');
    if (b != null) {
      balances = (jsonDecode(b) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    if (t != null) {
      transfers = (jsonDecode(t) as List)
          .map((e) => Transfer.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      transfers = _seed();
    }
    currency = p.getString('currency') ?? 'USD';
    hidden = p.getBool('hidden') ?? false;
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('balances', jsonEncode(balances));
    await p.setString(
        'transfers', jsonEncode(transfers.map((e) => e.toJson()).toList()));
    await p.setString('currency', currency);
    await p.setBool('hidden', hidden);
  }

  List<Transfer> _seed() {
    final now = DateTime.now();
    Transfer t(String id, String n, String c, double a, int minsAgo) =>
        Transfer(
          id: id,
          name: n,
          currency: c,
          amount: a,
          at: now.subtract(Duration(minutes: minsAgo)).toIso8601String(),
        );
    return [
      t('#447337927', 'مقهى النخيل', 'USD', 0.5, 5),
      t('#447336723', 'مقهى النخيل', 'SYP', 100, 6),
      t('#447280060', 'مكتبة الأمل', 'SYP', 200, 26),
      t('#447248816', 'محمد أحمد', 'SYP', 430, 38),
      t('#447055257', 'متجر السلام', 'SYP', 260, 110),
      t('#446594287', 'مخبز الشام', 'SYP', 1950, 300),
    ];
  }

  void setCurrency(String c) {
    currency = c;
    notifyListeners();
    _save();
  }

  void toggleHidden() {
    hidden = !hidden;
    notifyListeners();
    _save();
  }

  /// يرجع نص الخطأ إن فشل، أو null عند النجاح
  String? send(String name, double amount) {
    if (amount.isNaN || amount <= 0) return 'أدخل مبلغاً صحيحاً';
    if (amount > balance) return 'الرصيد غير كافٍ';
    balances[currency] = balance - amount;
    transfers.insert(
      0,
      Transfer(
        id: '#44${1000000 + Random().nextInt(9000000)}',
        name: name,
        currency: currency,
        amount: amount,
        at: DateTime.now().toIso8601String(),
        type: 'out',
      ),
    );
    if ((balances['USD'] ?? 0) <= kUsdResetThreshold) {
      balances['USD'] = kInitialBalances['USD']!;
    }
    notifyListeners();
    _save();
    return null;
  }

  /// نفس خطوات send() تماماً لكن بالاتجاه المعاكس: تُضاف للرصيد بدل ما
  /// تُخصم، وتُسجَّل الحوالة كـ "مستقبَلة" (type: 'in') فتظهر بالأخضر
  /// وبدون إشارة "-" بواجهة المستخدم.
  String? receive(String name, double amount) {
    if (amount.isNaN || amount <= 0) return 'أدخل مبلغاً صحيحاً';
    balances[currency] = balance + amount;
    transfers.insert(
      0,
      Transfer(
        id: '#44${1000000 + Random().nextInt(9000000)}',
        name: name,
        currency: currency,
        amount: amount,
        at: DateTime.now().toIso8601String(),
        type: 'in',
      ),
    );
    notifyListeners();
    _save();
    return null;
  }
}

// ─────────────────────────────────────────────
// التطبيق
// ─────────────────────────────────────────────
void main() => runApp(const WalletApp());

class WalletApp extends StatelessWidget {
  const WalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المحفظة',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Tajawal',
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final wallet = WalletState();
  int tab = 0;

  @override
  void initState() {
    super.initState();
    wallet.load();
  }

  @override
  void dispose() {
    wallet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(color: kBg),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: wallet,
            builder: (ctx, child) {
              if (!wallet.loaded) {
                return const Center(child: CircularProgressIndicator());
              }
              final pages = <Widget>[
                HomePage(
                  wallet: wallet,
                  onSend: () => startSendFlow(context, wallet),
                  onReceive: () => startReceiveFlow(context, wallet),
                  onSeeAll: () => setState(() => tab = 1),
                ),
                TransfersPage(wallet: wallet),
                const PlaceholderPage(
                    icon: Icons.credit_card_rounded, title: 'الخدمات'),
                const PlaceholderPage(
                    icon: Icons.person_outline_rounded, title: 'حسابي'),
              ];
              return Stack(
                children: [
                  Column(
                    children: [
                      const TopBar(),
                      Expanded(child: pages[tab]),
                    ],
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 10,
                    child: BottomNav(
                      index: tab,
                      onTap: (i) => setState(() => tab = i),
                      onScan: () => openScanner(context, wallet),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// الشريط العلوي (جرس + أفاتار قابل للاستبدال)
// ─────────────────────────────────────────────
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: kGlassStrong,
      ),
      child: kAvatarAsset.isNotEmpty
          ? Image.asset(kAvatarAsset, fit: BoxFit.cover)
          : const Icon(Icons.person_rounded, color: Colors.white, size: 28),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          const ProfileAvatar(),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded,
                  color: Colors.white, size: 32),
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: kRed,
                    shape: BoxShape.circle,
                  ),
                  child: Text('1', style: ts(11)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// الصفحة الرئيسية
// ─────────────────────────────────────────────
class HomePage extends StatelessWidget {
  final WalletState wallet;
  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onSeeAll;

  const HomePage({
    super.key,
    required this.wallet,
    required this.onSend,
    required this.onReceive,
    required this.onSeeAll,
  });

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('قريباً (نسخة تجريبية)', style: ts(14))),
    );
  }

  @override
  Widget build(BuildContext context) {
    // آخر 4 حوالات فقط. النصف العلوي (الرصيد + الاختصارات + استقبال/إرسال)
    // ثابت بدون تمرير، وقائمة "آخر التحويلات" فقط هي الجزء القابل للتمرير،
    // وبنفس شكل ومقاس بطاقات شاشة "التحويلات" تماماً (TransferTile).
    final recent = wallet.transfers.take(4).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              // الرصيد + العملات + العين
              Row(
                children: [
                  Text(
                    wallet.hidden ? '•••••' : money(wallet.balance),
                    style: ts(36),
                    textDirection: TextDirection.ltr,
                  ),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: kCurrencies.map((c) {
                      final sel = c == wallet.currency;
                      return GestureDetector(
                        onTap: () => wallet.setCurrency(c),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            c,
                            style: ts(sel ? 30 : 16,
                                color: sel ? Colors.white : Colors.white70),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: wallet.toggleHidden,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: kGlassStrong,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        wallet.hidden
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // الاختصارات + استقبال/إرسال
              SizedBox(
                height: 250,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kGlass,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: GridView.count(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            QuickTile(
                                icon: Icons.bookmark_rounded,
                                label: 'خدماتي',
                                onTap: () => _soon(context)),
                            QuickTile(
                                icon: Icons.layers_rounded,
                                label: 'مدفوعات',
                                onTap: () => _soon(context)),
                            QuickTile(
                                icon: Icons.receipt_long_rounded,
                                label: 'فواتير',
                                onTap: () => _soon(context)),
                            MoreTile(onTap: () => _soon(context)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: BigButton(
                              label: 'استقبال',
                              icon: Icons.call_received,
                              gradient: kTealGradient,
                              onTap: onReceive,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: BigButton(
                              label: 'إرسال',
                              icon: Icons.call_made,
                              gradient: kPurpleGradient,
                              onTap: onSend,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),

              // آخر التحويلات
              GestureDetector(
                onTap: onSeeAll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('آخر التحويلات', style: ts(20)),
                    const SizedBox(height: 6),
                    Container(width: 60, height: 3, color: kAccent),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),

        // القسم القابل للتمرير وحده — بنفس بطاقة شاشة التحويلات (TransferTile)
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
            children: recent.map((t) => HomeTransferRow(transfer: t)).toList(),
          ),
        ),
      ],
    );
  }
}

// صف حوالة بالشاشة الرئيسية — نفس التصميم الأصلي (سطر واحد: الاسم + المبلغ +
// أيقونة)، لكن بنفس مقاس بطاقة شاشة "التحويلات" (نفس الحشو الداخلي وهامش
// السفل ونصف قطر الزوايا) عشان يتطابق الحجم بين الشاشتين.
class HomeTransferRow extends StatelessWidget {
  final Transfer transfer;
  const HomeTransferRow({super.key, required this.transfer});

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    final color = t.isIncoming ? kGreen : kRed;
    final sign = t.isIncoming ? '+' : '-';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: kGlass,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Text(t.name, style: ts(17)),
          const Spacer(),
          Text(
            '$sign ${t.currency} ${money(t.amount)}',
            style: ts(16, color: color),
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(width: 6),
          Icon(
            t.isIncoming ? Icons.download_rounded : Icons.upload_rounded,
            color: color,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const QuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kGlassStrong,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 34),
            const SizedBox(height: 6),
            Text(label, style: ts(13)),
          ],
        ),
      ),
    );
  }
}

class MoreTile extends StatelessWidget {
  final VoidCallback onTap;
  const MoreTile({super.key, required this.onTap});

  Widget _mini(IconData? icon) => Container(
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: icon == null ? null : Icon(icon, size: 16, color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kGlassStrong,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _mini(Icons.eject_rounded),
              _mini(Icons.layers_rounded),
              _mini(null),
              _mini(null),
            ],
          ),
        ),
      ),
    );
  }
}

class BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  const BigButton({
    super.key,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Center(
            child: Row(
              // النص أولاً ثم الأيقونة: بما أن التطبيق RTL، هذا يضع النص
              // يميناً والأيقونة يساراً تماماً كما في التصميم المرجعي.
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: ts(20)),
                const SizedBox(width: 12),
                Icon(icon, color: Colors.white, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// تبويب التحويلات + الإيصال
// ─────────────────────────────────────────────
class TransfersPage extends StatelessWidget {
  final WalletState wallet;
  const TransfersPage({super.key, required this.wallet});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
      children: [
        Row(
          children: [
            Text('آخر التحويلات', style: ts(22)),
            const Spacer(),
            Text('متقدم', style: ts(16, color: kAccent)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text('اضغط مطولاً لعرض الإيصال', style: ts(14)),
          ],
        ),
        const SizedBox(height: 14),
        if (wallet.transfers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Text('لا توجد تحويلات بعد',
                  style: ts(16, color: Colors.white70)),
            ),
          ),
        ...wallet.transfers.map(
          (t) => TransferTile(transfer: t, onLongPress: () => showReceipt(context, t)),
        ),
      ],
    );
  }
}

// بطاقة حوالة واحدة — نفس الشكل والمقاس بالضبط، تُستخدم بشاشة "التحويلات"
// وبقائمة "آخر التحويلات" بالشاشة الرئيسية كي يتطابق حجمهما تماماً.
class TransferTile extends StatelessWidget {
  final Transfer transfer;
  final VoidCallback? onLongPress;

  const TransferTile({super.key, required this.transfer, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: kGlass,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name, style: ts(18)),
                const SizedBox(height: 10),
                Text(
                  t.isIncoming
                      ? '+ ${amountLabel(t.amount, t.currency)}'
                      : '- ${amountLabel(t.amount, t.currency)}',
                  style: ts(19, color: t.isIncoming ? kGreen : kRed),
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(t.id, style: ts(15), textDirection: TextDirection.ltr),
                const SizedBox(height: 14),
                Text(fmtDate(t.at),
                    style: ts(14), textDirection: TextDirection.ltr),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _receiptRow(String label, String value, {bool ltr = false, Color? color}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Text(label, style: ts(14, color: Colors.white60)),
        const Spacer(),
        Text(
          value,
          style: ts(15, color: color ?? Colors.white),
          textDirection: ltr ? TextDirection.ltr : null,
        ),
      ],
    ),
  );
}

void showReceipt(BuildContext context, Transfer t) {
  showModalBottomSheet(
    context: context,
    backgroundColor: kDialogBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          CircleAvatar(
            radius: 28,
            backgroundColor: t.isIncoming ? kGreen : kTeal,
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 10),
          Text('إيصال التحويل', style: ts(20)),
          const SizedBox(height: 16),
          _receiptRow('رقم العملية', t.id, ltr: true),
          _receiptRow(t.isIncoming ? 'المرسل' : 'المستلم', t.name),
          _receiptRow(
            'المبلغ',
            t.isIncoming
                ? '+ ${amountLabel(t.amount, t.currency)}'
                : '- ${amountLabel(t.amount, t.currency)}',
            color: t.isIncoming ? kGreen : kRed,
          ),
          _receiptRow('التاريخ', fmtDate(t.at), ltr: true),
          _receiptRow('الحالة', 'ناجحة'),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: t.id));
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text('نسخ رقم العملية', style: ts(16)),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// تدفق الإرسال (اسم المستقبل ← المبلغ ← تم التحويل)
// ─────────────────────────────────────────────
class _InputDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String action;
  final TextInputType keyboard;

  const _InputDialog({
    required this.title,
    required this.hint,
    required this.action,
    required this.keyboard,
  });

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final c = TextEditingController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kDialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.title, style: ts(20)),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: widget.keyboard,
        style: ts(18),
        onSubmitted: (v) => Navigator.pop(context, v),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: ts(16, color: Colors.white38),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white38),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: kAccent),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('إلغاء', style: ts(16, color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, c.text),
          child: Text(widget.action, style: ts(16, color: kAccent)),
        ),
      ],
    );
  }
}

Future<void> startSendFlow(
  BuildContext context,
  WalletState w, {
  String? presetName,
}) async {
  var name = presetName;
  if (name == null) {
    name = await showDialog<String>(
      context: context,
      builder: (_) => const _InputDialog(
        title: 'اسم المستقبل',
        hint: 'اكتب اسم المستقبل',
        action: 'التالي',
        keyboard: TextInputType.name,
      ),
    );
    if (name == null || name.trim().isEmpty) return;
  }
  if (!context.mounted) return;

  final cur = w.currency;
  final raw = await showDialog<String>(
    context: context,
    builder: (_) => _InputDialog(
      title: 'المبلغ',
      hint: cur,
      action: 'إرسال',
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    ),
  );
  if (raw == null || !context.mounted) return;

  final amount = double.tryParse(toEnglishDigits(raw.trim())) ?? 0;
  final err = w.send(name.trim(), amount);
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err, style: ts(14))),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kDialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 32,
            backgroundColor: kTeal,
            child: Icon(Icons.check_rounded, size: 42, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text('تم التحويل', style: ts(22)),
          const SizedBox(height: 6),
          Text(
            '${amountLabel(amount, cur)} إلى ${name!.trim()}',
            style: ts(15, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('حسناً', style: ts(16, color: kAccent)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
// الاستقبال (نفس خطوات الإرسال تماماً، لكن بالاتجاه المعاكس)
// ─────────────────────────────────────────────
Future<void> startReceiveFlow(BuildContext context, WalletState w) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const _InputDialog(
      title: 'اسم المرسل',
      hint: 'اكتب اسم المرسل',
      action: 'التالي',
      keyboard: TextInputType.name,
    ),
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;

  final cur = w.currency;
  final raw = await showDialog<String>(
    context: context,
    builder: (_) => _InputDialog(
      title: 'المبلغ',
      hint: cur,
      action: 'استقبال',
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    ),
  );
  if (raw == null || !context.mounted) return;

  final amount = double.tryParse(toEnglishDigits(raw.trim())) ?? 0;
  final err = w.receive(name.trim(), amount);
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err, style: ts(14))),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kDialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 32,
            backgroundColor: kGreen,
            child: Icon(Icons.check_rounded, size: 42, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text('تم الاستقبال', style: ts(22)),
          const SizedBox(height: 6),
          Text(
            '${amountLabel(amount, cur)} من ${name.trim()}',
            style: ts(15, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('حسناً', style: ts(16, color: kAccent)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
// ماسح الباركود / QR
// ─────────────────────────────────────────────
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final controller = MobileScannerController();
  bool handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('مسح الباركود', style: ts(18)),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (handled) return;
              final code =
                  capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
              if (code == null || code.isEmpty) return;
              handled = true;
              Navigator.pop(context, code);
            },
          ),
          Center(
            child: IgnorePointer(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: kAccent, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openScanner(BuildContext context, WalletState w) async {
  final code = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const ScannerPage()),
  );
  if (code == null || !context.mounted) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kDialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('تم مسح الرمز', style: ts(20)),
      content: Text(code,
          style: ts(16, color: kAccent), textDirection: TextDirection.ltr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('إغلاق', style: ts(16, color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('تحويل', style: ts(16, color: kAccent)),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await startSendFlow(context, w, presetName: code);
  }
}

// ─────────────────────────────────────────────
// شريط التنقل السفلي + زر QR العائم
// ─────────────────────────────────────────────
class BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onScan;

  const BottomNav({
    super.key,
    required this.index,
    required this.onTap,
    required this.onScan,
  });

  Widget _item(int i, IconData icon, String label) {
    final sel = index == i;
    final color = sel ? kAccent : Colors.white;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onTap(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(label, style: ts(13, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xCC1A2A66),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x22FFFFFF)),
            ),
            child: Row(
              children: [
                _item(0, Icons.home_rounded, 'الرئيسية'),
                _item(1, Icons.monetization_on_outlined, 'التحويلات'),
                const SizedBox(width: 84),
                _item(2, Icons.credit_card_rounded, 'الخدمات'),
                _item(3, Icons.person_outline_rounded, 'حسابي'),
              ],
            ),
          ),
          Positioned(
            top: 0,
            child: GestureDetector(
              onTap: onScan,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x554C8DF6),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.qr_code_scanner_rounded,
                    color: Colors.white, size: 38),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// صفحات مؤقتة (الخدمات / حسابي)
// ─────────────────────────────────────────────
class PlaceholderPage extends StatelessWidget {
  final IconData icon;
  final String title;

  const PlaceholderPage({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.white54),
          const SizedBox(height: 12),
          Text(title, style: ts(20)),
          const SizedBox(height: 6),
          Text('قريباً…', style: ts(14, color: Colors.white54)),
        ],
      ),
    );
  }
}
