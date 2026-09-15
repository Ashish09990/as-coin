import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ASCoinApp());
}

// ============================================================
// AS COIN CONFIGURATION
// ============================================================

class ASConfig {
  // IMPORTANT:
  // Replace this with your deployed HTTPS backend URL.
  // Example: https://api.example.com
  static const String backendUrl = '';

  static const String appName = 'AS COIN';
  static const String symbol = 'ASC';

  static const int maxSupply = 21000000;

  // Initial sale example:
  // 50 USDT = 5,000 ASC
  static const double packageUsdt = 50.0;
  static const double packageAsc = 5000.0;

  static const double kycFeeUsdt = 1.0;

  static const String usdtNetwork = 'TRC20 (TRON)';

  // IMPORTANT:
  // Use only an address controlled by your production payment system.
  static const String usdtDepositAddress =
      'TYskeHD53kcs9ksb5ymBGubtJAJpQPkND2';

  static const int verificationSeconds = 300;
}

// ============================================================
// MODELS
// ============================================================

class UserSession {
  final String token;
  final String userId;
  final String? phone;
  final String? email;
  final String? telegramId;
  final double balance;
  final String kycStatus;
  final String? walletAddress;

  UserSession({
    required this.token,
    required this.userId,
    this.phone,
    this.email,
    this.telegramId,
    required this.balance,
    required this.kycStatus,
    this.walletAddress,
  });

  factory UserSession.fromJson(Map<String, dynamic> j) {
    return UserSession(
      token: j['token']?.toString() ?? '',
      userId: j['user_id']?.toString() ?? '',
      phone: j['phone']?.toString(),
      email: j['email']?.toString(),
      telegramId: j['telegram_id']?.toString(),
      balance: double.tryParse('${j['balance'] ?? 0}') ?? 0,
      kycStatus: j['kyc_status']?.toString() ?? 'Pending',
      walletAddress: j['wallet_address']?.toString(),
    );
  }
}

class Purchase {
  final String id;
  final double usdt;
  final double asc;
  final String status;
  final String? txHash;
  final DateTime? createdAt;

  Purchase({
    required this.id,
    required this.usdt,
    required this.asc,
    required this.status,
    this.txHash,
    this.createdAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> j) {
    return Purchase(
      id: j['id']?.toString() ?? '',
      usdt: double.tryParse('${j['usdt'] ?? 0}') ?? 0,
      asc: double.tryParse('${j['asc'] ?? 0}') ?? 0,
      status: j['status']?.toString() ?? 'Pending',
      txHash: j['tx_hash']?.toString(),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
    );
  }
}

class ASCTx {
  final String id;
  final String type;
  final double amount;
  final String address;
  final String status;
  final String? txHash;
  final DateTime? createdAt;

  ASCTx({
    required this.id,
    required this.type,
    required this.amount,
    required this.address,
    required this.status,
    this.txHash,
    this.createdAt,
  });

  factory ASCTx.fromJson(Map<String, dynamic> j) {
    return ASCTx(
      id: j['id']?.toString() ?? '',
      type: j['type']?.toString() ?? 'Transaction',
      amount: double.tryParse('${j['amount'] ?? 0}') ?? 0,
      address: j['address']?.toString() ?? '',
      status: j['status']?.toString() ?? 'Pending',
      txHash: j['tx_hash']?.toString(),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
    );
  }
}

// ============================================================
// API
// ============================================================

class APIException implements Exception {
  final String message;

  APIException(this.message);

  @override
  String toString() => message;
}

class ASApi {
  static String get base => ASConfig.backendUrl.trim();

  static bool get configured => base.isNotEmpty;

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (!configured) {
      throw APIException('Backend connection is not configured.');
    }

