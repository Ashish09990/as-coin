import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ASCoinApp());
}

/* ============================================================
   AS COIN CONFIG
============================================================ */

class ASCConfig {
  static const String appName = 'AS COIN';
  static const String symbol = 'ASC';

  static const double dailyMaximum = 0.14;
  static const int miningEndYear = 2130;
  static const int migrationDays = 365;
  static const double kycFeeUsdt = 1.0;
  static const int maxSupply = 20000000;

  // YAHAN REAL HTTPS BACKEND URL AAYEGA.
  // Example:
  // https://api.example.com
  static const String apiBaseUrl = '';

  static const Duration timeout = Duration(seconds: 20);
}

/* ============================================================
   API ERROR
============================================================ */

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/* ============================================================
   SESSION
============================================================ */

class ASCSession {
  final String token;
  final String phone;
  final String accountId;
  final String walletAddress;
  final bool kycVerified;
  final double balance;
  final DateTime? miningStarted;
  final DateTime? lastClaim;
  final bool miningActive;
  final bool migrated;

  const ASCSession({
    required this.token,
    required this.phone,
    required this.accountId,
    required this.walletAddress,
    required this.kycVerified,
    required this.balance,
    required this.miningStarted,
    required this.lastClaim,
    required this.miningActive,
    required this.migrated,
  });

  factory ASCSession.fromJson(Map<String, dynamic> json) {
    DateTime? date(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return ASCSession(
      token: json['token']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      accountId: json['account_id']?.toString() ?? '',
      walletAddress: json['wallet_address']?.toString() ?? '',
      kycVerified: json['kyc_verified'] == true,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      miningStarted: date(json['mining_started']),
      lastClaim: date(json['last_claim']),
      miningActive: json['mining_active'] == true,
      migrated: json['migrated'] == true,
    );
  }
}

/* ============================================================
   TRANSACTION
============================================================ */

class ASCTransaction {
  final String id;
  final String type;
  final double amount;
  final String sender;
  final String recipient;
  final String status;
  final String txHash;
  final DateTime? date;

  const ASCTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.sender,
    required this.recipient,
    required this.status,
    required this.txHash,
    required this.date,
  });

  factory ASCTransaction.fromJson(Map<String, dynamic> json) {
    return ASCTransaction(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      sender: json['sender']?.toString() ?? '',
      recipient: json['recipient']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      txHash: json['tx_hash']?.toString() ?? '',
      date: DateTime.tryParse(
        json['date']?.toString() ?? '',
      ),
    );
  }
}

/* ============================================================
   SESSION STORAGE
============================================================ */

class ASCStore {
  static String? token;
  static String? phone;

  static Future<void> save(
    String newToken,
    String newPhone,
  ) async {
    token = newToken;
    phone = newPhone;
  }

  static Future<void> clear() async {
    token = null;
    phone = null;
  }
}

/* ============================================================
   API
============================================================ */

class ASCApi {
  static String get baseUrl {
    final value = ASCConfig.apiBaseUrl.trim();

    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }

