import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ASCoinApp());
}

/* ============================================================
   CONFIG
============================================================ */

class ASCConfig {
  static const String appName = 'AS COIN';
  static const String symbol = 'ASC';

  static const double dailyReward = 0.14;
  static const int miningEndYear = 2130;
  static const int migrationDays = 365;
  static const double kycFeeUsdt = 1.0;
  static const int maxSupply = 20000000;

  // IMPORTANT:
  // Apne deployed HTTPS backend ka URL yahan lagana hai.
  // Example:
  // https://api.yourdomain.com
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
  final String accountId;
  final String phone;
  final String walletAddress;

  final double balance;

  final bool kycVerified;
  final bool miningActive;
  final bool migrated;

  final DateTime? miningStarted;
  final DateTime? lastClaim;
  final DateTime? accountCreated;

  const ASCSession({
    required this.token,
    required this.accountId,
    required this.phone,
    required this.walletAddress,
    required this.balance,
    required this.kycVerified,
    required this.miningActive,
    required this.migrated,
    required this.miningStarted,
    required this.lastClaim,
    required this.accountCreated,
  });

  factory ASCSession.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return ASCSession(
      token: json['token']?.toString() ?? '',
      accountId:
          json['account_id']?.toString() ??
          json['user_id']?.toString() ??
          '',
      phone: json['phone']?.toString() ?? '',
      walletAddress:
          json['wallet_address']?.toString() ?? '',
      balance:
          (json['balance'] as num?)?.toDouble() ?? 0,
      kycVerified:
          json['kyc_verified'] == true ||
          json['kyc_status']?.toString().toUpperCase() ==
              'VERIFIED',
      miningActive:
          json['mining_active'] == true,
      migrated:
          json['migrated'] == true,
      miningStarted:
          parseDate(json['mining_started']),
      lastClaim:
          parseDate(json['last_claim']),
      accountCreated:
          parseDate(json['account_created']),
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

  factory ASCTransaction.fromJson(
    Map<String, dynamic> json,
  ) {
    return ASCTransaction(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'TRANSFER',
      amount:
          (json['amount'] as num?)?.toDouble() ?? 0,
      sender:
          json['sender']?.toString() ?? '',
      recipient:
          json['recipient']?.toString() ?? '',
      status:
          json['status']?.toString() ?? 'UNKNOWN',
      txHash:
          json['tx_hash']?.toString() ?? '',
      date: DateTime.tryParse(
        json['date']?.toString() ??
            json['created_at']?.toString() ??
            '',
      ),
    );
  }
}

/* ============================================================
   SESSION STORE
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
   API CLIENT
============================================================ */

class ASCApi {
  static String get baseUrl {
    final value =
        ASCConfig.apiBaseUrl.trim();

    if (value.endsWith('/')) {
      return value.substring(
        0,
        value.length - 1,
      );
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
        'Backend URL configure nahi hai.',
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

    final uri =
        Uri.parse('$baseUrl$path');

    http.Response response;

    try {
      if (method == 'GET') {
        response = await http
            .get(
              uri,
              headers: headers,
            )
            .timeout(
              ASCConfig.timeout,
            );
      } else if (method == 'POST') {
        response = await http
            .post(
              uri,
              headers: headers,
              body: jsonEncode(
                body ?? {},
              ),
            )
            .timeout(
              ASCConfig.timeout,
            );
      } else {
        throw const ApiException(
          'Invalid API method.',
        );
      }
    } on TimeoutException {
      throw const ApiException(
        'Server timeout. Dobara try karo.',
      );
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }

      throw ApiException(
        'Network error: $e',
      );
    }

    dynamic decoded;

    try {
      decoded =
          response.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'Server ne invalid response diya.',
        response.statusCode,
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message =
          'Request failed.';

      if (decoded is Map) {
        message =
            decoded['detail']
                ?.toString() ??
            decoded['message']
                ?.toString() ??
            message;
      }

      throw ApiException(
        message,
        response.statusCode,
      );
    }

    if (decoded is! Map) {
      throw const ApiException(
        'Invalid server response.',
      );
    }

    return Map<String, dynamic>.from(
      decoded,
    );
  }

