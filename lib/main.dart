import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ASCoinApp());
}

// ============================================================
// CONFIG
// ============================================================

class Config {
  static const String appName = 'AS COIN';
  static const String symbol = 'ASC';

  // Leave empty until backend is deployed.
  static const String backendUrl = '';

  static const String network = 'TRC20 (TRON)';

  static const double packageUsdt = 50.0;
  static const double packageAsc = 5000.0;

  static const double kycFee = 1.0;

  static const int maxSupply = 21000000;

  // This address will be supplied by backend in production.
  static const String fallbackUsdtAddress = '';

  static bool get backendReady => backendUrl.trim().isNotEmpty;
}

// ============================================================
// SESSION
// ============================================================

class Session {
  final String token;
  final String userId;
  final String? email;
  final String? phone;
  final double balance;
  final String kycStatus;
  final String? walletAddress;

  const Session({
    required this.token,
    required this.userId,
    this.email,
    this.phone,
    required this.balance,
    required this.kycStatus,
    this.walletAddress,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      token: json['token']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      balance:
          double.tryParse('${json['balance'] ?? 0}') ?? 0,
      kycStatus:
          json['kyc_status']?.toString() ?? 'Pending',
      walletAddress:
          json['wallet_address']?.toString(),
    );
  }

  Session copyWith({
    String? token,
    String? userId,
    String? email,
    String? phone,
    double? balance,
    String? kycStatus,
    String? walletAddress,
  }) {
    return Session(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      balance: balance ?? this.balance,
      kycStatus: kycStatus ?? this.kycStatus,
      walletAddress:
          walletAddress ?? this.walletAddress,
    );
  }
}

// ============================================================
// PURCHASE
// ============================================================

class Purchase {
  final String id;
  final double usdt;
  final double asc;
  final String status;
  final String? txHash;
  final String? depositAddress;

  const Purchase({
    required this.id,
    required this.usdt,
    required this.asc,
    required this.status,
    this.txHash,
    this.depositAddress,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    return Purchase(
      id: json['id']?.toString() ?? '',
      usdt:
          double.tryParse('${json['usdt'] ?? 0}') ?? 0,
      asc:
          double.tryParse('${json['asc'] ?? 0}') ?? 0,
      status:
          json['status']?.toString() ?? 'Pending',
      txHash:
          json['tx_hash']?.toString(),
      depositAddress:
          json['deposit_address']?.toString(),
    );
  }
}

// ============================================================
// TRANSACTION
// ============================================================

class WalletTransaction {
  final String id;
  final String type;
  final double amount;
  final String address;
  final String status;
  final String? txHash;
  final String? date;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.address,
    required this.status,
    this.txHash,
    this.date,
  });

  factory WalletTransaction.fromJson(
    Map<String, dynamic> json,
  ) {
    return WalletTransaction(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Transaction',
      amount:
          double.tryParse('${json['amount'] ?? 0}') ?? 0,
      address:
          json['address']?.toString() ?? '',
      status:
          json['status']?.toString() ?? 'Pending',
      txHash:
          json['tx_hash']?.toString(),
      date:
          json['created_at']?.toString(),
    );
  }
}

// ============================================================
// API
// ============================================================

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}

class Api {
  static String get base => Config.backendUrl.trim();