    return value;
  }

  static bool get configured {
    return baseUrl.startsWith('https://');
  }

  static Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    if (!configured) {
      throw const ApiException(
        'AS COIN backend URL configure nahi hai.',
      );
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (auth && ASCStore.token != null) {
      headers['Authorization'] =
          'Bearer ${ASCStore.token}';
    }

    final uri = Uri.parse('$baseUrl$path');

    late http.Response response;

    try {
      if (method == 'GET') {
        response = await http
            .get(uri, headers: headers)
            .timeout(ASCConfig.timeout);
      } else if (method == 'POST') {
        response = await http
            .post(
              uri,
              headers: headers,
              body: jsonEncode(body ?? {}),
            )
            .timeout(ASCConfig.timeout);
      } else {
        throw const ApiException(
          'Invalid API method.',
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;

      throw ApiException(
        'Network error: $e',
      );
    }

    dynamic decoded;

    try {
      decoded = response.body.isEmpty
          ? {}
          : jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'Server ne invalid response diya.',
        response.statusCode,
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message = 'Request failed.';

      if (decoded is Map) {
        message =
            decoded['detail']?.toString() ??
            decoded['message']?.toString() ??
            message;
      }

      throw ApiException(
        message,
        response.statusCode,
      );
    }

    return Map<String, dynamic>.from(
      decoded as Map,
    );
  }

  static Future<void> requestOtp(
    String phone,
  ) async {
    await request(
      'POST',
      '/auth/request-otp',
      auth: false,
      body: {
        'phone': phone,
      },
    );
  }

  static Future<ASCSession> verifyOtp(
    String phone,
    String otp,
  ) async {
    final result = await request(
      'POST',
      '/auth/verify-otp',
      auth: false,
      body: {
        'phone': phone,
        'otp': otp,
      },
    );

    final session =
        ASCSession.fromJson(result);

    await ASCStore.save(
      session.token,
      session.phone,
    );

    return session;
  }

  static Future<ASCSession> me() async {
    final result =
        await request('GET', '/me');

    return ASCSession.fromJson(result);
  }

  static Future<ASCSession> startMining() async {
    final result =
        await request(
      'POST',
      '/mining/start',
    );

    return ASCSession.fromJson(result);
  }

  static Future<ASCSession> claimMining() async {
    final result =
        await request(
      'POST',
      '/mining/claim',
    );

    return ASCSession.fromJson(result);
  }

  static Future<Map<String, dynamic>>
      createKycPayment() async {
    return request(
      'POST',
      '/kyc/payment',
      body: {
        'amount_usdt':
            ASCConfig.kycFeeUsdt,
        'network': 'TRC20',
      },
    );
  }

  static Future<ASCSession> checkKyc() async {
    final result =
        await request(
      'GET',
      '/kyc/status',
    );

    return ASCSession.fromJson(result);
  }

  static Future<List<ASCTransaction>>
      transactions() async {
    final result =
        await request(
      'GET',
      '/transactions',
    );

    final list =
        result['transactions']
                as List<dynamic>? ??
            [];

    return list
        .map(
          (item) =>
              ASCTransaction.fromJson(
            Map<String, dynamic>.from(
              item,
            ),
          ),
        )
        .toList();
  }

  static Future<Map<String, dynamic>>
      send(
    String recipient,
    double amount,
  ) async {
    return request(
      'POST',
      '/wallet/send',
      body: {
        'recipient': recipient,
        'amount': amount,
      },
    );
  }

  static Future<ASCSession>
      adminKycAuthorization(
    String oneTimeToken,
  ) async {
    final result =
        await request(
      'POST',
      '/admin/kyc-authorize',
      body: {
        'one_time_token':
            oneTimeToken,
      },
    );

    return ASCSession.fromJson(
      result,
    );
  }
}

/* ============================================================
   APP
============================================================ */

class ASCoinApp extends StatelessWidget {
  const ASCoinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: ASCConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const SplashPage(),
    );
  }
}

/* ============================================================
   SPLASH
============================================================ */

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() =>
      _SplashPageState();
}

