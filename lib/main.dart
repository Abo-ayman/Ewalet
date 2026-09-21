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
const kBg = Color(0xFF0D1225);
const kAccent = Color(0xFF4C8DF6);
const kRed = Color(0xFFFF4D4D);
const kTeal = Color(0xFF5B98A4);
const kPurple = Color(0xFF7D609E);
// ألوان زري استقبال/إرسال — مقاسة من الصورة المرجعية (من اليسار لليمين)
const kTealGradient = [Color(0xFF3A4547), Color(0xFF32434C)]; // استقبال
const kPurpleGradient = [Color(0xFF38233F), Color(0xFF402A44)]; // إرسال
// لون السهم والنص على كل زر
const kReceiveInk = Color(0xFFDCE7F0);
const kSendInk = Color(0xFFF3E6F7);
const kGlass = Color(0x1FFFFFFF);
const kGlassStrong = Color(0x2EFFFFFF);
const kDialogBg = Color(0xFF1B2A6B);
// أخضر الحوالات المستقبَلة + أخضر زر المشاركة عبر واتساب
const kGreen = Color(0xFF054239);
const kWhatsapp = Color(0xFF25D366);

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

  Transfer({
    required this.id,
    required this.name,
    required this.currency,
    required this.amount,
    required this.at,
    this.incoming = false,
    this.acct = '',
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
      };

  factory Transfer.fromJson(Map<String, dynamic> j) => Transfer(
        id: j['id'] as String,
        name: j['name'] as String,
        currency: j['currency'] as String,
        amount: (j['amount'] as num).toDouble(),
        at: j['at'] as String,
        incoming: j['incoming'] == true,
        acct: (j['acct'] as String?) ?? '',
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

  void setOwnerName(String v) {
    ownerName = v.trim();
    notifyListeners();
    _save();
  }

  Transfer _make(String name, double amount, {required bool incoming}) =>
      Transfer(
        id: '#44${1000000 + Random().nextInt(9000000)}',
        name: name,
        currency: currency,
        amount: amount,
        at: DateTime.now().toIso8601String(),
        incoming: incoming,
        acct: '${1000 + Random().nextInt(9000)}',
      );

  /// يرجع نص الخطأ إن فشل، أو null عند النجاح
  String? send(String name, double amount) {
    if (amount.isNaN || amount <= 0) return 'أدخل مبلغاً صحيحاً';
    if (amount > balance) return 'الرصيد غير كافٍ';
    balances[currency] = balance - amount;
    transfers.insert(0, _make(name, amount, incoming: false));
    if ((balances['USD'] ?? 0) <= kUsdResetThreshold) {
      balances['USD'] = kInitialBalances['USD']!;
    }
    notifyListeners();
    _save();
    return null;
  }

  /// استقبال حوالة: يزيد الرصيد ويضيف حوالة مستقبَلة (خضراء) في القائمة
  String? receive(String name, double amount) {
    if (amount.isNaN || amount <= 0) return 'أدخل مبلغاً صحيحاً';
    balances[currency] = balance + amount;
    transfers.insert(0, _make(name, amount, incoming: true));
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
                AccountPage(wallet: wallet),
              ];
              return Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: 0.10,
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
                  ),
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

  /// صف "آخر التحويلات": ارتفاع ثابت 64 كما في الصورة المرجعية
  Widget _recentRow(Transfer t) {
    final c = t.incoming ? kGreen : kRed;
    return Container(
      height: 64,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: kGlass,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(t.name,
                style: ts(17), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(
            '${t.incoming ? '+ ' : ''}${t.currency} ${money(t.amount)}',
            style: ts(17, color: c),
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(width: 6),
          Icon(
            t.incoming ? Icons.download_rounded : Icons.upload_rounded,
            color: c,
            size: 22,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = wallet.transfers.take(5).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        // الرصيد + عجلة العملات (اسحب للأعلى/الأسفل) + العين
        BalanceHeader(wallet: wallet),
        const SizedBox(height: 20),

        // الاختصارات + استقبال/إرسال — مربع (الارتفاع = نصف العرض) مثل المرجع
        LayoutBuilder(
          builder: (context, cons) {
            final side = (cons.maxWidth - 14) / 2;
            return SizedBox(
              height: side,
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
            );
          },
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
        ...recent.map(_recentRow),
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

  Widget _side(String code, int dir) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(code, dir),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(code, style: ts(16, color: Colors.white70)),
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        w.hidden ? '•••••' : money(w.balance),
                        style: ts(36),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(0, 0.25 * _dir),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(w.currency),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _side(prev, -1),
                      Text(w.currency, style: ts(30)),
                      _side(next, 1),
                    ],
                  ),
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
        final rowH = pitch - 13;
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
                Text('اضغط مطولاً لعرض الوصل', style: ts(14)),
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
            ...wallet.transfers.map((t) {
              final color = t.incoming ? kGreen : kRed;
              return GestureDetector(
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
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name, style: ts(18).copyWith(height: 1.2)),
                          const SizedBox(height: 4),
                          // المستقبَلة: أخضر مع (+)، والمرسلة: أحمر مع (-)
                          Text(
                            '${t.incoming ? '+' : '-'} '
                            '${amountLabel(t.amount, t.currency)}',
                            style: ts(19, color: color).copyWith(height: 1.2),
                          ),
                        ],
                      ),
                      const Spacer(),
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
        );
      },
    );
  }
}

/// شاشة الوصل: الوصل في الثلث العلوي، وباقي الصفحة بيضاء، وفي الأسفل زر
/// "تصدير" الذي ينشئ ملف PDF ويفتح قائمة المشاركة (اختر واتساب).
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
  static const _exportBlue = Color(0xFF0277BD); // أزرق سماوي داكن
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
      final file = File('${dir.path}/receipt_$opNo.pdf');
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
              // الوصل في الثلث العلوي من الشاشة (يصغر تلقائياً إن لزم)
              SizedBox(
                height: size.height / 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: size.width - 10,
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
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _exportBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _exportBlue.withOpacity(0.6),
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
                  opacity: 0.10,
                  child: Image.asset(
                    'assets/images/logo_watermark.png',
                    width: 190,
                    height: 170,
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
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
              _row('الملاحظة:', const SizedBox.shrink()),
              const SizedBox(height: 10),
              Container(height: 4, color: _bar),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
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
    name = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: incoming ? 'اسم المرسل' : 'اسم المستقبل',
        hint: incoming ? 'اكتب اسم المرسل' : 'اكتب اسم المستقبل',
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
      action: incoming ? 'استقبال' : 'إرسال',
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    ),
  );
  if (raw == null || !context.mounted) return;

  final amount = double.tryParse(toEnglishDigits(raw.trim())) ?? 0;
  final err = incoming
      ? w.receive(name.trim(), amount)
      : w.send(name.trim(), amount);
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
          CircleAvatar(
            radius: 32,
            backgroundColor: incoming ? kGreen : kTeal,
            child: const Icon(Icons.check_rounded, size: 42, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(incoming ? 'تم الاستقبال' : 'تم التحويل', style: ts(22)),
          const SizedBox(height: 6),
          Text(
            incoming
                ? '${amountLabel(amount, cur)} من ${name!.trim()}'
                : '${amountLabel(amount, cur)} إلى ${name!.trim()}',
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
              Text(
                widget.wallet.ownerName.isEmpty
                    ? 'حسابي'
                    : widget.wallet.ownerName,
                style: ts(22),
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