  static Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (base.isEmpty) {
      throw ApiException(
        'Backend connection is not configured.',
      );
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
        response = await http.get(
          uri,
          headers: headers,
        );
      } else {
        response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      }
    } catch (_) {
      throw ApiException(
        'Unable to connect to AS COIN server.',
      );
    }

    Map<String, dynamic> data = {};

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    } catch (_) {}

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw ApiException(
        data['detail']?.toString() ??
            data['message']?.toString() ??
            'Server request failed.',
      );
    }

    return data;
  }

  static Future<String> requestOtp(
    String phone,
  ) async {
    final data = await request(
      'POST',
      '/auth/request-otp',
      body: {
        'phone': phone,
      },
    );

    return data['message']?.toString() ??
        'Verification code sent.';
  }

  static Future<Session> verifyOtp(
    String phone,
    String otp,
  ) async {
    final data = await request(
      'POST',
      '/auth/verify-otp',
      body: {
        'phone': phone,
        'otp': otp,
      },
    );

    return Session.fromJson(data);
  }

  static Future<Session> googleLogin(
    String idToken,
  ) async {
    final data = await request(
      'POST',
      '/auth/google',
      body: {
        'id_token': idToken,
      },
    );

    return Session.fromJson(data);
  }

  static Future<Session> me(
    String token,
  ) async {
    final data = await request(
      'GET',
      '/me',
      token: token,
    );

    return Session(
      token: token,
      userId:
          data['user_id']?.toString() ?? '',
      email:
          data['email']?.toString(),
      phone:
          data['phone']?.toString(),
      balance:
          double.tryParse(
                '${data['balance'] ?? 0}',
              ) ??
              0,
      kycStatus:
          data['kyc_status']?.toString() ??
              'Pending',
      walletAddress:
          data['wallet_address']?.toString(),
    );
  }

  static Future<Purchase> createPurchase(
    String token,
  ) async {
    final data = await request(
      'POST',
      '/purchases/create',
      token: token,
    );

    return Purchase.fromJson(data);
  }

  static Future<Purchase> purchaseStatus(
    String token,
    String id,
  ) async {
    final data = await request(
      'GET',
      '/purchases/$id',
      token: token,
    );

    return Purchase.fromJson(data);
  }

  static Future<Map<String, dynamic>> kycPayment(
    String token,
  ) async {
    return request(
      'POST',
      '/kyc/payment',
      token: token,
    );
  }

  static Future<Map<String, dynamic>> kycStatus(
    String token,
  ) async {
    return request(
      'GET',
      '/kyc/status',
      token: token,
    );
  }

  static Future<List<WalletTransaction>> history(
    String token,
  ) async {
    final data = await request(
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
        .map(
          WalletTransaction.fromJson,
        )
        .toList();
  }

  static Future<Map<String, dynamic>> send(
    String token,
    String address,
    double amount,
  ) async {
    return request(
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
// LOCAL TOKEN STORAGE
// ============================================================

class TokenStore {
  static const String key = 'as_coin_token';

  static Future<void> save(
    String token,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      key,
      token,
    );
  }

  static Future<String?> get() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(key);
  }

  static Future<void> clear() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.remove(key);
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
      title: Config.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor:
            const Color(0xFF101116),
        colorScheme:
            ColorScheme.fromSeed(
          seedColor:
              const Color(0xFFB7BEFF),
          brightness: Brightness.dark,
        ),
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
  State<StartupPage> createState() =>
      _StartupPageState();
}

class _StartupPageState
    extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    await Future.delayed(
      const Duration(milliseconds: 700),
    );

    final token =
        await TokenStore.get();

    if (!mounted) return;

    if (token == null ||
        token.isEmpty ||
        !Config.backendReady) {
      goLogin();
      return;
    }

    try {
      final session =
          await Api.me(token);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              HomePage(session: session),
        ),
      );
    } catch (_) {
      await TokenStore.clear();

      if (!mounted) return;

      goLogin();
    }
  }

  void goLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 55,
              backgroundColor:
                  Colors.white,
              child: Icon(
                Icons.attach_money,
                size: 65,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'AS COIN',
              style: TextStyle(
                fontSize: 30,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Secure ASC Network',
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
  State<LoginPage> createState() =>
      _LoginPageState();
}

class _LoginPageState
    extends State<LoginPage> {
  final phone =
      TextEditingController();

  final otp =
      TextEditingController();

  String countryCode = '+91';

  bool otpSent = false;
  bool loading = false;
  bool googleLoading = false;

  @override
  void dispose() {
    phone.dispose();
    otp.dispose();
    super.dispose();
  }

  void showMessage(
    String text,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  Future<void> sendOtp() async {
    if (!Config.backendReady) {
      showMessage(
        'Backend connection is not configured.',
      );
      return;
    }

    final number =
        phone.text.trim();

    if (number.length < 6) {
      showMessage(
        'Enter a valid mobile number.',
      );
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final message =
          await Api.requestOtp(
        '$countryCode$number',
      );

      if (!mounted) return;

      setState(() {
        otpSent = true;
        loading = false;
      });

      showMessage(message);
    } catch (e) {
      setState(() {
        loading = false;
      });

      showMessage(
        cleanError(e),
      );
    }
  }

  Future<void> verifyOtp() async {
    final number =
        phone.text.trim();

    final code =
        otp.text.trim();

    if (code.length < 4) {
      showMessage(
        'Enter the verification code.',
      );
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final session =
          await Api.verifyOtp(
        '$countryCode$number',
        code,
      );

      await TokenStore.save(
        session.token,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              HomePage(
            session: session,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        loading = false;
      });

      showMessage(
        cleanError(e),
      );
    }
  }

  Future<void> googleSignIn() async {
    if (!Config.backendReady) {
      showMessage(
        'Backend connection is not configured.',
      );
      return;
    }

    setState(() {
      googleLoading = true;
    });

    try {
      final signIn =
          GoogleSignIn.instance;

      await signIn.initialize();

      final account =
          await signIn.authenticate();

      final authentication =
          account.authentication;

      final idToken =
          authentication.idToken;

      if (idToken == null ||
          idToken.isEmpty) {
        throw ApiException(
          'Google ID token was not received.',
        );
      }

      final session =
          await Api.googleLogin(
        idToken,
      );

      await TokenStore.save(
        session.token,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              HomePage(
            session: session,
          ),
        ),
      );
    } catch (e) {
      showMessage(
        cleanError(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          googleLoading = false;
        });
      }
    }
  }

  String cleanError(
    Object error,
  ) {
    return error
        .toString()
        .replaceFirst(
          'Exception: ',
          '',
        );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 520,
              ),
              child: Column(
                children: [
                  const SizedBox(
                    height: 20,
                  ),

                  const CircleAvatar(
                    radius: 60,
                    backgroundColor:
                        Colors.white,
                    child: Icon(
                      Icons.attach_money,
                      size: 70,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(
                    height: 22,
                  ),

                  const Text(
                    'AS COIN',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 7,
                  ),

                  const Text(
                    'Secure ASC Network',
                    style: TextStyle(
                      fontSize: 17,
                      color:
                          Colors.white70,
                    ),
                  ),

                  const SizedBox(
                    height: 35,
                  ),

                  SizedBox(
                    width:
                        double.infinity,
                    height: 52,
                    child:
                        OutlinedButton.icon(
                      onPressed:
                          googleLoading
                              ? null
                              : googleSignIn,
                      icon: googleLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Icon(
                              Icons
                                  .account_circle,
                            ),
                      label:
                          const Text(
                        'Continue with Google',
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  SizedBox(
                    width:
                        double.infinity,
                    height: 52,
                    child:
                        OutlinedButton.icon(
                      onPressed:
                          Config.backendReady
                              ? () {
                                  showMessage(
                                    'Telegram verification is available through the configured backend.',
                                  );
                                }
                              : null,
                      icon: const Icon(
                        Icons.send,
                      ),
                      label:
                          const Text(
                        'Continue with Telegram',
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 25,
                  ),

                  const Row(
                    children: [
                      Expanded(
                        child: Divider(),
                      ),
                      Padding(
                        padding:
                            EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        child:
                            Text('OR'),
                      ),
                      Expanded(
                        child: Divider(),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 25,
                  ),

                  Row(
                    children: [
                      SizedBox(
                        width: 105,
                        child:
                            DropdownButtonFormField<
                                String>(
                          initialValue:
                              countryCode,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Code',
                            border:
                                OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: '+91',
                              child:
                                  Text('+91'),
                            ),
                            DropdownMenuItem(
                              value: '+1',
                              child:
                                  Text('+1'),
                            ),
                            DropdownMenuItem(
                              value: '+44',
                              child:
                                  Text('+44'),
                            ),
                            DropdownMenuItem(
                              value: '+61',
                              child:
                                  Text('+61'),
                            ),
                            DropdownMenuItem(
                              value: '+971',
                              child:
                                  Text('+971'),
                            ),
                          ],
                          onChanged:
                              (value) {
                            if (value !=
                                null) {
                              setState(() {
                                countryCode =
                                    value;
                              });
                            }
                          },
                        ),
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      Expanded(
                        child:
                            TextField(
                          controller:
                              phone,
                          keyboardType:
                              TextInputType
                                  .phone,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Mobile number',
                            border:
                                OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (otpSent) ...[
                    const SizedBox(
                      height: 16,
                    ),
                    TextField(
                      controller: otp,
                      keyboardType:
                          TextInputType
                              .number,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Verification code',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                  ],

                  const SizedBox(
                    height: 18,
                  ),

                  SizedBox(
                    width:
                        double.infinity,
                    height: 54,
                    child:
                        FilledButton(
                      onPressed:
                          loading
                              ? null
                              : otpSent
                                  ? verifyOtp
                                  : sendOtp,
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : Text(
                              otpSent
                                  ? 'VERIFY CODE'
                                  : 'SEND VERIFICATION CODE',
                            ),
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  const Text(
                    'One verified identity = one AS COIN account.',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color:
                          Colors.white60,
                    ),
                  ),

                  if (!Config
                      .backendReady) ...[
                    const SizedBox(
                      height: 25,
                    ),
                    const Text(
                      'Backend connection is not configured.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color:
                            Colors.orange,
                        fontWeight:
                            FontWeight.bold,
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
  final Session session;

  const HomePage({
    super.key,
    required this.session,
  });

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState
    extends State<HomePage> {
  late Session session;

  @override
  void initState() {
    super.initState();
    session = widget.session;
  }

  Future<void> refresh() async {
    try {
      final updated =
          await Api.me(
        session.token,
      );

      if (!mounted) return;

      setState(() {
        session = updated;
      });
    } catch (e) {
      showMessage(
        cleanError(e),
      );
    }
  }

  void showMessage(
    String text,
  ) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  String cleanError(
    Object error,
  ) {
    return error
        .toString()
        .replaceFirst(
          'Exception: ',
          '',
        );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('AS COIN'),
        actions: [
          IconButton(
            onPressed: refresh,
            icon:
                const Icon(Icons.refresh),
          ),
        ],
      ),
      body:
          RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding:
              const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Text(
                      'ASC Balance',
                      style: TextStyle(
                        color:
                            Colors.white60,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      '${session.balance.toStringAsFixed(2)} ASC',
                      style:
                          const TextStyle(
                        fontSize: 34,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            Row(
              children: [
                Expanded(
                  child: HomeTile(
                    icon:
                        Icons.shopping_cart,
                    title:
                        'Buy ASC',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PurchasePage(
                            session:
                                session,
                          ),
                        ),
                      );
                      refresh();
                    },
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: HomeTile(
                    icon: Icons.wallet,
                    title:
                        'Wallet',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              WalletPage(
                            session:
                                session,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 12,
            ),

            Row(
              children: [
                Expanded(
                  child: HomeTile(
                    icon:
                        Icons.verified_user,
                    title: 'KYC',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              KycPage(
                            session:
                                session,
                          ),
                        ),
                      );
                      refresh();
                    },
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: HomeTile(
                    icon:
                        Icons.history,
                    title:
                        'History',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              HistoryPage(
                            session:
                                session,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 20,
            ),

            Card(
              child: ListTile(
                leading:
                    const Icon(
                  Icons.verified_user,
                ),
                title:
                    const Text(
                  'KYC Status',
                ),
                subtitle:
                    Text(
                  session.kycStatus,
                ),
              ),
            ),

            Card(
              child: ListTile(
                leading:
                    const Icon(
                  Icons.inventory,
                ),
                title:
                    const Text(
                  'Maximum Supply',
                ),
                subtitle:
                    const Text(
                  '21,000,000 ASC',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeTile
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const HomeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            vertical: 25,
            horizontal: 10,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 34,
              ),
              const SizedBox(
                height: 10,
              ),
              Text(
                title,
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

class PurchasePage
    extends StatefulWidget {
  final Session session;

  const PurchasePage({
    super.key,
    required this.session,
  });

  @override
  State<PurchasePage> createState() =>
      _PurchasePageState();
}

class _PurchasePageState
    extends State<PurchasePage> {
  Purchase? purchase;
  Timer? timer;

  bool loading = false;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void message(
    String text,
  ) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  Future<void> startPurchase() async {
    setState(() {
      loading = true;
    });

    try {
      final result =
          await Api.createPurchase(
        widget.session.token,
      );

      if (!mounted) return;

      setState(() {
        purchase = result;
        loading = false;
      });

      startChecking();
    } catch (e) {
      setState(() {
        loading = false;
      });

      message(
        cleanError(e),
      );
    }
  }

  void startChecking() {
    timer?.cancel();

    timer = Timer.periodic(
      const Duration(
        seconds: 10,
      ),
      (_) => checkPayment(),
    );
  }

  Future<void> checkPayment() async {
    final current =
        purchase;

    if (current == null) {
      return;
    }

    try {
      final updated =
          await Api.purchaseStatus(
        widget.session.token,
        current.id,
      );

      if (!mounted) return;

      setState(() {
        purchase = updated;
      });

      if (updated.status
              .toLowerCase() ==
          'confirmed') {
        timer?.cancel();

        message(
          'Payment verified. ASC credited.',
        );
      }
    } catch (_) {}
  }

  String cleanError(
    Object error,
  ) {
    return error
        .toString()
        .replaceFirst(
          'Exception: ',
          '',
        );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final p = purchase;

    final address =
        p?.depositAddress ??
            Config.fallbackUsdtAddress;

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Buy ASC'),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'ASC Purchase',
                    style:
                        TextStyle(
                      fontSize: 25,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 18,
                  ),
                  info(
                    'Payment',
                    '50 USDT',
                  ),
                  info(
                    'ASC',
                    '5,000 ASC',
                  ),
                  info(
                    'Network',
                    'TRC20 (TRON)',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 15,
          ),

          if (address.isNotEmpty)
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'USDT Deposit',
                      style:
                          TextStyle(
                        fontSize: 20,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 15,
                    ),

                    QrImageView(
                      data: address,
                      size: 220,
                      backgroundColor:
                          Colors.white,
                    ),

                    const SizedBox(
                      height: 15,
                    ),

                    const Text(
                      'TRC20 (TRON)',
                      style:
                          TextStyle(
                        color:
                            Colors.white60,
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    SelectableText(
                      address,
                      textAlign:
                          TextAlign.center,
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: address,
                          ),
                        );

                        message(
                          'Address copied.',
                        );
                      },
                      icon:
                          const Icon(
                        Icons.copy,
                      ),
                      label:
                          const Text(
                        'COPY ADDRESS',
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(
            height: 15,
          ),

          if (p == null)
            SizedBox(
              height: 54,
              child:
                  FilledButton(
                onPressed:
                    loading
                        ? null
                        : startPurchase,
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth:
                              2,
                        ),
                      )
                    : const Text(
                        'I HAVE MADE THE PAYMENT',
                      ),
              ),
            ),

          if (p != null)
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(
                      Icons.sync,
                      size: 50,
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    const Text(
                      'Payment Verification',
                      style:
                          TextStyle(
                        fontSize: 21,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      'Status: ${p.status}',
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    const Text(
                      'The blockchain will be checked automatically. ASC is credited only after a valid payment is confirmed.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            Colors.white60,
                      ),
                    ),
                    if (p.txHash != null &&
                        p.txHash!
                            .isNotEmpty) ...[
                      const SizedBox(
                        height: 15,
                      ),
                      SelectableText(
                        p.txHash!,
                        textAlign:
                            TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget info(
    String a,
    String b,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(a),
          ),
          Text(
            b,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
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

class KycPage
    extends StatefulWidget {
  final Session session;

  const KycPage({
    super.key,
    required this.session,
  });

  @override
  State<KycPage> createState() =>
      _KycPageState();
}

class _KycPageState
    extends State<KycPage> {
  String status = 'Pending';
  bool loading = false;

  @override
  void initState() {
    super.initState();
    loadStatus();
  }

  Future<void> loadStatus() async {
    try {
      final data =
          await Api.kycStatus(
        widget.session.token,
      );

      if (!mounted) return;

      setState(() {
        status =
            data['status']
                    ?.toString() ??
                'Pending';
      });
    } catch (_) {}
  }

  Future<void> startKyc() async {
    setState(() {
      loading = true;
    });

    try {
      final data =
          await Api.kycPayment(
        widget.session.token,
      );

      if (!mounted) return;

      setState(() {
        loading = false;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              KycPaymentPage(
            data: data,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('KYC'),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(
                    Icons.verified_user,
                    size: 60,
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  const Text(
                    'KYC Status',
                    style:
                        TextStyle(
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    status,
                    style:
                        const TextStyle(
                      fontSize: 27,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 18,
          ),

          if (status.toLowerCase() !=
              'verified')
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'Standard KYC',
                      style:
                          TextStyle(
                        fontSize: 19,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    const Text(
                      '1 USDT',
                      style:
                          TextStyle(
                        fontSize: 30,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    const Text(
                      'TRC20 (TRON)',
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    SizedBox(
                      width:
                          double.infinity,
                      height: 52,
                      child:
                          FilledButton(
                        onPressed:
                            loading
                                ? null
                                : startKyc,
                        child: loading
                            ? const CircularProgressIndicator()
                            : const Text(
                                'START KYC',
                              ),
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

class KycPaymentPage
    extends StatelessWidget {
  final Map<String, dynamic> data;

  const KycPaymentPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final address =
        data['deposit_address']
                ?.toString() ??
            '';

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('KYC Payment'),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'KYC Payment',
                    style:
                        TextStyle(
                      fontSize: 24,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  const Text(
                    '1 USDT',
                    style:
                        TextStyle(
                      fontSize: 30,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  const Text(
                    'TRC20 (TRON)',
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  if (address.isNotEmpty)
                    QrImageView(
                      data: address,
                      size: 230,
                      backgroundColor:
                          Colors.white,
                    ),
                  const SizedBox(
                    height: 18,
                  ),
                  SelectableText(
                    address,
                    textAlign:
                        TextAlign.center,
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  const Text(
                    'Payment will be verified automatically on the blockchain.',
                    textAlign:
                        TextAlign.center,
                    style:
                        TextStyle(
                      color:
                          Colors.white60,
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

class WalletPage
    extends StatelessWidget {
  final Session session;

  const WalletPage({
    super.key,
    required this.session,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('ASC Wallet'),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 60,
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  const Text(
                    'Balance',
                    style:
                        TextStyle(
                      color:
                          Colors.white60,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    '${session.balance.toStringAsFixed(2)} ASC',
                    style:
                        const TextStyle(
                      fontSize: 31,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Row(
            children: [
              Expanded(
                child:
                    FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ReceivePage(
                          session:
                              session,
                        ),
                      ),
                    );
                  },
                  icon:
                      const Icon(
                    Icons.call_received,
                  ),
                  label:
                      const Text(
                    'RECEIVE',
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                    FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SendPage(
                          session:
                              session,
                        ),
                      ),
                    );
                  },
                  icon:
                      const Icon(
                    Icons.call_made,
                  ),
                  label:
                      const Text(
                    'SEND',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      HistoryPage(
                    session: session,
                  ),
                ),
              );
            },
            icon:
                const Icon(
              Icons.history,
            ),
            label:
                const Text(
              'TRANSACTION HISTORY',
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RECEIVE
// ============================================================

class ReceivePage
    extends StatelessWidget {
  final Session session;

  const ReceivePage({
    super.key,
    required this.session,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final address =
        session.walletAddress;

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Receive ASC'),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          if (address == null ||
              address.isEmpty)
            const Card(
              child: Padding(
                padding:
                    EdgeInsets.all(20),
                child: Text(
                  'ASC wallet address is not available yet.',
                  textAlign:
                      TextAlign.center,
                ),
              ),
            )
          else ...[
            const Text(
              'Scan to receive ASC',
              textAlign:
                  TextAlign.center,
              style:
                  TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            Center(
              child:
                  QrImageView(
                data: address,
                size: 260,
                backgroundColor:
                    Colors.white,
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            SelectableText(
              address,
              textAlign:
                  TextAlign.center,
            ),

            const SizedBox(
              height: 15,
            ),

            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text: address,
                  ),
                );

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  const SnackBar(
                    content:
                        Text(
                      'Address copied.',
                    ),
                  ),
                );
              },
              icon:
                  const Icon(
                Icons.copy,
              ),
              label:
                  const Text(
                'COPY ADDRESS',
              ),
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

class SendPage
    extends StatefulWidget {
  final Session session;

  const SendPage({
    super.key,
    required this.session,
  });

  @override
  State<SendPage> createState() =>
      _SendPageState();
}

class _SendPageState
    extends State<SendPage> {
  final address =
      TextEditingController();

  final amount =
      TextEditingController();

  bool loading = false;

  @override
  void dispose() {
    address.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final target =
        address.text.trim();

    final value =
        double.tryParse(
      amount.text.trim(),
    );

    if (target.isEmpty) {
      show('Enter recipient address.');
      return;
    }

    if (value == null ||
        value <= 0) {
      show('Enter a valid ASC amount.');
      return;
    }

    if (value >
        widget.session.balance) {
      show('Insufficient ASC balance.');
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final result =
          await Api.send(
        widget.session.token,
        target,
        value,
      );

      if (!mounted) return;

      show(
        result['message']?.toString() ??
            'ASC transfer submitted.',
      );
    } catch (e) {
      show(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void show(
    String text,
  ) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Send ASC'),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          TextField(
            controller: address,
            maxLines: 3,
            decoration:
                const InputDecoration(
              labelText:
                  'Recipient wallet address',
              border:
                  OutlineInputBorder(),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ScannerPage(
                    onScan: (value) {
                      address.text =
                          value;
                      Navigator.pop(
                        context,
                      );
                    },
                  ),
                ),
              );
            },
            icon:
                const Icon(
              Icons.qr_code_scanner,
            ),
            label:
                const Text(
              'SCAN QR',
            ),
          ),

          const SizedBox(
            height: 15,
          ),

          TextField(
            controller: amount,
            keyboardType:
                const TextInputType
                    .numberWithOptions(
              decimal: true,
            ),
            decoration:
                const InputDecoration(
              labelText:
                  'ASC amount',
              border:
                  OutlineInputBorder(),
            ),
          ),

          const SizedBox(
            height: 22,
          ),

          SizedBox(
            height: 54,
            child:
                FilledButton(
              onPressed:
                  loading
                      ? null
                      : send,
              child: loading
                  ? const CircularProgressIndicator()
                  : const Text(
                      'SEND ASC',
                    ),
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

class ScannerPage
    extends StatefulWidget {
  final ValueChanged<String> onScan;

  const ScannerPage({
    super.key,
    required this.onScan,
  });

  @override
  State<ScannerPage> createState() =>
      _ScannerPageState();
}

class _ScannerPageState
    extends State<ScannerPage> {
  bool found = false;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Scan QR'),
      ),
      body:
          MobileScanner(
        onDetect:
            (capture) {
          if (found) return;

          for (final barcode
              in capture.barcodes) {
            final value =
                barcode.rawValue;

            if (value != null &&
                value.isNotEmpty) {
              found = true;
              widget.onScan(
                value,
              );
              return;
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

class HistoryPage
    extends StatefulWidget {
  final Session session;

  const HistoryPage({
    super.key,
    required this.session,
  });

  @override
  State<HistoryPage> createState() =>
      _HistoryPageState();
}

class _HistoryPageState
    extends State<HistoryPage> {
  bool loading = true;

  List<WalletTransaction>
      transactions = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result =
          await Api.history(
        widget.session.token,
      );

      if (!mounted) return;

      setState(() {
        transactions =
            result;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'Transaction History',
        ),
      ),
      body:
          loading
              ? const Center(
                  child:
                      CircularProgressIndicator(),
                )
              : transactions
                      .isEmpty
                  ? const Center(
                      child:
                          Text(
                        'No transactions yet.',
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh:
                          load,
                      child:
                          ListView
                              .builder(
                        itemCount:
                            transactions
                                .length,
                        itemBuilder:
                            (_, index) {
                          final tx =
                              transactions[
                                  index];

                          return Card(
                            margin:
                                const EdgeInsets
                                    .symmetric(
                              horizontal:
                                  12,
                              vertical:
                                  6,
                            ),
                            child:
                                ListTile(
                              leading:
                                  Icon(
                                tx.type
                                            .toLowerCase() ==
                                        'receive'
                                    ? Icons
                                        .call_received
                                    : Icons
                                        .call_made,
                              ),
                              title:
                                  Text(
                                '${tx.amount.toStringAsFixed(2)} ASC',
                              ),
                              subtitle:
                                  Text(
                                '${tx.type}\n${tx.status}',
                              ),
                              isThreeLine:
                                  true,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
