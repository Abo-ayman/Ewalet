import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// الألوان والثوابت
// ─────────────────────────────────────────────
const kBg = Color(0xFF1B244B); // أفتح 5٪ إضافية من 0xFF141B38
const kAccent = Color(0xFF4C8DF6);
const kRed = Color(0xFF6B1F2A);
const kSendRed = Color(0xFFFF2A6D); // أحمر الحوالات الصادرة (لون محدد صراحة)
const kTeal = Color(0xFF5B98A4);
const kPurple = Color(0xFF7D609E);
// ألوان زري استقبال/إرسال — مطابقة للتصميم الجديد (أخضر زمردي غامق / أحمر نبيتي غامق)
const kTealGradient = [Color(0xFF1E3B36), kGreen]; // استقبال
const kPurpleGradient = [Color(0xFF2E1119), kRed]; // إرسال
// لون السهم والنص على كل زر
const kReceiveInk = Color(0xFFDCE7F0);
const kSendInk = Color(0xFFF3E6F7);
const kGlass = Color(0x1FFFFFFF);
const kGlassStrong = Color(0x2EFFFFFF);
// لون الشريط السفلي = نفس لون خلفية الحوالات (kGlass فوق kBg) لكن معتم، وحافته بلون الخلفية العامة
final kNavBg = Color.alphaBlend(kGlass, kBg);
const kDialogBg = Color(0xFF1B2A6B);
// أخضر الحوالات المستقبَلة + أخضر زر المشاركة عبر واتساب
const kGreen = Color(0xFF428177);
const kWhatsapp = Color(0xFF25D366);
// أخضر شريط "تمت العملية بنجاح" بعد إتمام التحويل
const kSuccessGreen = Color(0xFF2FA860);
// أزرق زر "تصدير" بالإيصال — نفس اللون يُعتمد لأي زر رئيسي مشابه بالتطبيق
const kExportBlue = Color(0xFF0277BD);

/// مسار صورتك الخاصة للأفاتار (أعلى اليمين).
/// اتركه فارغاً لاستخدام الأيقونة الافتراضية، وعند الانتهاء ضع مثلاً:
/// 'assets/images/avatar.png' (وفعّل قسم assets في pubspec.yaml)
const String kAvatarAsset = 'assets/images/logo.png';

const Map<String, double> kInitialBalances = {
  'USD': 433.0,
  'EUR': 50.0,
  'SYP': 500000.0,
};

/// عندما ينزل رصيد الدولار إلى هذا الحد أو أقل يعود تلقائياً لقيمته الأصلية
const double kUsdResetThreshold = 10;

const List<String> kCurrencies = ['EUR', 'USD', 'SYP'];

// خط Tajawal بوزن 600 (SemiBold) في كل التطبيق — بين Medium وBold
TextStyle ts(double size, {Color color = Colors.white}) => TextStyle(
      fontFamily: 'Tajawal',
      fontWeight: FontWeight.w600,
      fontSize: size,
      color: color,
    );

/// أول 3 كلمات من الاسم كحد أقصى؛ أي زيادة تُستبدل بـ "..."
String shortName(String name, {int maxWords = 3}) {
  final words = name.trim().split(RegExp(r'\s+'));
  if (words.length <= maxWords) return name.trim();
  return '${words.take(maxWords).join(' ')} ...';
}

/// نفس ts لكن بوزن 400 (يُستخدم في شاشة التحويلات)
TextStyle ts400(double size, {Color color = Colors.white}) =>
    ts(size, color: color).copyWith(fontWeight: FontWeight.w400);

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

/// رقم حساب الطرف الآخر (أول 4 أرقام) يُشتق من رقم العملية للحوالات القديمة
String acctFromId(String id) {
  final d = id.replaceAll(RegExp(r'\D'), '');
  return d.length >= 4 ? d.substring(d.length - 4) : d.padLeft(4, '0');
}

/// 0214************ — نفس شكل الحساب في الإيصال المرجعي
String maskAcct(String first4) => '$first4************';