    final uri = Uri.parse('$base$path');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;

    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: headers);
      } else {
        response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      }
    } catch (_) {
      throw APIException(
        'Unable to connect to the AS COIN server. Please try again.',
      );
    }

    Map<String, dynamic> data = {};

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw APIException(
        data['message']?.toString() ??
            data['detail']?.toString() ??
            'Server request failed.',
      );
    }

    return data;
  }

  // ---------------- AUTH ----------------

  static Future<String> requestPhoneOtp(String phone) async {
    final data = await _request(
      'POST',
      '/auth/request-otp',
      body: {'phone': phone},
    );

    return data['message']?.toString() ??
        'Verification code sent successfully.';
  }

  static Future<UserSession> verifyPhoneOtp(
    String phone,
    String otp,
  ) async {
    final data = await _request(
      'POST',
      '/auth/verify-otp',
      body: {
        'phone': phone,
        'otp': otp,
      },
    );

    return UserSession.fromJson(data);
  }

  static Future<UserSession> googleLogin(String idToken) async {
    final data = await _request(
      'POST',
      '/auth/google',
      body: {
        'id_token': idToken,
      },
    );

    return UserSession.fromJson(data);
  }

  static Future<UserSession> telegramLogin(String telegramData) async {
    final data = await _request(
      'POST',
      '/auth/telegram',
      body: {
        'telegram_data': telegramData,
      },
    );

    return UserSession.fromJson(data);
  }

  // ---------------- USER ----------------

  static Future<UserSession> me(String token) async {
    final data = await _request(
      'GET',
      '/me',
      token: token,
    );

    return UserSession(
      token: token,
      userId: data['user_id']?.toString() ?? '',
      phone: data['phone']?.toString(),
      email: data['email']?.toString(),
      telegramId: data['telegram_id']?.toString(),
      balance: double.tryParse('${data['balance'] ?? 0}') ?? 0,
      kycStatus: data['kyc_status']?.toString() ?? 'Pending',
      walletAddress: data['wallet_address']?.toString(),
    );
  }

  // ---------------- KYC ----------------

  static Future<Map<String, dynamic>> createKycPayment(
    String token,
  ) async {
    return _request(
      'POST',
      '/kyc/payment',
      token: token,
      body: {
        'amount_usdt': ASConfig.kycFeeUsdt,
        'network': ASConfig.usdtNetwork,
      },
    );
  }

  static Future<Map<String, dynamic>> kycStatus(
    String token,
  ) async {
    return _request(
      'GET',
      '/kyc/status',
      token: token,
    );
  }

  // ---------------- PURCHASE ----------------

  static Future<Purchase> createPurchase(
    String token,
  ) async {
    final data = await _request(
      'POST',
      '/purchases/create',
      token: token,
      body: {
        'amount_usdt': ASConfig.packageUsdt,
        'amount_asc': ASConfig.packageAsc,
        'network': ASConfig.usdtNetwork,
      },
    );

    return Purchase.fromJson(data);
  }

  static Future<Purchase> purchaseStatus(
    String token,
    String purchaseId,
  ) async {
    final data = await _request(
      'GET',
      '/purchases/$purchaseId',
      token: token,
    );

    return Purchase.fromJson(data);
  }

  // ---------------- WALLET ----------------

  static Future<List<ASCTx>> transactions(
    String token,
  ) async {
    final data = await _request(
      'GET',
      '/transactions',
      token: token,
    );

    final list = data['transactions'];

    if (list is! List) {
      return [];
    }

    return list
        .whereType<Map<String, dynamic>>()
        .map(ASCTx.fromJson)
        .toList();
  }

  static Future<Map<String, dynamic>> sendAsc(
    String token,
    String address,
    double amount,
  ) async {
    return _request(
      'POST',
      '/wallet/send',
      token: token,
      body: {
        'address': address,
        'amount': amount,
      },
    );
  }
}

// ============================================================
// LOCAL SESSION
// ============================================================

class SessionStore {
  static const String key = 'asc_token';

  static Future<void> save(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, token);
  }

  static Future<String?> read() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(key);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(key);
  }
}

// ============================================================
// APP
// ============================================================

class ASCoinApp extends StatelessWidget {
  const ASCoinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: ASConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101116),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB9BEFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const StartupPage(),
    );
  }
}