class _SplashPageState
    extends State<SplashPage> {
  @override
  void initState() {
    super.initState();

    Future.delayed(
      const Duration(milliseconds: 700),
      () {
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const LoginPage(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.monetization_on,
              size: 85,
            ),
            SizedBox(height: 15),
            Text(
              'AS COIN',
              style: TextStyle(
                fontSize: 30,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            SizedBox(height: 6),
            Text('ASC Network'),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   LOGIN
============================================================ */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() =>
      _LoginPageState();
}

class _LoginPageState
    extends State<LoginPage> {
  final country =
      TextEditingController(text: '+91');

  final phone =
      TextEditingController();

  final otp =
      TextEditingController();

  bool loading = false;
  bool otpSent = false;

  String normalizePhone() {
    var c = country.text
        .replaceAll(
          RegExp(r'[^0-9+]'),
          '',
        );

    var p = phone.text
        .replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );

    if (c.isEmpty) {
      c = '+91';
    }

    if (!c.startsWith('+')) {
      c = '+$c';
    }

    final code =
        c.substring(1);

    if (p.startsWith(code)) {
      p = p.substring(
        code.length,
      );
    }

    return '$c$p';
  }

  Future<void> sendOtp() async {
    final number =
        normalizePhone();

    final digits =
        phone.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (digits.length < 6) {
      message(
        'Valid mobile number enter karo.',
      );
      return;
    }

    if (!ASCApi.configured) {
      message(
        'Backend URL configure nahi hai.',
      );
      return;
    }

    setState(
      () => loading = true,
    );

    try {
      await ASCApi.requestOtp(
        number,
      );

      if (!mounted) return;

      setState(
        () => otpSent = true,
      );

      message(
        'OTP sent successfully.',
      );
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  Future<void> verifyOtp() async {
    final number =
        normalizePhone();

    final code =
        otp.text.trim();

    if (code.length < 4) {
      message(
        'OTP enter karo.',
      );
      return;
    }

    setState(
      () => loading = true,
    );

    try {
      final session =
          await ASCApi.verifyOtp(
        number,
        code,
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
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  void message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  void dispose() {
    country.dispose();
    phone.dispose();
    otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.monetization_on,
                  size: 90,
                ),
                const SizedBox(
                  height: 15,
                ),
                const Text(
                  'AS COIN',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                const Text(
                  'Secure ASC Network',
                ),
                const SizedBox(
                  height: 40,
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller:
                            country,
                        keyboardType:
                            TextInputType
                                .phone,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Code',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child: TextField(
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
                const SizedBox(
                  height: 15,
                ),
                if (otpSent)
                  TextField(
                    controller: otp,
                    keyboardType:
                        TextInputType.number,
                    maxLength: 8,
                    decoration:
                        const InputDecoration(
                      labelText: 'OTP',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(
                  height: 8,
                ),
                SizedBox(
                  width:
                      double.infinity,
                  child: FilledButton(
                    onPressed:
                        loading
                            ? null
                            : otpSent
                                ? verifyOtp
                                : sendOtp,
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        14,
                      ),
                      child: Text(
                        loading
                            ? 'PLEASE WAIT...'
                            : otpSent
                                ? 'VERIFY OTP'
                                : 'SEND OTP',
                      ),
                    ),
                  ),
                ),
                const SizedBox(
                  height: 15,
                ),
                const Text(
                  'OTP aur account verification server par hoti hai.',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
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

/* ============================================================
   HOME
============================================================ */

class HomePage extends StatefulWidget {
  final ASCSession session;

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
  late ASCSession session;

  bool loading = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();

    session =
        widget.session;

    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      setState(
        () => loading = true,
      );

      final updated =
          await ASCApi.me();

      if (mounted) {
        setState(
          () => session = updated,
        );
      }
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  Duration get remaining {
    if (session.lastClaim ==
        null) {
      return Duration.zero;
    }

    final next =
        session.lastClaim!
            .toUtc()
            .add(
              const Duration(
                hours: 24,
              ),
            );

    final difference =
        next.difference(
      DateTime.now().toUtc(),
    );

    return difference.isNegative
        ? Duration.zero
        : difference;
  }

  String countdown() {
    final d = remaining;

    if (d == Duration.zero) {
      return 'READY';
    }

    return '${d.inHours.toString().padLeft(2, '0')}:'
        '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  Future<void> startMining() async {
    if (!session.kycVerified) {
      message(
        'Pehle KYC complete karo.',
      );
      return;
    }

    if (DateTime.now().year >=
        ASCConfig.miningEndYear) {
      message(
        'Mining period ended.',
      );
      return;
    }

    setState(
      () => loading = true,
    );

    try {
      final updated =
          await ASCApi.startMining();

      if (mounted) {
        setState(
          () => session = updated,
        );

        message(
          'Mining started.',
        );
      }
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  Future<void> claim() async {
    if (!session.kycVerified) {
      message(
        'KYC verification required.',
      );
      return;
    }

    if (remaining !=
        Duration.zero) {
      message(
        'Next claim: ${countdown()}',
      );
      return;
    }

    setState(
      () => loading = true,
    );

    try {
      final updated =
          await ASCApi.claimMining();

      if (mounted) {
        setState(
          () => session = updated,
        );

        message(
          '0.14 ASC credited.',
        );
      }
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  void message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  Future<void> openKyc() async {
    final updated =
        await Navigator.push<ASCSession>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            KycPage(
          session: session,
        ),
      ),
    );

    if (updated != null &&
        mounted) {
      setState(
        () => session = updated,
      );
    }
  }

  Future<void> openWallet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            WalletPage(
          session: session,
        ),
      ),
    );

    await refresh();
  }

  void openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const HistoryPage(),
      ),
    );
  }

  void openAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AccountPage(
          session: session,
        ),
      ),
    );
  }

  Future<void> logout() async {
    await ASCStore.clear();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const LoginPage(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('AS COIN • ASC'),
        actions: [
          IconButton(
            onPressed: openWallet,
            icon: const Icon(
              Icons
                  .account_balance_wallet,
            ),
          ),
          IconButton(
            onPressed: openAccount,
            icon: const Icon(
              Icons.person,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding:
              const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AS COIN',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    const Text(
                      'ASC • Network',
                      style: TextStyle(
                        color:
                            Colors.grey,
                      ),
                    ),
                    const SizedBox(
                      height: 18,
                    ),
                    Text(
                      '${session.balance.toStringAsFixed(8)} ASC',
                      style:
                          const TextStyle(
                        fontSize: 32,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    const Text(
                      'Maximum mining reward: 0.14 ASC / 24 hours',
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      session.accountId,
                      style:
                          const TextStyle(
                        fontSize: 12,
                        color:
                            Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bolt,
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        const Expanded(
                          child: Text(
                            'Mining',
                            style:
                                TextStyle(
                              fontSize:
                                  21,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                        Text(
                          session.miningActive
                              ? 'ACTIVE'
                              : 'STOPPED',
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    LinearProgressIndicator(
                      value:
                          session.miningActive
                              ? 1
                              : 0,
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          FilledButton(
                        onPressed:
                            loading ||
                                    session
                                        .miningActive
                                ? null
                                : startMining,
                        child: Text(
                          session.miningActive
                              ? 'MINING ACTIVE'
                              : 'START MINING',
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          OutlinedButton(
                        onPressed:
                            loading
                                ? null
                                : claim,
                        child: Text(
                          remaining ==
                                  Duration
                                      .zero
                              ? 'CLAIM 0.14 ASC'
                              : 'NEXT CLAIM ${countdown()}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Card(
              child: ListTile(
                leading: Icon(
                  session.kycVerified
                      ? Icons.verified
                      : Icons
                          .verified_user_outlined,
                ),
                title: const Text(
                  'KYC Verification',
                ),
                subtitle: Text(
                  session.kycVerified
                      ? 'Verified'
                      : 'Available immediately • 1 USDT TRC20',
                ),
                trailing:
                    FilledButton(
                  onPressed:
                      session.kycVerified
                          ? null
                          : openKyc,
                  child: Text(
                    session.kycVerified
                        ? 'VERIFIED'
                        : 'KYC',
                  ),
                ),
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'AS COIN PROTOCOL',
                      style:
                          TextStyle(
                        fontSize: 21,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      height: 12,
                    ),
                    Text(
                      'Maximum Supply: 20,000,000 ASC',
                    ),
                    Text(
                      'Daily Maximum: 0.14 ASC',
                    ),
                    Text(
                      'Mining End: 2130',
                    ),
                    Text(
                      'KYC: Immediate',
                    ),
                    Text(
                      'Normal KYC Fee: 1 USDT • TRC20',
                    ),
                    Text(
                      'Migration: 365 days',
                    ),
                    Text(
                      'Transfers: Verified accounts',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons
                          .account_balance_wallet,
                    ),
                    title: const Text(
                      'Wallet',
                    ),
                    subtitle:
                        const Text(
                      'Send / Receive ASC',
                    ),
                    onTap: openWallet,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.history,
                    ),
                    title: const Text(
                      'Transaction History',
                    ),
                    onTap:
                        openHistory,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.person,
                    ),
                    title: const Text(
                      'Account',
                    ),
                    onTap:
                        openAccount,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.logout,
                    ),
                    title: const Text(
                      'Logout',
                    ),
                    onTap: logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}/* ============================================================
   KYC PAGE
============================================================ */

class KycPage extends StatefulWidget {
  final ASCSession session;

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
  bool loading = false;
  bool checking = false;

  Future<void> createPayment() async {
    setState(
      () => loading = true,
    );

    try {
      final result =
          await ASCApi.createKycPayment();

      if (!mounted) return;

      final address =
          result['payment_address']
              ?.toString() ??
          '';

      final amount =
          result['amount_usdt']
              ?.toString() ??
          '1';

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(
            'KYC Payment',
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Send exactly 1 USDT on TRC20 to:',
                ),
                const SizedBox(
                  height: 12,
                ),
                SelectableText(
                  address,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  'Amount: $amount USDT',
                ),
                const SizedBox(
                  height: 12,
                ),
                const Text(
                  'KYC will be approved only after the server confirms the blockchain payment.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child:
                  const Text('CLOSE'),
            ),
          ],
        ),
      );
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  Future<void> checkStatus() async {
    setState(
      () => checking = true,
    );

    try {
      final updated =
          await ASCApi.checkKyc();

      if (!mounted) return;

      Navigator.pop(
        context,
        updated,
      );
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => checking = false,
        );
      }
    }
  }

  Future<void> adminAuthorization() async {
    final controller =
        TextEditingController();

    final token =
        await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Owner Authorization',
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration:
              const InputDecoration(
            labelText:
                'One-time authorization',
            border:
                OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              context,
            ),
            child:
                const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              context,
              controller.text.trim(),
            ),
            child:
                const Text('VERIFY'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (token == null ||
        token.isEmpty) {
      return;
    }

    setState(
      () => loading = true,
    );

    try {
      final updated =
          await ASCApi
              .adminKycAuthorization(
        token,
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        updated,
      );
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  void message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'KYC VERIFICATION',
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          const Icon(
            Icons.verified_user,
            size: 80,
          ),
          const SizedBox(
            height: 15,
          ),
          const Text(
            'KYC available immediately',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          const Text(
            'Normal KYC fee: 1 USDT • TRC20',
            textAlign:
                TextAlign.center,
          ),
          const SizedBox(
            height: 25,
          ),

          /* NORMAL KYC */

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text(
                    'NORMAL USER',
                    style:
                        TextStyle(
                      fontSize: 19,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  const Text(
                    'Pay 1 USDT on TRC20. The server checks the blockchain transaction before approving KYC.',
                    textAlign:
                        TextAlign.center,
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        FilledButton.icon(
                      onPressed:
                          loading
                              ? null
                              : createPayment,
                      icon:
                          const Icon(
                        Icons
                            .payment,
                      ),
                      label: Text(
                        loading
                            ? 'PLEASE WAIT...'
                            : 'PAY 1 USDT • TRC20',
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        OutlinedButton(
                      onPressed:
                          checking
                              ? null
                              : checkStatus,
                      child: Text(
                        checking
                            ? 'CHECKING...'
                            : 'CHECK KYC STATUS',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 15,
          ),

          /* OWNER */

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text(
                    'OWNER / ADMIN',
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
                    'Owner authorization is verified server-side and can be used only once.',
                    textAlign:
                        TextAlign.center,
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        OutlinedButton(
                      onPressed:
                          loading
                              ? null
                              : adminAuthorization,
                      child:
                          const Text(
                        'ADMIN AUTHORIZATION',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 15,
          ),

          const Card(
            child: Padding(
              padding:
                  EdgeInsets.all(16),
              child: Text(
                'Security: KYC status is controlled by the AS COIN server. The APK does not contain a permanent owner password or fake payment confirmation.',
                style:
                    TextStyle(
                  color:
                      Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }/* ============================================================
   KYC PAGE
============================================================ */

class KycPage extends StatefulWidget {
  final ASCSession session;

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
  bool loading = false;
  bool checking = false;

  Future<void> createPayment() async {
    setState(
      () => loading = true,
    );

    try {
      final result =
          await ASCApi.createKycPayment();

      if (!mounted) return;

      final address =
          result['payment_address']
              ?.toString() ??
          '';

      final amount =
          result['amount_usdt']
              ?.toString() ??
          '1';

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(
            'KYC Payment',
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Send exactly 1 USDT on TRC20 to:',
                ),
                const SizedBox(
                  height: 12,
                ),
                SelectableText(
                  address,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  'Amount: $amount USDT',
                ),
                const SizedBox(
                  height: 12,
                ),
                const Text(
                  'KYC will be approved only after the server confirms the blockchain payment.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child:
                  const Text('CLOSE'),
            ),
          ],
        ),
      );
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  Future<void> checkStatus() async {
    setState(
      () => checking = true,
    );

    try {
      final updated =
          await ASCApi.checkKyc();

      if (!mounted) return;

      Navigator.pop(
        context,
        updated,
      );
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => checking = false,
        );
      }
    }
  }

  Future<void> adminAuthorization() async {
    final controller =
        TextEditingController();

    final token =
        await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Owner Authorization',
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration:
              const InputDecoration(
            labelText:
                'One-time authorization',
            border:
                OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              context,
            ),
            child:
                const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              context,
              controller.text.trim(),
            ),
            child:
                const Text('VERIFY'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (token == null ||
        token.isEmpty) {
      return;
    }

    setState(
      () => loading = true,
    );

    try {
      final updated =
          await ASCApi
              .adminKycAuthorization(
        token,
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        updated,
      );
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => loading = false,
        );
      }
    }
  }

  void message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'KYC VERIFICATION',
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          const Icon(
            Icons.verified_user,
            size: 80,
          ),
          const SizedBox(
            height: 15,
          ),
          const Text(
            'KYC available immediately',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          const Text(
            'Normal KYC fee: 1 USDT • TRC20',
            textAlign:
                TextAlign.center,
          ),
          const SizedBox(
            height: 25,
          ),

          /* NORMAL KYC */

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text(
                    'NORMAL USER',
                    style:
                        TextStyle(
                      fontSize: 19,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  const Text(
                    'Pay 1 USDT on TRC20. The server checks the blockchain transaction before approving KYC.',
                    textAlign:
                        TextAlign.center,
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        FilledButton.icon(
                      onPressed:
                          loading
                              ? null
                              : createPayment,
                      icon:
                          const Icon(
                        Icons
                            .payment,
                      ),
                      label: Text(
                        loading
                            ? 'PLEASE WAIT...'
                            : 'PAY 1 USDT • TRC20',
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        OutlinedButton(
                      onPressed:
                          checking
                              ? null
                              : checkStatus,
                      child: Text(
                        checking
                            ? 'CHECKING...'
                            : 'CHECK KYC STATUS',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 15,
          ),

          /* OWNER */

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text(
                    'OWNER / ADMIN',
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
                    'Owner authorization is verified server-side and can be used only once.',
                    textAlign:
                        TextAlign.center,
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        OutlinedButton(
                      onPressed:
                          loading
                              ? null
                              : adminAuthorization,
                      child:
                          const Text(
                        'ADMIN AUTHORIZATION',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 15,
          ),

          const Card(
            child: Padding(
              padding:
                  EdgeInsets.all(16),
              child: Text(
                'Security: KYC status is controlled by the AS COIN server. The APK does not contain a permanent owner password or fake payment confirmation.',
                style:
                    TextStyle(
                  color:
                      Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   WALLET PAGE
============================================================ */

class WalletPage extends StatefulWidget {
  final ASCSession session;

  const WalletPage({
    super.key,
    required this.session,
  });

  @override
  State<WalletPage> createState() =>
      _WalletPageState();
}

class _WalletPageState
    extends State<WalletPage> {
  late ASCSession session;

  @override
  void initState() {
    super.initState();
    session = widget.session;
  }

  Future<void> refresh() async {
    try {
      final updated =
          await ASCApi.me();

      if (mounted) {
        setState(
          () => session = updated,
        );
      }
    } catch (e) {
      message(
        e.toString(),
      );
    }
  }

  void copyAddress() {
    Clipboard.setData(
      ClipboardData(
        text:
            session.walletAddress,
      ),
    );

    message(
      'ASC address copied.',
    );
  }

  Future<void> receive() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReceivePage(
          address:
              session.walletAddress,
        ),
      ),
    );
  }

  Future<void> send() async {
    if (!session.kycVerified) {
      message(
        'KYC verification required.',
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SendPage(
          session: session,
        ),
      ),
    );

    await refresh();
  }

  void message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('ASC WALLET'),
      ),
      body: RefreshIndicator(
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
                  children: [
                    const Icon(
                      Icons
                          .account_balance_wallet,
                      size: 60,
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      'Wallet Balance',
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      '${session.balance.toStringAsFixed(8)} ASC',
                      style:
                          const TextStyle(
                        fontSize: 30,
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

            /* ADDRESS */

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ASC WALLET ADDRESS',
                      style:
                          TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    SelectableText(
                      session
                          .walletAddress,
                      style:
                          const TextStyle(
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child:
                              OutlinedButton
                                  .icon(
                            onPressed:
                                copyAddress,
                            icon:
                                const Icon(
                              Icons.copy,
                            ),
                            label:
                                const Text(
                              'COPY',
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child:
                              OutlinedButton
                                  .icon(
                            onPressed:
                                receive,
                            icon:
                                const Icon(
                              Icons.qr_code,
                            ),
                            label:
                                const Text(
                              'QR CODE',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            SizedBox(
              width:
                  double.infinity,
              child:
                  FilledButton.icon(
                onPressed: receive,
                icon:
                    const Icon(
                  Icons.download,
                ),
                label:
                    const Padding(
                  padding:
                      EdgeInsets.all(14),
                  child:
                      Text(
                    'RECEIVE ASC',
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            SizedBox(
              width:
                  double.infinity,
              child:
                  FilledButton.icon(
                onPressed: send,
                icon:
                    const Icon(
                  Icons.send,
                ),
                label:
                    const Padding(
                  padding:
                      EdgeInsets.all(14),
                  child:
                      Text(
                    'SEND ASC',
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            Card(
              child: ListTile(
                leading: Icon(
                  session.kycVerified
                      ? Icons.verified
                      : Icons.warning,
                ),
                title:
                    const Text(
                  'KYC STATUS',
                ),
                subtitle:
                    Text(
                  session.kycVerified
                      ? 'Verified'
                      : 'Not verified',
                ),
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),
                child: Text(
                  session.migrated
                      ? 'Wallet migration completed.'
                      : 'Migration becomes available after ${ASCConfig.migrationDays} days.',
                  style:
                      const TextStyle(
                    color:
                        Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   RECEIVE PAGE
============================================================ */

class ReceivePage
    extends StatelessWidget {
  final String address;

  const ReceivePage({
    super.key,
    required this.address,
  });

  void copy(
    BuildContext context,
  ) {
    Clipboard.setData(
      ClipboardData(
        text: address,
      ),
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      const SnackBar(
        content: Text(
          'Address copied.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('RECEIVE ASC'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          const Text(
            'YOUR ASC RECEIVING ADDRESS',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          const Text(
            'Scan or copy this address to receive ASC.',
            textAlign:
                TextAlign.center,
          ),

          const SizedBox(
            height: 25,
          ),

          Center(
            child: Container(
              padding:
                  const EdgeInsets.all(18),
              color:
                  Colors.white,
              child: QrImageView(
                data: address,
                size: 240,
              ),
            ),
          ),

          const SizedBox(
            height: 25,
          ),

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child:
                  SelectableText(
                address,
                textAlign:
                    TextAlign.center,
              ),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          SizedBox(
            width:
                double.infinity,
            child:
                FilledButton.icon(
              onPressed: () =>
                  copy(context),
              icon:
                  const Icon(
                Icons.copy,
              ),
              label:
                  const Text(
                'COPY ADDRESS',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   SEND PAGE
============================================================ */

class SendPage
    extends StatefulWidget {
  final ASCSession session;

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

  bool sending = false;

  Future<void> scan() async {
    final result =
        await Navigator.push<
            String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const ScannerPage(),
      ),
    );

    if (result != null &&
        result.trim().isNotEmpty &&
        mounted) {
      setState(() {
        address.text =
            result.trim();
      });
    }
  }

  Future<void> send() async {
    final recipient =
        address.text.trim();

    final value =
        double.tryParse(
      amount.text.trim(),
    );

    if (!widget.session.kycVerified) {
      message(
        'KYC verification required.',
      );
      return;
    }

    if (recipient.isEmpty) {
      message(
        'Recipient address enter karo.',
      );
      return;
    }

    if (value == null ||
        value <= 0) {
      message(
        'Valid ASC amount enter karo.',
      );
      return;
    }

    if (value >
        widget.session.balance) {
      message(
        'Insufficient ASC balance.',
      );
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (_) =>
          AlertDialog(
        title: const Text(
          'CONFIRM TRANSFER',
        ),
        content: Text(
          'Amount: ${value.toStringAsFixed(8)} ASC\n\nRecipient:\n$recipient',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              context,
              false,
            ),
            child:
                const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              context,
              true,
            ),
            child:
                const Text('CONFIRM'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(
      () => sending = true,
    );

    try {
      final result =
          await ASCApi.send(
        recipient,
        value,
      );

      if (!mounted) return;

      final status =
          result['status']
              ?.toString() ??
          'SUBMITTED';

      final txHash =
          result['tx_hash']
              ?.toString() ??
          '';

      showDialog(
        context: context,
        builder: (_) =>
            AlertDialog(
          title: const Text(
            'TRANSFER SUBMITTED',
          ),
          content: Text(
            'Status: $status\n\n'
            '${txHash.isEmpty ? 'Transaction is being processed by the server.' : 'TX: $txHash'}',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child:
                  const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      message(
        e.toString(),
      );
    } finally {
      if (mounted) {
        setState(
          () => sending = false,
        );
      }
    }
  }

  void message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  void dispose() {
    address.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('SEND ASC'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading:
                  const Icon(
                Icons
                    .account_balance_wallet,
              ),
              title:
                  const Text(
                'Available Balance',
              ),
              subtitle:
                  Text(
                '${widget.session.balance.toStringAsFixed(8)} ASC',
              ),
            ),
          ),

          const SizedBox(
            height: 15,
          ),

          TextField(
            controller: address,
            minLines: 2,
            maxLines: 4,
            decoration:
                InputDecoration(
              labelText:
                  'Recipient ASC Address',
              hintText:
                  'ASC-XXXXXXXX...',
              border:
                  const OutlineInputBorder(),
              suffixIcon:
                  IconButton(
                onPressed: scan,
                icon:
                    const Icon(
                  Icons
                      .qr_code_scanner,
                ),
              ),
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
                  'Amount ASC',
              border:
                  OutlineInputBorder(),
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          SizedBox(
            width:
                double.infinity,
            child:
                FilledButton.icon(
              onPressed:
                  sending
                      ? null
                      : send,
              icon:
                  const Icon(
                Icons.send,
              ),
              label:
                  Padding(
                padding:
                    const EdgeInsets.all(
                  14,
                ),
                child: Text(
                  sending
                      ? 'PROCESSING...'
                      : 'SEND ASC',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



              
        ),
      ),
    );
  }

  Future<void> send() async {
    if (!session.kycVerified) {
      message(
        'KYC verification required.',
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SendPage(
          session: session,
        ),
      ),
    );

    await refresh();
  }

  void message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('ASC WALLET'),
      ),
      body: RefreshIndicator(
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
                  children: [
                    const Icon(
                      Icons
                          .account_balance_wallet,
                      size: 60,
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      'Wallet Balance',
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      '${session.balance.toStringAsFixed(8)} ASC',
                      style:
                          const TextStyle(
                        fontSize: 30,
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

            /* ADDRESS */

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ASC WALLET ADDRESS',
                      style:
                          TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    SelectableText(
                      session
                          .walletAddress,
                      style:
                          const TextStyle(
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child:
                              OutlinedButton
                                  .icon(
                            onPressed:
                                copyAddress,
                            icon:
                                const Icon(
                              Icons.copy,
                            ),
                            label:
                                const Text(
                              'COPY',
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child:
                              OutlinedButton
                                  .icon(
                            onPressed:
                                receive,
                            icon:
                                const Icon(
                              Icons.qr_code,
                            ),
                            label:
                                const Text(
                              'QR CODE',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            SizedBox(
              width:
                  double.infinity,
              child:
                  FilledButton.icon(
                onPressed: receive,
                icon:
                    const Icon(
                  Icons.download,
                ),
                label:
                    const Padding(
                  padding:
                      EdgeInsets.all(14),
                  child:
                      Text(
                    'RECEIVE ASC',
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            SizedBox(
              width:
                  double.infinity,
              child:
                  FilledButton.icon(
                onPressed: send,
                icon:
                    const Icon(
                  Icons.send,
                ),
                label:
                    const Padding(
                  padding:
                      EdgeInsets.all(14),
                  child:
                      Text(
                    'SEND ASC',
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            Card(
              child: ListTile(
                leading: Icon(
                  session.kycVerified
                      ? Icons.verified
                      : Icons.warning,
                ),
                title:
                    const Text(
                  'KYC STATUS',
                ),
                subtitle:
                    Text(
                  session.kycVerified
                      ? 'Verified'
                      : 'Not verified',
                ),
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),
                child: Text(
                  session.migrated
                      ? 'Wallet migration completed.'
                      : 'Migration becomes available after ${ASCConfig.migrationDays} days.',
                  style:
                      const TextStyle(
                    color:
                        Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _found = false;

  void _onDetect(BarcodeCapture capture) {
    if (_found) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _found = true;
        Navigator.pop(context, value.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan ASC Address'),
      ),
      body: MobileScanner(
        onDetect: _onDetect,
      ),
    );
  }
}


class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool loading = true;
  String? error;
  List<ASCTransaction> transactions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final data = await ASCApi.transactions();

      if (!mounted) return;

      setState(() {
        transactions = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  IconData _iconFor(String type) {
    final t = type.toLowerCase();

    if (t.contains('claim') || t.contains('mining')) {
      return Icons.bolt;
    }

    if (t.contains('send')) {
      return Icons.arrow_upward;
    }

    if (t.contains('receive')) {
      return Icons.arrow_downward;
    }

    if (t.contains('kyc')) {
      return Icons.verified;
    }

    return Icons.swap_horiz;
  }

  Color _colorFor(String type) {
    final t = type.toLowerCase();

    if (t.contains('send')) {
      return Colors.red;
    }

    if (t.contains('receive') ||
        t.contains('claim') ||
        t.contains('mining')) {
      return Colors.green;
    }

    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASC History'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 50,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : transactions.isEmpty
                  ? const Center(
                      child: Text(
                        'No transactions yet',
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: transactions.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final tx = transactions[index];
                          final color = _colorFor(tx.type);

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  _iconFor(tx.type),
                                  color: color,
                                ),
                              ),
                              title: Text(
                                tx.type.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  if (tx.address != null &&
                                      tx.address!.isNotEmpty)
                                    Text(
                                      tx.address!,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  if (tx.txHash != null &&
                                      tx.txHash!.isNotEmpty)
                                    Text(
                                      'TX: ${tx.txHash}',
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  if (tx.createdAt != null)
                                    Text(tx.createdAt!),
                                ],
                              ),
                              trailing: Text(
                                '${tx.amount >= 0 ? '+' : ''}${tx.amount.toStringAsFixed(4)} ASC',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}


class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  ASCSession? session;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ASCApi.me();

      if (!mounted) return;

      setState(() {
        session = data;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await ASCStore.clear();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
      (route) => false,
    );
  }

  Widget _info(
    String title,
    String value, {
    IconData icon = Icons.info_outline,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(
          title,
          style: const TextStyle(fontSize: 12),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const CircleAvatar(
              radius: 42,
              child: Icon(
                Icons.person,
                size: 45,
              ),
            ),

            const SizedBox(height: 16),

            Center(
              child: Text(
                'AS COIN Account',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),

            const SizedBox(height: 20),

            if (session != null) ...[
              _info(
                'User ID',
                session!.userId,
                icon: Icons.badge,
              ),
              _info(
                'Phone',
                session!.phone,
                icon: Icons.phone,
              ),
              _info(
                'Wallet Address',
                session!.walletAddress,
                icon: Icons.account_balance_wallet,
              ),
              _info(
                'Balance',
                '${session!.balance.toStringAsFixed(4)} ASC',
                icon: Icons.currency_bitcoin,
              ),
              _info(
                'KYC',
                session!.kycStatus,
                icon: Icons.verified_user,
              ),
              _info(
                'Mining Rate',
                '${ASCConfig.dailyMaximum.toStringAsFixed(2)} ASC / day',
                icon: Icons.bolt,
              ),
              _info(
                'Migration',
                '${ASCConfig.migrationDays} days',
                icon: Icons.swap_horiz,
              ),
              _info(
                'Mining End',
                '${ASCConfig.miningEndYear}',
                icon: Icons.event,
              ),
            ],

            const SizedBox(height: 12),

            Card(
              child: ListTile(
                leading: const Icon(Icons.security),
                title: const Text('Security'),
                subtitle: const Text(
                  'Account and mining rules are verified by the server.',
                ),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ),

            const SizedBox(height: 24),

            const Center(
              child: Text(
                'AS COIN',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 6),

            const Center(
              child: Text(
                'Secure digital asset platform',
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ------------------------------------------------------------
// APP END
// ------------------------------------------------------------

class ErrorPage extends StatelessWidget {
  final String message;

  const ErrorPage({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AS COIN'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