String receiptAmount(double v, String c) {
  switch (c) {
    case 'USD':
      return '\$ ${money(v)}';
    case 'EUR':
      return '€ ${money(v)}';
    default:
      return '${money(v)} ل.س';
  }
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
  final String name; // الطرف الآخر: المستقبِل عند الإرسال، المرسِل عند الاستقبال
  final String currency;
  final double amount;
  final String at; // ISO 8601
  final bool incoming; // true = حوالة مستقبَلة
  final String acct; // أول 4 أرقام من حساب الطرف الآخر (للإيصال)
  final String note; // ملاحظة اختيارية أُدخلت عند التحويل

  Transfer({
    required this.id,
    required this.name,
    required this.currency,
    required this.amount,
    required this.at,
    this.incoming = false,
    this.acct = '',
    this.note = '',
  });

  String get otherAcct => acct.isNotEmpty ? acct : acctFromId(id);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currency': currency,
        'amount': amount,
        'at': at,
        'incoming': incoming,
        'acct': acct,
        'note': note,
      };

  factory Transfer.fromJson(Map<String, dynamic> j) => Transfer(
        id: j['id'] as String,
        name: j['name'] as String,
        currency: j['currency'] as String,
        amount: (j['amount'] as num).toDouble(),
        at: j['at'] as String,
        incoming: j['incoming'] == true,
        acct: (j['acct'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
      );
}

class WalletState extends ChangeNotifier {
  Map<String, double> balances = Map.of(kInitialBalances);
  List<Transfer> transfers = [];
  String currency = 'USD';
  bool hidden = false;
  bool loaded = false;

  /// اسم صاحب الحساب (يظهر في الإيصالات) + أول 4 أرقام من رقم حسابه
  String ownerName = '';
  String ownAcct = '';
  /// علامة التوثيق الزرقاء الصغيرة جنب الاسم (تُفعَّل/تُعطَّل يدوياً)
  bool verified = false;

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
    ownerName = p.getString('ownerName') ?? '';
    verified = p.getBool('verified') ?? false;
    var acct = p.getString('ownAcct');
    if (acct == null || acct.isEmpty) {
      acct = '${1000 + Random().nextInt(9000)}';
      await p.setString('ownAcct', acct);
    }
    ownAcct = acct;
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
    await p.setString('ownerName', ownerName);
    await p.setBool('verified', verified);
    await p.setString('ownAcct', ownAcct);
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

  void toggleVerified() {
    verified = !verified;
    notifyListeners();
    _save();
  }

  void setOwnerName(String v) {
    ownerName = v.trim();
    notifyListeners();
    _save();
  }

  Transfer _make(String name, double amount,
          {required bool incoming, required String currency, String note = ''}) =>
      Transfer(
        id: '#44${1000000 + Random().nextInt(9000000)}',
        name: name,
        currency: currency,
        amount: amount,
        at: DateTime.now().toIso8601String(),
        incoming: incoming,
        acct: '${1000 + Random().nextInt(9000)}',
        note: note,
      );

  /// يرجع نص الخطأ إن فشل، أو null عند النجاح.
  /// [currency] اختياري: عملة هذه العملية تحديداً (افتراضياً عملة الشاشة الحالية).
  String? send(String name, double amount, {String? currency, String note = ''}) {
    final cur = currency ?? this.currency;
    final bal = balances[cur] ?? 0;
    if (amount.isNaN || amount <= 0) return 'أدخل مبلغاً صحيحاً';
    if (amount > bal) return 'الرصيد غير كافٍ';
    balances[cur] = bal - amount;
    transfers.insert(0, _make(name, amount, incoming: false, currency: cur, note: note));
    if ((balances['USD'] ?? 0) <= kUsdResetThreshold) {
      balances['USD'] = kInitialBalances['USD']!;
    }
    notifyListeners();
    _save();
    return null;
  }

  /// استقبال حوالة: يزيد الرصيد ويضيف حوالة مستقبَلة (خضراء) في القائمة
  String? receive(String name, double amount, {String? currency, String note = ''}) {
    final cur = currency ?? this.currency;
    if (amount.isNaN || amount <= 0) return 'أدخل مبلغاً صحيحاً';
    balances[cur] = (balances[cur] ?? 0) + amount;
    transfers.insert(0, _make(name, amount, incoming: true, currency: cur, note: note));
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
      home: const SplashPage(),
    );
  }
}