  /* ---------------- AUTH ---------------- */

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

    if (session.token.isEmpty) {
      throw const ApiException(
        'Server ne login token nahi diya.',
      );
    }

    await ASCStore.save(
      session.token,
      session.phone,
    );

    return session;
  }

  static Future<ASCSession> me() async {
    final result =
        await request(
      'GET',
      '/me',
    );

    return ASCSession.fromJson(result);
  }

  /* ---------------- MINING ---------------- */

  static Future<ASCSession>
      startMining() async {
    final result =
        await request(
      'POST',
      '/mining/start',
    );

    return ASCSession.fromJson(result);
  }

  static Future<ASCSession>
      claimMining() async {
    final result =
        await request(
      'POST',
      '/mining/claim',
      body: {
        'reward':
            ASCConfig.dailyReward,
      },
    );

    return ASCSession.fromJson(result);
  }

  /* ---------------- KYC ---------------- */

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

  static Future<ASCSession>
      kycStatus() async {
    final result =
        await request(
      'GET',
      '/kyc/status',
    );

    return ASCSession.fromJson(result);
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

    return ASCSession.fromJson(result);
  }

  /* ---------------- WALLET ---------------- */

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

  static Future<List<ASCTransaction>>
      transactions() async {
    final result =
        await request(
      'GET',
      '/transactions',
    );

    final raw =
        result['transactions'];

    if (raw is! List) {
      return [];
    }

    return raw
        .whereType<Map>()
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
}

/* ============================================================
   APP
============================================================ */

class ASCoinApp extends StatelessWidget {
  const ASCoinApp({super.key});

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      title: ASCConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed:
            Colors.indigo,
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
      const Duration(
        milliseconds: 700,
      ),
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
  Widget build(
    BuildContext context,
  ) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .monetization_on,
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
            Text(
              'ASC Network',
            ),
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
  final countryController =
      TextEditingController(
    text: '+91',
  );

  final phoneController =
      TextEditingController();

  final otpController =
      TextEditingController();

  bool loading = false;
  bool otpSent = false;

  String getPhone() {
    String country =
        countryController.text
            .replaceAll(
              RegExp(r'[^0-9+]'),
              '',
            );

    String phone =
        phoneController.text
            .replaceAll(
              RegExp(r'[^0-9]'),
              '',
            );

    if (country.isEmpty) {
      country = '+91';
    }

    if (!country.startsWith('+')) {
      country = '+$country';
    }

    final code =
        country.substring(1);

    if (phone.startsWith(code)) {
      phone =
          phone.substring(
        code.length,
      );
    }

    return '$country$phone';
  }