// ============================================================
// STARTUP
// ============================================================

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.delayed(const Duration(milliseconds: 700));

    final token = await SessionStore.read();

    if (!mounted) return;

    if (token == null || token.isEmpty || !ASApi.configured) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginPage(),
        ),
      );
      return;
    }

    try {
      final session = await ASApi.me(token);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(session: session),
        ),
      );
    } catch (_) {
      await SessionStore.clear();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet,
              size: 72,
            ),
            SizedBox(height: 18),
            Text(
              'AS COIN',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Secure ASC Network',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 25),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LOGIN
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  String countryCode = '+91';
  bool otpSent = false;
  bool loading = false;

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  void message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> sendOtp() async {
    if (!ASApi.configured) {
      message('Backend connection is not configured.');
      return;
    }

    final number = phoneController.text.trim();

    if (number.length < 6) {
      message('Enter a valid mobile number.');
      return;
    }

    setState(() => loading = true);

    try {
      final fullPhone = '$countryCode$number';

      final result = await ASApi.requestPhoneOtp(fullPhone);

      if (!mounted) return;

      setState(() {
        otpSent = true;
        loading = false;
      });

      message(result);
    } catch (e) {
      setState(() => loading = false);
      message(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> verifyOtp() async {
    final number = phoneController.text.trim();
    final otp = otpController.text.trim();

    if (otp.length < 4) {
      message('Enter the verification code.');
      return;
    }

    setState(() => loading = true);

    try {
      final session = await ASApi.verifyPhoneOtp(
        '$countryCode$number',
        otp,
      );

      await SessionStore.save(session.token);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(session: session),
        ),
      );
    } catch (e) {
      setState(() => loading = false);
      message(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> googleLogin() async {
    message(
      'Google Sign-In requires the production Google authentication configuration.',
    );
  }

  Future<void> telegramLogin() async {
    message(
      'Telegram verification requires the production Telegram Gateway configuration.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                children: [
                  const SizedBox(height: 25),

                  const CircleAvatar(
                    radius: 62,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.attach_money,
                      size: 72,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(height: 25),

                  const Text(
                    'AS COIN',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Secure ASC Network',
                    style: TextStyle(
                      fontSize: 17,
                      color: Colors.white70,
                    ),
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : googleLogin,
                      icon: const Icon(Icons.account_circle),
                      label: const Text('Continue with Google'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : telegramLogin,
                      icon: const Icon(Icons.send),
                      label: const Text('Continue with Telegram'),
                    ),
                  ),

                  const SizedBox(height: 25),

                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('OR'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: 25),

                  Row(
                    children: [
                      SizedBox(
                        width: 105,
                        child: DropdownButtonFormField<String>(
                          value: countryCode,
                          decoration: const InputDecoration(
                            labelText: 'Code',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: '+91',
                              child: Text('+91'),
                            ),
                            DropdownMenuItem(
                              value: '+1',
                              child: Text('+1'),
                            ),
                            DropdownMenuItem(
                              value: '+44',
                              child: Text('+44'),
                            ),
                            DropdownMenuItem(
                              value: '+61',
                              child: Text('+61'),
                            ),
                            DropdownMenuItem(
                              value: '+971',
                              child: Text('+971'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => countryCode = v);
                            }
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Mobile number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  if (otpSent)
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        border: OutlineInputBorder(),
                      ),
                    ),

                  if (otpSent) const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: loading
                          ? null
                          : (otpSent ? verifyOtp : sendOtp),
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              otpSent
                                  ? 'VERIFY CODE'
                                  : 'SEND VERIFICATION CODE',
                            ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'One verified identity = one AS COIN account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),

                  if (!ASApi.configured) ...[
                    const SizedBox(height: 30),
                    const Text(
                      'Backend connection is not configured.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOME
// ============================================================

class HomePage extends StatefulWidget {
  final UserSession session;

  const HomePage({
    super.key,
    required this.session,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late UserSession session;

  @override
  void initState() {
    super.initState();
    session = widget.session;
  }

  Future<void> refresh() async {
    try {
      final updated = await ASApi.me(session.token);

      if (!mounted) return;

      setState(() => session = updated);
    } catch (e) {
      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void showMessage(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AS COIN'),
        actions: [
          IconButton(
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ASC Balance',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${session.balance.toStringAsFixed(2)} ASC',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: _HomeButton(
                    icon: Icons.shopping_cart,
                    title: 'Buy ASC',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PurchasePage(
                            session: session,
                          ),
                        ),
                      );
                      await refresh();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HomeButton(
                    icon: Icons.account_balance_wallet,
                    title: 'Wallet',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WalletPage(
                            session: session,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _HomeButton(
                    icon: Icons.verified_user,
                    title: 'KYC',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => KycPage(
                            session: session,
                          ),
                        ),
                      );
                      await refresh();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HomeButton(
                    icon: Icons.history,
                    title: 'History',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryPage(
                            session: session,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            Card(
              child: ListTile(
                leading: const Icon(Icons.security),
                title: const Text('Account Security'),
                subtitle: Text(
                  'KYC: ${session.kycStatus}',
                ),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2),
                title: const Text('Maximum Supply'),
                subtitle: Text(
                  '${ASConfig.maxSupply} ASC',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _HomeButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 25,
            horizontal: 12,
          ),
          child: Column(
            children: [
              Icon(icon, size: 34),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PURCHASE
// ============================================================

class PurchasePage extends StatefulWidget {
  final UserSession session;

  const PurchasePage({
    super.key,
    required this.session,
  });

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  Purchase? purchase;
  Timer? timer;
  int secondsLeft = ASConfig.verificationSeconds;
  bool creating = false;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> createPayment() async {
    setState(() => creating = true);

    try {
      final p = await ASApi.createPurchase(widget.session.token);

      if (!mounted) return;

      setState(() {
        purchase = p;
        creating = false;
        secondsLeft = ASConfig.verificationSeconds;
      });

      startVerification();
    } catch (e) {
      setState(() => creating = false);
      message(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void startVerification() {
    timer?.cancel();

    timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) async {
        if (purchase == null) return;

        if (secondsLeft > 0) {
          setState(() {
            secondsLeft -= 10;
            if (secondsLeft < 0) secondsLeft = 0;
          });
        }

        try {
          final updated = await ASApi.purchaseStatus(
            widget.session.token,
            purchase!.id,
          );

          if (!mounted) return;

          setState(() => purchase = updated);

          if (updated.status.toLowerCase() == 'confirmed' ||
              updated.status.toLowerCase() == 'completed') {
            timer?.cancel();

            message(
              'Payment verified. ASC has been credited.',
            );
          }
        } catch (_) {
          // Keep checking.
        }
      },
    );
  }

  String timeText() {
    final m = secondsLeft ~/ 60;
    final s = secondsLeft % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = purchase;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buy ASC'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'ASC Purchase',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _info('Payment', '50 USDT'),
                  _info('ASC Allocation', '5,000 ASC'),
                  _info('Network', ASConfig.usdtNetwork),

                  const Divider(height: 30),

                  const Text(
                    'Send exactly 50 USDT using TRC20.',
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),

                  QrImageView(
                    data: ASConfig.usdtDepositAddress,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Deposit Address',
                    style: TextStyle(
                      color: Colors.white60,
                    ),
                  ),

                  const SizedBox(height: 8),

                  SelectableText(
                    ASConfig.usdtDepositAddress,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 15),

                  OutlinedButton.icon(
                    onPressed: () {
                      // Clipboard can be added if desired.
                      message('Select and copy the address above.');
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('COPY ADDRESS'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          if (p == null)
            SizedBox(
              height: 55,
              child: FilledButton(
                onPressed: creating ? null : createPayment,
                child: creating
                    ? const CircularProgressIndicator()
                    : const Text('I HAVE MADE THE PAYMENT'),
              ),
            ),

          if (p != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(
                      Icons.sync,
                      size: 45,
                    ),
                    const SizedBox(height: 12),

                    const Text(
                      'Payment Verification',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Status: ${p.status}',
                      style: const TextStyle(fontSize: 17),
                    ),

                    const SizedBox(height: 12),

                    if (p.status.toLowerCase() == 'pending')
                      Text(
                        'Automatic verification: up to ${timeText()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                        ),
                      ),

                    if (p.txHash != null &&
                        p.txHash!.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      const Text(
                        'Transaction',
                        style: TextStyle(
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        p.txHash!,
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 20),

                    const Text(
                      'A payment screenshot may be uploaded for support records, '
                      'but ASC will only be credited after blockchain verification.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScannerPage(
                      title: 'Scan Payment QR',
                      onScanned: (value) {
                        Navigator.pop(context);
                        message(
                          'QR detected. Blockchain verification remains required.',
                        );
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('SCAN QR'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _info(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// KYC
// ============================================================

class KycPage extends StatefulWidget {
  final UserSession session;

  const KycPage({
    super.key,
    required this.session,
  });

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  String status = 'Pending';
  bool loading = false;

  @override
  void initState() {
    super.initState();
    loadStatus();
  }

  void message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> loadStatus() async {
    try {
      final data = await ASApi.kycStatus(
        widget.session.token,
      );

      if (!mounted) return;

      setState(() {
        status = data['status']?.toString() ?? 'Pending';
      });
    } catch (_) {}
  }

  Future<void> payKyc() async {
    setState(() => loading = true);

    try {
      final data = await ASApi.createKycPayment(
        widget.session.token,
      );

      if (!mounted) return;

      setState(() => loading = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => KycPaymentPage(
            session: widget.session,
            paymentData: data,
          ),
        ),
      );
    } catch (e) {
      setState(() => loading = false);

      message(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KYC Verification'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(
                    Icons.verified_user,
                    size: 65,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'KYC Status',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          if (status.toLowerCase() != 'verified')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'Standard KYC Fee',
                      style: TextStyle(fontSize: 17),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1 USDT',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'TRC20 (TRON)',
                      style: TextStyle(
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: loading ? null : payKyc,
                        child: loading
                            ? const CircularProgressIndicator()
                            : const Text('START KYC'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// KYC PAYMENT
// ============================================================

class KycPaymentPage extends StatefulWidget {
  final UserSession session;
  final Map<String, dynamic> paymentData;

  const KycPaymentPage({
    super.key,
    required this.session,
    required this.paymentData,
  });

  @override
  State<KycPaymentPage> createState() => _KycPaymentPageState();
}

class _KycPaymentPageState extends State<KycPaymentPage> {
  Timer? timer;
  int seconds = 300;
  String status = 'Pending';

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => check(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> check() async {
    try {
      final data = await ASApi.kycStatus(
        widget.session.token,
      );

      if (!mounted) return;

      setState(() {
        status = data['status']?.toString() ?? status;
        seconds -= 10;
        if (seconds < 0) seconds = 0;
      });

      if (status.toLowerCase() == 'verified') {
        timer?.cancel();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final address =
        widget.paymentData['deposit_address']?.toString() ??
            ASConfig.usdtDepositAddress;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KYC Payment'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'KYC Payment',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    'Amount',
                    style: TextStyle(color: Colors.white60),
                  ),

                  const Text(
                    '1 USDT',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text('TRC20 (TRON)'),

                  const SizedBox(height: 20),

                  QrImageView(
                    data: address,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),

                  const SizedBox(height: 18),

                  SelectableText(
                    address,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'Verification status: $status',
                    style: const TextStyle(
                      fontSize: 18,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'The system will automatically verify the blockchain payment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WALLET
// ============================================================

class WalletPage extends StatelessWidget {
  final UserSession session;

  const WalletPage({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final address = session.walletAddress;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ASC Wallet'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 65,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'Available Balance',
                    style: TextStyle(
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${session.balance.toStringAsFixed(2)} ASC',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 15),

          Card(
            child: ListTile(
              title: const Text('Wallet Address'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  address == null || address.isEmpty
                      ? 'Wallet address will be provided by the backend.'
                      : address,
                ),
              ),
            ),
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: _WalletAction(
                  icon: Icons.call_received,
                  title: 'Receive',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceivePage(
                          session: session,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WalletAction(
                  icon: Icons.call_made,
                  title: 'Send',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SendPage(
                          session: session,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistoryPage(
                      session: session,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.history),
              label: const Text('TRANSACTION HISTORY'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _WalletAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon),
            const SizedBox(height: 7),
            Text(title),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// RECEIVE
// ============================================================

class ReceivePage extends StatelessWidget {
  final UserSession session;

  const ReceivePage({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final address = session.walletAddress;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive ASC'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (address == null || address.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Your ASC wallet address is not available yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else ...[
            const Text(
              'Scan to receive ASC',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            Center(
              child: QrImageView(
                data: address,
                size: 260,
                backgroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'ASC Wallet Address',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
              ),
            ),

            const SizedBox(height: 8),

            SelectableText(
              address,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Select and copy the wallet address above.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('COPY ADDRESS'),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// SEND
// ============================================================

class SendPage extends StatefulWidget {
  final UserSession session;

  const SendPage({
    super.key,
    required this.session,
  });

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final addressController = TextEditingController();
  final amountController = TextEditingController();

  bool loading = false;

  @override
  void dispose() {
    addressController.dispose();
    amountController.dispose();
    super.dispose();
  }

  void message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> send() async {
    final address = addressController.text.trim();
    final amount = double.tryParse(
      amountController.text.trim(),
    );

    if (address.isEmpty) {
      message('Enter the recipient wallet address.');
      return;
    }

    if (amount == null || amount <= 0) {
      message('Enter a valid ASC amount.');
      return;
    }

    if (amount > widget.session.balance) {
      message('Insufficient ASC balance.');
      return;
    }

    setState(() => loading = true);

    try {
      final data = await ASApi.sendAsc(
        widget.session.token,
        address,
        amount,
      );

      if (!mounted) return;

      setState(() => loading = false);

      message(
        data['message']?.toString() ??
            'ASC transfer submitted successfully.',
      );
    } catch (e) {
      setState(() => loading = false);

      message(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send ASC'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: addressController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Recipient wallet address',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 15),

          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScannerPage(
                    title: 'Scan ASC Address',
                    onScanned: (value) {
                      addressController.text = value;
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('SCAN QR'),
          ),

          const SizedBox(height: 15),

          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'ASC amount',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 25),

          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: loading ? null : send,
              child: loading
                  ? const CircularProgressIndicator()
                  : const Text('SEND ASC'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// QR SCANNER
// ============================================================

class ScannerPage extends StatefulWidget {
  final String title;
  final ValueChanged<String> onScanned;

  const ScannerPage({
    super.key,
    required this.title,
    required this.onScanned,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (scanned) return;

          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;

            if (value != null && value.isNotEmpty) {
              scanned = true;
              widget.onScanned(value);
              break;
            }
          }
        },
      ),
    );
  }
}

// ============================================================
// HISTORY
// ============================================================

class HistoryPage extends StatefulWidget {
  final UserSession session;

  const HistoryPage({
    super.key,
    required this.session,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool loading = true;
  List<ASCTx> transactions = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await ASApi.transactions(
        widget.session.token,
      );

      if (!mounted) return;

      setState(() {
        transactions = data;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : transactions.isEmpty
              ? const Center(
                  child: Text('No transactions yet.'),
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.builder(
                    itemCount: transactions.length,
                    itemBuilder: (_, index) {
                      final tx = transactions[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: Icon(
                            tx.type.toLowerCase() == 'receive'
                                ? Icons.call_received
                                : Icons.call_made,
                          ),
                          title: Text(
                            '${tx.amount.toStringAsFixed(2)} ASC',
                          ),
                          subtitle: Text(
                            '${tx.type}\n${tx.status}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