// ─────────────────────────────────────────────
// شاشة البداية (Splash) — نفس خلفية التطبيق (kBg) مع اللوجو بالوسط،
// ثم انتقال بتلاشٍ ناعم إلى الشاشة الرئيسية.
// ─────────────────────────────────────────────
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) => const Shell(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          width: 140,
          height: 140,
          fit: BoxFit.contain,
        ),
      ),
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
                AccountPage(wallet: wallet),
              ];
              return Stack(
                children: [
                  // الربع الأعلى اليمين، مع اختفاء 30٪ من عرضه خارج حافة
                  // الشاشة اليمنى (right سالب = مُزاح للخارج) كحركة جمالية.
                  Positioned(
                    top: 40,
                    right: -84, // 30٪ من 280
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.25, // 0.15 + 10٪
                        child: Image.asset(
                          'assets/images/logo_watermark.png',
                          width: 280,
                          height: 280,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      const TopBar(),
                      Expanded(child: pages[tab]),
                    ],
                  ),
                  // خلفية صلبة بلون خلفية الشاشة خلف الشريط فقط (بارتفاعه 72
                  // فقط، وليس ارتفاع الشريط الكامل 100 الذي يشمل زر الباركود)،
                  // فتمنع تداخل الحوالات معه دون أن تترك حداً عريضاً فوقه.
                  // زر الباركود له حافة صغيرة خاصة به (4 بكسل) تكفيه بمفرده.
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(height: 68.4, color: kBg), // مطابق لسماكة الشريط الجديدة
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 0,
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
          // الشعار كاملاً داخل الدائرة (بدون قص) مع هامش صغير
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                kAvatarAsset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            )
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
          const GreetingLabel(),
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

/// تحية حسب وقت اليوم (صباح/مساء) بدل صورة الأفاتار — كما في التصميم الجديد
class GreetingLabel extends StatelessWidget {
  const GreetingLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final isDay = hour >= 5 && hour < 18;
    final text = isDay ? 'صباح الخير' : 'مساء الخير';
    final icon = isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 6),
        Text(text, style: ts(16)),
      ],
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

  /// صف "آخر التحويلات": ارتفاع ثابت 64 كما في الصورة المرجعية
  Widget _recentRow(Transfer t) {
    const k = 0.95; // تصغير 5٪ (الارتفاع والخط) — العرض يطابق الشريط السفلي
    final c = t.incoming ? kGreen : kSendRed;
    return Container(
      height: 64 * k * 0.95, // أنحف 5٪ إضافية
      margin: EdgeInsets.only(bottom: 13 * k),
      padding: EdgeInsets.symmetric(horizontal: 18 * k),
      decoration: BoxDecoration(
        color: kGlass,
        borderRadius: BorderRadius.circular(16), // أدوّر، مطابق للتصميم الجديد
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(t.name,
                style: ts(17 * k),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: 8 * k),
          Text(
            '${t.currency} ${money(t.amount)}',
            style: ts(17 * k, color: c),
            textDirection: TextDirection.ltr,
          ),
          SizedBox(width: 6 * k),
          Icon(
            t.incoming ? Icons.download_rounded : Icons.upload_rounded,
            color: c,
            size: 22 * k,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = wallet.transfers.take(5).toList();
    return Column(
      children: [
        // النصف العلوي ثابت (الرصيد + الاختصارات + عنوان "آخر التحويلات")
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الرصيد + عجلة العملات (اسحب للأعلى/الأسفل) + العين
              BalanceHeader(wallet: wallet),
              const SizedBox(height: 20),

              // الاختصارات + استقبال/إرسال — مربع (الارتفاع = نصف العرض) مثل المرجع
              LayoutBuilder(
                builder: (context, cons) {
                  const k = 0.95; // تصغير 5٪
                  final side = (cons.maxWidth - 14) / 2;
                  return Center(
                    child: SizedBox(
                      width: cons.maxWidth * k,
                      height: side * k, // ارتفاع كامل يمنع اختفاء الصف السفلي تحت الإطار
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kGlass,
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: GridView.count(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                padding: EdgeInsets.zero,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  QuickTile(
                                      icon: Icons.layers_rounded,
                                      label: 'مدفوعات',
                                      onTap: () => _soon(context)),
                                  QuickTile(
                                      icon: Icons.receipt_long_rounded,
                                      label: 'فواتير',
                                      onTap: () => _soon(context)),
                                  QuickTile(
                                      icon: Icons.compare_arrows_rounded,
                                      label: 'حوالات',
                                      onTap: () => _soon(context)),
                                  QuickTile(
                                      icon: Icons.account_balance_rounded,
                                      label: 'بنوك',
                                      onTap: () => _soon(context)),
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
                                    arrowAngle: -pi / 4, // السهم لأسفل اليسار
                                    ink: kReceiveInk,
                                    gradient: kTealGradient,
                                    onTap: onReceive,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: BigButton(
                                    label: 'إرسال',
                                    arrowAngle: 3 * pi / 4, // السهم لأعلى اليمين
                                    ink: kSendInk,
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
                  );
                },
              ),
              const SizedBox(height: 26),

              // آخر التحويلات
              GestureDetector(
                onTap: onSeeAll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('آخر التحويلات', style: ts(20)),
                    const SizedBox(height: 8),
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
        // آخر التحويلات فقط هي القابلة للتمرير
        Expanded(
          child: ListView(
            // 14 من كل جهة = نفس هامش الشريط السفلي (left/right: 14 في Shell)
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 120),
            children: recent.map(_recentRow).toList(),
          ),
        ),
      ],
    );
  }
}

/// الرصيد الكبير + عجلة العملات (أسماء فقط) + زر العين.
/// اسحب على الرصيد/العملات للأعلى أو للأسفل لتبديل العملة، ويظهر رصيد العملة
/// المختارة في الجهة الأخرى. الضغط على اسم عملة يختارها أيضاً.
class BalanceHeader extends StatefulWidget {
  final WalletState wallet;
  const BalanceHeader({super.key, required this.wallet});

  @override
  State<BalanceHeader> createState() => _BalanceHeaderState();
}

class _BalanceHeaderState extends State<BalanceHeader> {
  double _acc = 0;
  int _dir = 1; // اتجاه آخر تبديل (للحركة)

  void _select(String code, int dir) {
    if (code == widget.wallet.currency) return;
    HapticFeedback.selectionClick();
    setState(() => _dir = dir);
    widget.wallet.setCurrency(code);
  }

  void _move(int step) {
    final n = kCurrencies.length;
    final i = kCurrencies.indexOf(widget.wallet.currency);
    _select(kCurrencies[(i + step + n) % n], step);
  }

  /// انزلاق سلس: العنصر الجديد يدخل من جهة السحب والقديم يخرج للجهة المعاكسة
  /// (مع تلاشي ومنحنى ناعم). يُستخدم للعجلة وللرصيد معاً ليتحركا بتناغم.
  Widget _slider(String code, Widget child, {required double shift}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        clipBehavior: Clip.none,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (c, anim) {
        final incoming = c.key == ValueKey<String>(code);
        final begin = Offset(0, (incoming ? _dir : -_dir) * shift);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: begin, end: Offset.zero).animate(anim),
            child: c,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<String>(code), child: child),
    );
  }

  Widget _side(String code, int dir) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(code, dir),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.4), // 3 ← -20٪
        child: Text(code, style: ts(19.2, color: Colors.white70)), // 20٪ أصغر من الوسط (24)
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallet;
    final n = kCurrencies.length;
    final i = kCurrencies.indexOf(w.currency);
    final prev = kCurrencies[(i - 1 + n) % n];
    final next = kCurrencies[(i + 1) % n];

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => _acc = 0,
            onVerticalDragUpdate: (d) {
              _acc += d.delta.dy;
              if (_acc <= -26) {
                _acc = 0;
                _move(1); // سحب للأعلى ← العملة التالية
              } else if (_acc >= 26) {
                _acc = 0;
                _move(-1); // سحب للأسفل ← العملة السابقة
              }
            },
            child: Row(
              children: [
                // يأخذ كل المساحة المتبقية، ويصغّر الرقم فقط إذا كان طويلاً جداً
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _slider(
                      w.currency,
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          w.hidden ? '•••••' : money(w.balance),
                          style: ts(28.8), // 36 ← -20٪
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                      shift: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _slider(
                  w.currency,
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _side(prev, -1),
                      Text(w.currency, style: ts(24)), // 30 ← -20٪
                      _side(next, 1),
                    ],
                  ),
                  shift: 0.34,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: w.toggleHidden,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: kGlassStrong,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              w.hidden
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ],
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: ts(13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MoreTile extends StatelessWidget {
  final VoidCallback onTap;
  const MoreTile({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kGlassStrong,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.move_to_inbox_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Icon(Icons.layers_rounded, color: Colors.white, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// سهمك المرسل (assets/images/arrow.png) — يُدوَّر ويُلوَّن حسب الزر:
/// إرسال: 3π/4 (يشير لأعلى اليمين)، استقبال: -π/4 (يشير لأسفل اليسار)
class ActionArrow extends StatelessWidget {
  final double angle; // بالراديان، الموجب مع عقارب الساعة
  final Color color;
  final double size;

  const ActionArrow({
    super.key,
    required this.angle,
    required this.color,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Image.asset(
        'assets/images/arrow.png',
        width: size,
        height: size,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class BigButton extends StatelessWidget {
  final String label;
  final double arrowAngle;
  final Color ink;
  final List<Color> gradient;
  final VoidCallback onTap;

  const BigButton({
    super.key,
    required this.label,
    required this.arrowAngle,
    required this.ink,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Center(
            child: Row(
              // النص أولاً ثم الأيقونة: بما أن التطبيق RTL، هذا يضع النص
              // يميناً والأيقونة يساراً تماماً كما في التصميم المرجعي.
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: ts(20, color: ink)),
                const SizedBox(width: 14),
                ActionArrow(angle: arrowAngle, color: ink),
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
    return LayoutBuilder(
      builder: (context, cons) {
        // 7 حوالات ظاهرة كاملة في الشاشة: نطرح ~96 للعنوان و~108 للشريط السفلي
        // ثم نقسم الباقي على 7 (بين 76 و96 لكل صف مع الفاصل).
        final pitch =
            ((cons.maxHeight - 96 - 108) / 7).clamp(76.0, 96.0).toDouble();
        final rowH = (pitch - 13) * 0.95; // أنحف 5٪
        return Column(
          children: [
            // العنوان + الملاحظة ثابتان، لا ينزلقان
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      Text('اضغط مطولاً لعرض الوصل', style: ts(14)),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            // الحوالات فقط هي القابلة للتمرير تحت الملاحظة
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
                children: [
                  if (wallet.transfers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Center(
                        child: Text('لا توجد تحويلات بعد',
                            style: ts(16, color: Colors.white70)),
                      ),
                    ),
                  ...wallet.transfers.map((t) {
              final color = t.incoming ? kGreen : kSendRed;
              return GestureDetector(
                // ضغطة واحدة: تحويل جديد لنفس صاحب الحوالة (يسأل عن المبلغ فقط)
                onTap: () => startSendFlow(context, wallet, presetName: t.name),
                // الضغط المطول يفتح الوصل في شاشة جديدة
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReceiptPage(
                        t: t,
                        ownerName: wallet.ownerName,
                        ownAcct: wallet.ownAcct,
                      ),
                    ),
                  );
                },
                child: Container(
                  height: rowH,
                  margin: const EdgeInsets.only(bottom: 13),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: kGlass,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(shortName(t.name),
                                style: ts400(18).copyWith(height: 1.2), // وزن 400 للاسم فقط
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            // المستقبَلة: أخضر مع (+)، والمرسلة: أحمر مع (-)
                            Text(
                              '${t.incoming ? '+' : '-'} '
                              '${amountLabel(t.amount, t.currency)}',
                              style: ts(19, color: color).copyWith(height: 1.2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(t.id,
                              style: ts(15).copyWith(height: 1.2),
                              textDirection: TextDirection.ltr),
                          const SizedBox(height: 6),
                          Text(fmtDate(t.at),
                              style: ts(14).copyWith(height: 1.2),
                              textDirection: TextDirection.ltr),
                        ],
                      ),
                    ],
                  ),
                ),
              );
                  }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// شاشة الوصل: الوصل في الثلث العلوي، وباقي الصفحة بيضاء، وفي الأسفل زرا
/// "تصدير" و"مشاركة" اللذان ينشئان ملف PDF ويفتحان قائمة المشاركة.
class ReceiptPage extends StatefulWidget {
  final Transfer t;
  final String ownerName;
  final String ownAcct;

  const ReceiptPage({
    super.key,
    required this.t,
    required this.ownerName,
    required this.ownAcct,
  });

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  static const _exportBlue = kExportBlue; // أزرق سماوي داكن
  static final _shareGray = Colors.grey.shade600; // رمادي زر المشاركة
  final GlobalKey _boundaryKey = GlobalKey();
  final DateTime _createdAt = DateTime.now();
  bool busy = false;

  Future<void> _export() async {
    final ctx = _boundaryKey.currentContext;
    if (ctx == null || busy) return;
    setState(() => busy = true);
    try {
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('render failed');
      final pdfBytes = await buildReceiptPdf(
        data.buffer.asUint8List(),
        image.width,
        image.height,
      );
      final opNo = widget.t.id.replaceAll('#', '');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sham_cash_receipt_$opNo.pdf');
      await file.writeAsBytes(pdfBytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        text: 'وصل عملية رقم $opNo',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء الوصل', style: ts(14))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const ink = Color(0xFF111111);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark, // أيقونات شريط الحالة داكنة على الأبيض
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: ink),
                    ),
                    Text('الوصل', style: ts(18, color: ink)),
                  ],
                ),
              ),
              // الوصل بعرض الشاشة كاملاً مع هامش 10 بكسل من كل الجهات
              // (يصغر تلقائياً فقط إن لم تتسع الشاشة له)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: size.width - 20,
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: ReceiptCard(
                          t: widget.t,
                          ownerName: widget.ownerName,
                          ownAcct: widget.ownAcct,
                          createdAt: _createdAt,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _exportBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              _exportBlue.withOpacity(0.6),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: busy ? null : _export,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.share_rounded),
                        label: Text('تصدير', style: ts(18)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _shareGray,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              _shareGray.withOpacity(0.6),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: busy ? null : _export,
                        icon: const Icon(Icons.share_rounded),
                        label: Text('مشاركة', style: ts(18)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// PDF بصفحة واحدة بحجم الوصل تماماً (الوصل نفسه كصورة عالية الدقة، فيظهر
/// النص العربي بنفس شكل الشاشة بدون أي مشاكل في تشكيل الحروف).
Future<Uint8List> buildReceiptPdf(Uint8List png, int pxW, int pxH) async {
  const contentW = 420.0;
  final contentH = contentW * pxH / pxW;
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(contentW + 40, contentH + 40),
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Image(
        pw.MemoryImage(png),
        width: contentW,
        height: contentH,
      ),
    ),
  );
  return doc.save();
}

/// تصميم الوصل — مطابق للصورة المرجعية: بيضاء، خطان رماديان أعلى وأسفل،
/// الحقول من اليمين، الأسماء بخط عريض، وشعار خفيف في الخلفية.
class ReceiptCard extends StatelessWidget {
  final Transfer t;
  final String ownerName;
  final String ownAcct;
  final DateTime createdAt;

  const ReceiptCard({
    super.key,
    required this.t,
    required this.ownerName,
    required this.ownAcct,
    required this.createdAt,
  });

  static const _ink = Color(0xFF111111);
  static const _bar = Color(0xFFC9C9C9);

  TextStyle _s(double size, [FontWeight w = FontWeight.w400]) => TextStyle(
        fontFamily: 'Tajawal',
        fontWeight: w,
        fontSize: size,
        color: _ink,
        height: 1.25,
      );

  Widget _row(String label, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(width: 112, child: Text(label, style: _s(15))),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: value,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final owner = ownerName.trim().isEmpty ? 'صاحب الحساب' : ownerName.trim();
    final senderName = t.incoming ? t.name : owner;
    final senderAcct = t.incoming ? t.otherAcct : ownAcct;
    final receiverName = t.incoming ? owner : t.name;
    final receiverAcct = t.incoming ? ownAcct : t.otherAcct;

    final d = DateTime.parse(t.at);
    final dateStr = '${d.year}-${p2(d.month)}-${p2(d.day)}';
    final timeStr = '${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}';
    final createdDate = '${p2(createdAt.day)}/${p2(createdAt.month)}/${createdAt.year}';
    final createdTime = '${p2(createdAt.hour > 12 ? createdAt.hour - 12 : (createdAt.hour == 0 ? 12 : createdAt.hour))}:${p2(createdAt.minute)}';
    final createdPeriod = createdAt.hour >= 12 ? 'PM' : 'AM';
    final opNo = t.id.replaceAll('#', '');
    final amountLtr = t.currency != 'SYP';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.30,
                  child: Image.asset(
                    'assets/images/logo.png', // نفس لوجو الرأس، كعلامة مائية بالوسط
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                // الشعار والكلمة بجانبه معاً جهة اليمين
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(width: 8),
                  Text('شام كاش', style: _s(22, FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              Container(height: 2, color: _bar),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'العملية ', style: _s(15)),
                      TextSpan(
                        text: t.incoming ? 'استقبال' : 'إرسال',
                        style: _s(15, FontWeight.w700),
                      ),
                      TextSpan(text: ' - رقم ', style: _s(15)),
                      TextSpan(text: opNo, style: _s(15, FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              _row(
                'تاريخ العملية:',
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(dateStr,
                        style: _s(15, FontWeight.w500),
                        textDirection: TextDirection.ltr),
                    Text(' - ', style: _s(15)),
                    Text(timeStr,
                        style: _s(15, FontWeight.w500),
                        textDirection: TextDirection.ltr),
                  ],
                ),
              ),
              _row('اسم المرسل:',
                  Text(senderName, style: _s(15, FontWeight.w700))),
              _row(
                'حساب المرسل:',
                Text(maskAcct(senderAcct),
                    style: _s(15, FontWeight.w500),
                    textDirection: TextDirection.ltr),
              ),
              _row('اسم المستلم:',
                  Text(receiverName, style: _s(15, FontWeight.w700))),
              _row(
                'حساب المستلم:',
                Text(maskAcct(receiverAcct),
                    style: _s(15, FontWeight.w500),
                    textDirection: TextDirection.ltr),
              ),
              _row(
                'المبلغ:',
                Text(
                  receiptAmount(t.amount, t.currency),
                  style: _s(15, FontWeight.w500),
                  textDirection:
                      amountLtr ? TextDirection.ltr : TextDirection.rtl,
                ),
              ),
              _row(
                'الملاحظة:',
                Text(
                  t.note.trim().isEmpty ? '—' : t.note.trim(),
                  style: _s(15, FontWeight.w500),
                ),
              ),
              const SizedBox(height: 10),
              Container(height: 4, color: _bar),
              const SizedBox(height: 10),
              Row(
                textDirection: TextDirection.rtl,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'تم إنشاء الملف عبر ',
                    style: _s(13),
                  ),
                  Text(
                    'شام كاش',
                    style: _s(13, FontWeight.w700).copyWith(
                      color: const Color(0xFF5B79B6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '$createdPeriod $createdTime - $createdDate',
                  style: _s(12, FontWeight.w500),
                  textDirection: TextDirection.ltr,
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
// تدفق الإرسال (اسم المستقبل ← المبلغ ← تم التحويل)
// ─────────────────────────────────────────────
class _BottomInputSheet extends StatefulWidget {
  final String? title;
  final String hint;
  final String action;
  final TextInputType keyboard;

  const _BottomInputSheet({
    this.title,
    required this.hint,
    required this.action,
    required this.keyboard,
  });

  @override
  State<_BottomInputSheet> createState() => _BottomInputSheetState();
}

class _BottomInputSheetState extends State<_BottomInputSheet> {
  final c = TextEditingController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // يرفع الشيت فوق لوحة المفاتيح عند فتحها
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: kDialogBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // مقبض صغير أعلى الشيت (شكل شائع لنوافذ الإدخال السفلية)
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              if (widget.title != null) ...[
                Text(widget.title!, style: ts(14, color: Colors.white70)),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: c,
                autofocus: true,
                textAlign: TextAlign.center,
                keyboardType: widget.keyboard,
                style: ts(20),
                onSubmitted: (v) => Navigator.pop(context, v),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: ts(20, color: Colors.white54),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kExportBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, c.text),
                  child: Text(widget.action, style: ts(18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// نتيجة شيت "تحويل أموال" (المبلغ + الملاحظة + العملة المختارة داخل الشيت)
class _TransferResult {
  final double amount;
  final String note;
  final String currency;
  _TransferResult(this.amount, this.note, this.currency);
}

/// شيت "تحويل أموال" — يظهر بعد بطاقة معلومات الحساب مباشرة: يستعرض الطرف
/// الآخر (اسم + رقم حساب مقنّع)، ثم اختيار العملة، ثم المبلغ المحوَّل،
/// ثم ملاحظة اختيارية، وأخيراً زر إرسال/استقبال.
class _TransferAmountSheet extends StatefulWidget {
  final String name;
  final bool incoming;
  final String initialCurrency;

  const _TransferAmountSheet({
    required this.name,
    required this.incoming,
    required this.initialCurrency,
  });

  @override
  State<_TransferAmountSheet> createState() => _TransferAmountSheetState();
}

class _TransferAmountSheetState extends State<_TransferAmountSheet> {
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  late String currency = widget.initialCurrency;

  @override
  void dispose() {
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Widget _currencyChip(String code, String label) {
    final sel = currency == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => currency = code),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: sel ? kAccent : kGlassStrong,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(label, style: ts(16)),
        ),
      ),
    );
  }

  Widget _box(String hint, TextEditingController c, {TextInputType? kb}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kGlassStrong,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: c,
        keyboardType: kb,
        style: ts(16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: ts(16, color: Colors.white54),
          border: InputBorder.none,
        ),
      ),
    );
  }

  void _submit() {
    final amount = double.tryParse(toEnglishDigits(amountCtrl.text.trim())) ?? 0;
    Navigator.pop(
      context,
      _TransferResult(amount, noteCtrl.text.trim(), currency),
    );
  }

  @override
  Widget build(BuildContext context) {
    // بيانات وهمية ثابتة لنفس الاسم (نفس المنطق المستخدم في بطاقة معلومات الحساب)
    final hash = widget.name.trim().hashCode.abs();
    final last4 = (1000 + hash % 9000).toString();
    final isVerified = hash.isEven;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: kDialogBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    widget.incoming ? 'استقبال أموال' : 'تحويل أموال',
                    style: ts(20),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: kGlassStrong,
                        ),
                        child: const Icon(Icons.person_rounded,
                            color: Colors.white, size: 46),
                      ),
                      const SizedBox(height: 10),
                      Text(widget.name, style: ts(19)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isVerified) ...[
                            const Icon(Icons.verified_rounded,
                                color: kAccent, size: 16),
                            const SizedBox(width: 6),
                          ],
                          Text('**** **** **** $last4',
                              style: ts(15, color: Colors.white70),
                              textDirection: TextDirection.ltr),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    _currencyChip('SYP', 'سوري'),
                    _currencyChip('USD', 'دولار'),
                    _currencyChip('EUR', 'يورو'),
                  ],
                ),
                const SizedBox(height: 22),
                Text('المبلغ المحول', style: ts(15, color: Colors.white70)),
                const SizedBox(height: 8),
                _box(
                  'أدخل المبلغ',
                  amountCtrl,
                  kb: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 18),
                Text('ملاحظة', style: ts(15, color: Colors.white70)),
                const SizedBox(height: 8),
                _box('اكتب ملاحظة', noteCtrl),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _submit,
                    child: Text(widget.incoming ? 'استقبال' : 'إرسال',
                        style: ts(18)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// يفتح شيت "تحويل أموال" ويرجع النتيجة (المبلغ + الملاحظة + العملة)، أو null عند الإلغاء
Future<_TransferResult?> _showTransferAmountSheet(
  BuildContext context, {
  required String name,
  required bool incoming,
  required String initialCurrency,
}) {
  return showModalBottomSheet<_TransferResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _TransferAmountSheet(
      name: name,
      incoming: incoming,
      initialCurrency: initialCurrency,
    ),
  );
}

/// يعرض شريط "تمت العملية بنجاح" الأخضر بنفس تصميم الإشعار المرجعي —
/// يطفو أعلى الشريط السفلي وزر QR بدل نافذة منتصف الشاشة.
void _showSuccessBanner(BuildContext context, {required bool incoming}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: kSuccessGreen,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 90),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      content: Row(
        children: [
          Expanded(
            child: Text(
              incoming ? 'تم الاستقبال بنجاح' : 'تمت العملية بنجاح',
              style: ts(15),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
        ],
      ),
    ),
  );
}

/// يفتح نافذة إدخال بأسفل الشاشة (بدل نافذة منبثقة بالوسط)
Future<String?> _showBottomInput(
  BuildContext context, {
  String? title,
  required String hint,
  required String action,
  required TextInputType keyboard,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _BottomInputSheet(
      title: title,
      hint: hint,
      action: action,
      keyboard: keyboard,
    ),
  );
}

/// بطاقة "معلومات الحساب" تظهر بعد إدخال الاسم مباشرة، وقبل خطوة المبلغ —
/// تستعرض اسم الطرف الآخر ورقم حسابه (مع علامة توثيق أحياناً حسب الحساب)
/// ونوع الحساب وتاريخ إنشائه، مع زري "إضافة" و"إرسال/استقبال".
class _AccountInfoSheet extends StatelessWidget {
  final String name;
  final bool incoming;

  const _AccountInfoSheet({required this.name, required this.incoming});

  Widget _field(String label, Widget value) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ts(15, color: Colors.white70)),
            const SizedBox(height: 8),
            value,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    // بيانات وهمية ثابتة لنفس الاسم (نفس الاسم يعطي نفس النتيجة دائماً)
    final hash = name.trim().hashCode.abs();
    final last4 = (1000 + hash % 9000).toString();
    final isVerified = hash.isEven;
    final created = DateTime.now().subtract(Duration(days: 20 + hash % 400));
    final createdStr = '${p2(created.day)}/${p2(created.month)}/${created.year}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: kDialogBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text('معلومات الحساب', style: ts(20)),
            const SizedBox(height: 18),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: kGlassStrong,
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: Colors.white, size: 42),
                  ),
                  const SizedBox(height: 10),
                  Text(name, style: ts(19)),
                ],
              ),
            ),
            _field(
              'رقم الحساب',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isVerified) ...[
                    const Icon(Icons.verified_rounded,
                        color: kAccent, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Text('**** **** **** $last4',
                      style: ts(16), textDirection: TextDirection.ltr),
                ],
              ),
            ),
            _field('نوع الحساب',
                Text('حساب شخصي', style: ts(15, color: Colors.white70))),
            _field(
              'تاريخ إنشاء الحساب',
              Text(createdStr,
                  style: ts(15, color: Colors.white70),
                  textDirection: TextDirection.ltr),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kGlassStrong,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('تمت الإضافة (نسخة تجريبية)',
                                style: ts(14))),
                      );
                    },
                    child: Text('إضافة', style: ts(17)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('إرسال', style: ts(17)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// يعرض بطاقة معلومات الحساب، ويرجع true إذا ضغط المستخدم زر المتابعة
Future<bool> _showAccountInfo(
  BuildContext context, {
  required String name,
  required bool incoming,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AccountInfoSheet(name: name, incoming: incoming),
  );
  return res ?? false;
}

Future<void> startSendFlow(
  BuildContext context,
  WalletState w, {
  String? presetName,
}) =>
    startTransferFlow(context, w, incoming: false, presetName: presetName);

/// زر الاستقبال: نفس تدفق الإرسال تماماً (اسم المرسل ← المبلغ ← تم)
Future<void> startReceiveFlow(BuildContext context, WalletState w) =>
    startTransferFlow(context, w, incoming: true);

Future<void> startTransferFlow(
  BuildContext context,
  WalletState w, {
  required bool incoming,
  String? presetName,
}) async {
  var name = presetName;
  if (name == null) {
    name = await _showBottomInput(
      context,
      title: incoming ? 'اسم المرسل' : 'اسم المستقبل',
      hint: 'أدخل الاسم',
      action: 'التالي',
      keyboard: TextInputType.name,
    );
    if (name == null || name.trim().isEmpty) return;
  }
  if (!context.mounted) return;

  // بطاقة معلومات الحساب تظهر مباشرة بعد الاسم، قبل خطوة المبلغ
  final proceed = await _showAccountInfo(
    context,
    name: name.trim(),
    incoming: incoming,
  );
  if (!proceed || !context.mounted) return;

  final result = await _showTransferAmountSheet(
    context,
    name: name.trim(),
    incoming: incoming,
    initialCurrency: w.currency,
  );
  if (result == null || !context.mounted) return;

  final amount = result.amount;
  final err = incoming
      ? w.receive(name.trim(), amount, currency: result.currency, note: result.note)
      : w.send(name.trim(), amount, currency: result.currency, note: result.note);
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err, style: ts(14))),
    );
    return;
  }

  _showSuccessBanner(context, incoming: incoming);
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
            height: 68.4, // 72 أنحف 5٪
            decoration: BoxDecoration(
              color: kNavBg,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: kBg, width: 4),
            ),
            child: Row(
              children: [
                _item(0, Icons.home_rounded, 'الرئيسية'),
                _item(1, Icons.monetization_on_outlined, 'التحويلات'),
                const SizedBox(width: 88),
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
                width: 80, // 72 + حافة 4 من كل جهة
                height: 80,
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: kBg, width: 4),
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

// ─────────────────────────────────────────────
// حسابي — اسم صاحب الحساب (يظهر في الإيصالات)
// ─────────────────────────────────────────────
class AccountPage extends StatefulWidget {
  final WalletState wallet;
  const AccountPage({super.key, required this.wallet});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final TextEditingController c =
      TextEditingController(text: widget.wallet.ownerName);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _save() {
    widget.wallet.setOwnerName(c.text);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ الاسم', style: ts(14))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: kGlassStrong),
                child: const Icon(Icons.person_rounded,
                    color: Colors.white, size: 50),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.wallet.ownerName.isEmpty
                        ? 'حسابي'
                        : widget.wallet.ownerName,
                    style: ts(22),
                  ),
                  const SizedBox(width: 6),
                  // زر صغير يفعّل/يعطّل علامة التوثيق الزرقاء جنب الاسم
                  GestureDetector(
                    onTap: widget.wallet.toggleVerified,
                    child: Icon(
                      Icons.verified_rounded,
                      color: widget.wallet.verified
                          ? kAccent
                          : Colors.white24,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kGlass,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('اسم صاحب الحساب', style: ts(16)),
              const SizedBox(height: 4),
              Text('يظهر في الإيصالات كاسم المرسل أو المستلم',
                  style: ts(13, color: Colors.white60)),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                style: ts(18),
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  hintText: 'اكتب الاسم الكامل',
                  hintStyle: ts(16, color: Colors.white38),
                  filled: true,
                  fillColor: kGlass,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kAccent),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _save,
                  child: Text('حفظ', style: ts(16)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: kGlass,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Text('رقم الحساب', style: ts(16)),
              const Spacer(),
              Text(maskAcct(widget.wallet.ownAcct),
                  style: ts(16, color: Colors.white70),
                  textDirection: TextDirection.ltr),
            ],
          ),
        ),
      ],
    );
  }
}