  Future<void> sendOtp() async {
    final digits =
        phoneController.text
            .replaceAll(
              RegExp(r'[^0-9]'),
              '',
            );

    if (digits.length < 6) {
      showMessage(
        'Valid mobile number enter karo.',
      );
      return;
    }

    if (!ASCApi.configured) {
      showMessage(
        'Backend URL configure nahi hai.',
      );
      return;
    }

    setState(
      () => loading = true,
    );

    try {
      await ASCApi.requestOtp(
        getPhone(),
      );

      if (!mounted) return;

      setState(
        () => otpSent = true,
      );

      showMessage(
        'OTP sent successfully.',
      );
    } catch (e) {
      showMessage(
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
    final otp =
        otpController.text.trim();

    if (otp.length < 4) {
      showMessage(
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
        getPhone(),
        otp,
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

  @override
  void dispose() {
    countryController.dispose();
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child:
              SingleChildScrollView(
            padding:
                const EdgeInsets.all(
              24,
            ),
            child: Column(
              children: [
                const Icon(
                  Icons
                      .monetization_on,
                  size: 90,
                ),
                const SizedBox(
                  height: 15,
                ),
                const Text(
                  'AS COIN',
                  style:
                      TextStyle(
                    fontSize: 34,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 6,
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
                      child:
                          TextField(
                        controller:
                            countryController,
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
                      child:
                          TextField(
                        controller:
                            phoneController,
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
                    controller:
                        otpController,
                    keyboardType:
                        TextInputType
                            .number,
                    maxLength: 8,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'OTP',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),

                const SizedBox(
                  height: 10,
                ),

                SizedBox(
                  width:
                      double.infinity,
                  child:
                      FilledButton(
                    onPressed:
                        loading
                            ? null
                            : otpSent
                                ? verifyOtp
                                : sendOtp,
                    child:
                        Padding(
                      padding:
                          const EdgeInsets
                              .all(
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
                  'One mobile number = one AS COIN account.',
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(
                    fontSize: 12,
                    color:
                        Colors.grey,
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

  Timer? timer;
  bool loading = false;

  @override
  void initState() {
    super.initState();

    session =
        widget.session;

    timer = Timer.periodic(
      const Duration(
        seconds: 1,
      ),
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

    final now =
        DateTime.now().toUtc();

    final d =
        next.difference(now);

    return d.isNegative
        ? Duration.zero
        : d;
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

  Future<void> refresh() async {
    try {
      final updated =
          await ASCApi.me();

      if (mounted) {
        setState(
          () => session =
              updated,
        );
      }
    } catch (e) {
      showMessage(
        e.toString(),
      );
    }
  }

  Future<void> startMining() async {
    if (!session.kycVerified) {
      showMessage(
        'Pehle KYC complete karo.',
      );
      return;
    }

    if (DateTime.now().year >=
        ASCConfig.miningEndYear) {
      showMessage(
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
          () => session =
              updated,
        );

        showMessage(
          'Mining started.',
        );
      }
    } catch (e) {
      showMessage(
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
      showMessage(
        'KYC verification required.',
      );
      return;
    }

    if (!session.miningActive) {
      showMessage(
        'Pehle mining start karo.',
      );
      return;
    }

    if (remaining !=
        Duration.zero) {
      showMessage(
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
          () => session =
              updated,
        );

        showMessage(
          '0.14 ASC credited.',
        );
      }
    } catch (e) {
      showMessage(
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

  Future<void> openKyc() async {
    final updated =
        await Navigator.push<
            ASCSession>(
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
        () => session =
            updated,
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
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('AS COIN'),
        actions: [
          IconButton(
            onPressed:
                openWallet,
            icon: const Icon(
              Icons
                  .account_balance_wallet,
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AccountPage(
                    session:
                        session,
                  ),
                ),
              );
            },
            icon: const Icon(
              Icons.person,
            ),
          ),
        ],
      ),
      body:
          RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding:
              const EdgeInsets.all(
            16,
          ),
          children: [
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  22,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Text(
                      'AS COIN',
                      style:
                          TextStyle(
                        fontSize: 28,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
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
                      'Maximum reward: 0.14 ASC / 24 hours',
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
                    const EdgeInsets.all(
                  18,
                ),
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
                                  FontWeight.bold,
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
                      height: 15,
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
                title:
                    const Text(
                  'KYC',
                ),
                subtitle:
                    Text(
                  session.kycVerified
                      ? 'Verified'
                      : 'Not verified • 1 USDT TRC20',
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
              child: Column(
                children: [
                  ListTile(
                    leading:
                        const Icon(
                      Icons
                          .account_balance_wallet,
                    ),
                    title:
                        const Text(
                      'Wallet',
                    ),
                    subtitle:
                        const Text(
                      'Send / Receive ASC',
                    ),
                    onTap:
                        openWallet,
                  ),
                  ListTile(
                    leading:
                        const Icon(
                      Icons.history,
                    ),
                    title:
                        const Text(
                      'Transaction History',
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) =>
                                  const HistoryPage(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(
                      Icons.logout,
                    ),
                    title:
                        const Text(
                      'Logout',
                    ),
                    onTap:
                        logout,
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            const Card(
              child: Padding(
                padding:
                    EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      'AS COIN PROTOCOL',
                      style:
                          TextStyle(
                        fontSize: 19,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      height: 10,
                    ),
                    Text(
                      'Maximum Supply: 20,000,000 ASC',
                    ),
                    Text(
                      'Mining Rate: 0.14 ASC / day',
                    ),
                    Text(
                      'Mining End: 2130',
                    ),
                    Text(
                      'KYC: Immediate',
                    ),
                    Text(
                      'Normal KYC: 1 USDT • TRC20',
                    ),
                    Text(
                      'Migration: 365 days',
                    ),
                  ],
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
   KYC
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

  Future<void> createPayment() async {
    setState(
      () => loading = true,
    );

    try {
      final result =
          await ASCApi
              .createKycPayment();

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
        builder: (_) =>
            AlertDialog(
          title:
              const Text(
            'KYC PAYMENT',
          ),
          content:
              SingleChildScrollView(
            child: Column(
              children: [
                const Text(
                  'Exactly 1 USDT TRC20 send karo:',
                  textAlign:
                      TextAlign.center,
                ),
                const SizedBox(
                  height: 15,
                ),
                if (address.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets
                            .all(
                      12,
                    ),
                    color:
                        Colors.white,
                    child:
                        QrImageView(
                      data:
                          address,
                      size: 190,
                    ),
                  ),
                const SizedBox(
                  height: 15,
                ),
                SelectableText(
                  address,
                  textAlign:
                      TextAlign.center,
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
                  'KYC tabhi approve hogi jab backend blockchain payment verify karega.',
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(
                    color:
                        Colors.grey,
                  ),
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
                  const Text(
                'CLOSE',
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      showMessage(
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
      () => loading = true,
    );

    try {
      final updated =
          await ASCApi.kycStatus();

      if (!mounted) return;

      if (updated.kycVerified) {
        Navigator.pop(
          context,
          updated,
        );
      } else {
        showMessage(
          'KYC abhi verified nahi hai.',
        );
      }
    } catch (e) {
      showMessage(
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

  Future<void> ownerAuthorization() async {
    final controller =
        TextEditingController();

    final token =
        await showDialog<String>(
      context: context,
      builder: (_) =>
          AlertDialog(
        title:
            const Text(
          'Owner Authorization',
        ),
        content:
            TextField(
          controller:
              controller,
          obscureText: true,
          decoration:
              const InputDecoration(
            labelText:
                'One-time token',
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
                const Text(
              'CANCEL',
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              context,
              controller
                  .text
                  .trim(),
            ),
            child:
                const Text(
              'VERIFY',
            ),
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
      showMessage(
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

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'KYC VERIFICATION',
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(
          20,
        ),
        children: [
          const Icon(
            Icons.verified_user,
            size: 75,
          ),
          const SizedBox(
            height: 15,
          ),
          const Text(
            'KYC available immediately',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
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

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              child: Column(
                children: [
                  const Text(
                    'NORMAL KYC',
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
                    'Payment server blockchain par verify karega. Fake/local KYC approval nahi hoga.',
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
                        FilledButton(
                      onPressed:
                          loading
                              ? null
                              : createPayment,
                      child: Text(
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
                          loading
                              ? null
                              : checkStatus,
                      child:
                          const Text(
                        'CHECK KYC STATUS',
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

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              child: Column(
                children: [
                  const Text(
                    'OWNER',
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
                    'Owner authorization server-side one-time token se verify hogi.',
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
                              : ownerAuthorization,
                      child:
                          const Text(
                        'OWNER AUTHORIZATION',
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

/* ============================================================
   WALLET
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
    session =
        widget.session;
  }

  Future<void> refresh() async {
    try {
      final updated =
          await ASCApi.me();

      if (mounted) {
        setState(
          () => session =
              updated,
        );
      }
    } catch (e) {
      showMessage(
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

    showMessage(
      'Wallet address copied.',
    );
  }

  Future<void> openReceive() async {
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

  Future<void> openSend() async {
    if (!session.kycVerified) {
      showMessage(
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

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'ASC WALLET',
        ),
      ),
      body:
          RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding:
              const EdgeInsets.all(
            18,
          ),
          children: [
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  22,
                ),
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
                      'Balance',
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

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Text(
                      'YOUR ASC ADDRESS',
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
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child:
                              OutlinedButton.icon(
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
                              OutlinedButton.icon(
                            onPressed:
                                openReceive,
                            icon:
                                const Icon(
                              Icons.qr_code,
                            ),
                            label:
                                const Text(
                              'QR',
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
                onPressed:
                    openReceive,
                icon:
                    const Icon(
                  Icons.download,
                ),
                label:
                    const Padding(
                  padding:
                      EdgeInsets.all(
                    14,
                  ),
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
                onPressed:
                    openSend,
                icon:
                    const Icon(
                  Icons.send,
                ),
                label:
                    const Padding(
                  padding:
                      EdgeInsets.all(
                    14,
                  ),
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
              child:
                  ListTile(
                leading: Icon(
                  session.kycVerified
                      ? Icons.verified
                      : Icons.warning,
                ),
                title:
                    const Text(
                  'KYC',
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
              height: 10,
            ),

            Card(
              child:
                  ListTile(
                leading:
                    const Icon(
                  Icons.swap_horiz,
                ),
                title:
                    const Text(
                  'Migration',
                ),
                subtitle:
                    Text(
                  session.migrated
                      ? 'Completed'
                      : 'Available after ${ASCConfig.migrationDays} days',
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
   RECEIVE
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
        content:
            Text(
          'Address copied.',
        ),
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
            const Text(
          'RECEIVE ASC',
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(
          20,
        ),
        children: [
          const Text(
            'YOUR ASC ADDRESS',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              color:
                  Colors.white,
              child:
                  QrImageView(
                data: address,
                size: 240,
              ),
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                16,
              ),
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
        ],
      ),
    );
  }
}

/* ============================================================
   SEND
============================================================ */

class SendPage extends StatefulWidget {
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
  final addressController =
      TextEditingController();

  final amountController =
      TextEditingController();

  bool sending = false;

  Future<void> scanQr() async {
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
        addressController
                .text =
            result.trim();
      });
    }
  }

  Future<void> send() async {
    final recipient =
        addressController.text.trim();

    final amount =
        double.tryParse(
      amountController.text.trim(),
    );

    if (recipient.isEmpty) {
      showMessage(
        'Recipient address enter karo.',
      );
      return;
    }

    if (amount == null ||
        amount <= 0) {
      showMessage(
        'Valid ASC amount enter karo.',
      );
      return;
    }

    if (amount >
        widget.session.balance) {
      showMessage(
        'Insufficient ASC balance.',
      );
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (_) =>
          AlertDialog(
        title:
            const Text(
          'CONFIRM SEND',
        ),
        content:
            Text(
          '${amount.toStringAsFixed(8)} ASC\n\nTo:\n$recipient',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              context,
              false,
            ),
            child:
                const Text(
              'CANCEL',
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              context,
              true,
            ),
            child:
                const Text(
              'CONFIRM',
            ),
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
        amount,
      );

      if (!mounted) return;

      final status =
          result['status']
              ?.toString() ??
          'SUBMITTED';

      final hash =
          result['tx_hash']
              ?.toString() ??
          '';

      await showDialog(
        context: context,
        builder: (_) =>
            AlertDialog(
          title:
              const Text(
            'TRANSFER',
          ),
          content:
              Text(
            'Status: $status\n\n'
            '${hash.isEmpty ? 'Server is processing the transaction.' : 'TX: $hash'}',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child:
                  const Text(
                'OK',
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      showMessage(
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

  @override
  void dispose() {
    addressController.dispose();
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'SEND ASC',
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(
          20,
        ),
        children: [
          Card(
            child:
                ListTile(
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
            controller:
                addressController,
            minLines: 2,
            maxLines: 4,
            decoration:
                InputDecoration(
              labelText:
                  'Recipient ASC Address',
              hintText:
                  'ASC address',
              border:
                  const OutlineInputBorder(),
              suffixIcon:
                  IconButton(
                onPressed:
                    scanQr,
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
            controller:
                amountController,
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
                    const EdgeInsets
                        .all(
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

/* ============================================================
   QR SCANNER
============================================================ */

class ScannerPage
    extends StatefulWidget {
  const ScannerPage({
    super.key,
  });

  @override
  State<ScannerPage> createState() =>
      _ScannerPageState();
}

class _ScannerPageState
    extends State<ScannerPage> {
  bool found = false;

  void onDetect(
    BarcodeCapture capture,
  ) {
    if (found) return;

    for (final barcode
        in capture.barcodes) {
      final value =
          barcode.rawValue;

      if (value != null &&
          value.trim().isNotEmpty) {
        found = true;

        Navigator.pop(
          context,
          value.trim(),
        );

        return;
      }
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
          'SCAN ASC ADDRESS',
        ),
      ),
      body:
          MobileScanner(
        onDetect:
            onDetect,
      ),
    );
  }
}

/* ============================================================
   HISTORY
============================================================ */

class HistoryPage
    extends StatefulWidget {
  const HistoryPage({
    super.key,
  });

  @override
  State<HistoryPage> createState() =>
      _HistoryPageState();
}

class _HistoryPageState
    extends State<HistoryPage> {
  bool loading = true;
  String? error;

  List<ASCTransaction>
      transactions = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result =
          await ASCApi.transactions();

      if (!mounted) return;

      setState(() {
        transactions =
            result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error =
            e.toString();
        loading = false;
      });
    }
  }

  IconData iconFor(
    String type,
  ) {
    final t =
        type.toLowerCase();

    if (t.contains('claim') ||
        t.contains('mining')) {
      return Icons.bolt;
    }

    if (t.contains('send')) {
      return Icons
          .arrow_upward;
    }

    if (t.contains('receive')) {
      return Icons
          .arrow_downward;
    }

    if (t.contains('kyc')) {
      return Icons.verified;
    }

    return Icons.swap_horiz;
  }

  Color colorFor(
    String type,
  ) {
    final t =
        type.toLowerCase();

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
  Widget build(
    BuildContext context,
  ) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(
          title:
              const Text(
            'ASC HISTORY',
          ),
        ),
        body:
            const Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (error != null) {
      return Scaffold(
        appBar: AppBar(
          title:
              const Text(
            'ASC HISTORY',
          ),
        ),
        body:
            Center(
          child:
              Padding(
            padding:
                const EdgeInsets
                    .all(
              24,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Icon(
                  Icons
                      .error_outline,
                  size: 55,
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  error!,
                  textAlign:
                      TextAlign.center,
                ),
                const SizedBox(
                  height: 15,
                ),
                FilledButton(
                  onPressed:
                      load,
                  child:
                      const Text(
                    'RETRY',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (transactions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title:
              const Text(
            'ASC HISTORY',
          ),
          actions: [
            IconButton(
              onPressed:
                  load,
              icon:
                  const Icon(
                Icons.refresh,
              ),
            ),
          ],
        ),
        body:
            const Center(
          child:
              Text(
            'No transactions yet.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'ASC HISTORY',
        ),
        actions: [
          IconButton(
            onPressed:
                load,
            icon:
                const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body:
          RefreshIndicator(
        onRefresh: load,
        child:
            ListView.separated(
          padding:
              const EdgeInsets.all(
            12,
          ),
          itemCount:
              transactions.length,
          separatorBuilder:
              (_, __) =>
                  const SizedBox(
            height: 8,
          ),
          itemBuilder:
              (_, index) {
            final tx =
                transactions[index];

            final color =
                colorFor(
              tx.type,
            );

            return Card(
              child:
                  ListTile(
                leading:
                    CircleAvatar(
                  child:
                      Icon(
                    iconFor(
                      tx.type,
                    ),
                    color:
                        color,
                  ),
                ),
                title:
                    Text(
                  tx.type
                      .toUpperCase(),
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight
                            .bold,
                  ),
                ),
                subtitle:
                    Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    if (tx.sender
                        .isNotEmpty)
                      Text(
                        'From: ${tx.sender}',
                        maxLines:
                            1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                      ),
                    if (tx.recipient
                        .isNotEmpty)
                      Text(
                        'To: ${tx.recipient}',
                        maxLines:
                            1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                      ),
                    if (tx.status
                        .isNotEmpty)
                      Text(
                        'Status: ${tx.status}',
                      ),
                    if (tx.txHash
                        .isNotEmpty)
                      Text(
                        'TX: ${tx.txHash}',
                        maxLines:
                            1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                      ),
                    if (tx.date !=
                        null)
                      Text(
                        tx.date!
                            .toLocal()
                            .toString(),
                      ),
                  ],
                ),
                trailing:
                    Text(
                  '${tx.amount >= 0 ? '+' : ''}${tx.amount.toStringAsFixed(4)}',
                  style:
                      TextStyle(
                    color:
                        color,
                    fontWeight:
                        FontWeight
                            .bold,
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

/* ============================================================
   ACCOUNT
============================================================ */

class AccountPage
    extends StatelessWidget {
  final ASCSession session;

  const AccountPage({
    super.key,
    required this.session,
  });

  Widget info(
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      child: ListTile(
        leading:
            Icon(icon),
        title:
            Text(
          title,
          style:
              const TextStyle(
            fontSize: 12,
            color:
                Colors.grey,
          ),
        ),
        subtitle:
            Text(
          value,
          style:
              const TextStyle(
            fontSize: 16,
            fontWeight:
                FontWeight.w600,
          ),
        ),
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
            const Text(
          'ACCOUNT',
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(
          16,
        ),
        children: [
          const CircleAvatar(
            radius: 42,
            child: Icon(
              Icons.person,
              size: 45,
            ),
          ),
          const SizedBox(
            height: 15,
          ),
          const Center(
            child: Text(
              'AS COIN ACCOUNT',
              style:
                  TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(
            height: 20,
          ),

          info(
            'User ID',
            session.accountId,
            Icons.badge,
          ),

          info(
            'Phone',
            session.phone,
            Icons.phone,
          ),

          info(
            'Wallet',
            session.walletAddress,
            Icons
                .account_balance_wallet,
          ),

          info(
            'Balance',
            '${session.balance.toStringAsFixed(8)} ASC',
            Icons
                .monetization_on,
          ),

          info(
            'KYC',
            session.kycVerified
                ? 'VERIFIED'
                : 'NOT VERIFIED',
            Icons.verified_user,
          ),

          info(
            'Mining Rate',
            '0.14 ASC / day',
            Icons.bolt,
          ),

          info(
            'Migration',
            '${ASCConfig.migrationDays} days',
            Icons.swap_horiz,
          ),

          info(
            'Mining End',
            '${ASCConfig.miningEndYear}',
            Icons.event,
          ),

          const SizedBox(
            height: 15,
          ),

          const Card(
            child: Padding(
              padding:
                  EdgeInsets.all(16),
              child: Text(
                'Account, KYC, mining and wallet rules must be enforced by the AS COIN backend. The app itself is not the authority for balances or rewards.',
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
