import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ASCoinApp());
}

/* ============================================================
   AS COIN — PRODUCTION CLIENT
   IMPORTANT:
   This client never invents balances, KYC success, OTP success,
   or blockchain transfers. Those must be confirmed by the API.

   Configure the real HTTPS backend in apiBaseUrl before release.
============================================================ */

class ASCConfig {
  static const appName = 'AS COIN';
  static const symbol = 'ASC';

  static const double dailyMaximum = 0.14;
  static const int miningEndYear = 2130;
  static const int migrationDays = 365;
  static const double kycFeeUsdt = 1.0;
  static const int maxSupply = 20000000;

  // Example: https://api.your-domain.com
  // DO NOT put private keys, seed phrases, bot tokens or admin
  // secrets in this APK.
  static const String apiBaseUrl = 'https://as-coin.onrender.com';

  static const Duration httpTimeout = Duration(seconds: 20);
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class Session {
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

  const Session({
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

  factory Session.fromJson(Map<String, dynamic> j) {
    DateTime? dt(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());

    final rawUser = j['user'];
    final Map<String, dynamic> data =
        rawUser is Map
            ? {
                ...Map<String, dynamic>.from(rawUser),
                'token': j['token'] ?? rawUser['token'],
              }
            : j;

    final kycStatus = data['kyc_status']?.toString();
    final kycVerified =
        data['kyc_verified'] == true ||
        (kycStatus != null &&
            kycStatus.toLowerCase() == 'verified');

    return Session(
      token: data['token']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      accountId:
          data['account_id']?.toString() ??
          data['user_id']?.toString() ??
          data['id']?.toString() ??
          '',
      walletAddress: data['wallet_address']?.toString() ?? '',
      kycVerified: kycVerified,
      balance: data['balance'] is num
          ? (data['balance'] as num).toDouble()
          : double.tryParse('${data['balance'] ?? 0}') ?? 0,
      miningStarted: dt(data['mining_started']),
      lastClaim: dt(data['last_claim']),
      miningActive: data['mining_active'] == true,
      migrated: data['migrated'] == true,
    );
  }
}

class ASCTransaction {
  final String id;
  final String type;
  final double amount;
  final String sender;
  final String recipient;
  final DateTime? date;
  final String status;
  final String txHash;

  const ASCTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.sender,
    required this.recipient,
    required this.date,
    required this.status,
    required this.txHash,
  });

  factory ASCTransaction.fromJson(Map<String, dynamic> j) {
    return ASCTransaction(
      id: j['id']?.toString() ?? '',
      type: j['type']?.toString() ?? '',
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      sender: j['sender']?.toString() ?? '',
      recipient: j['recipient']?.toString() ?? '',
      date: DateTime.tryParse(j['date']?.toString() ?? ''),
      status: j['status']?.toString() ?? 'UNKNOWN',
      txHash: j['tx_hash']?.toString() ?? '',
    );
  }
}

class ASCStore {
  static String? token;
  static String? phone;

  static Future<void> setSession(String t, String p) async {
    token = t;
    phone = p;
  }

  static Future<void> clear() async {
    token = null;
    phone = null;
  }
}

class ASCApi {
  static String get base {
    final b = ASCConfig.apiBaseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  static bool get configured => base.startsWith('https://');

  static Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    if (!configured) {
      throw const ApiException(
        'AS COIN backend is not configured. Set ASCConfig.apiBaseUrl to your HTTPS production API.',
      );
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth && ASCStore.token != null) {
      headers['Authorization'] = 'Bearer ${ASCStore.token}';
    }

    final uri = Uri.parse('$base$path');
    late http.Response response;

    try {
      if (method == 'GET') {
        response = await http
            .get(uri, headers: headers)
            .timeout(ASCConfig.httpTimeout);
      } else if (method == 'POST') {
        response = await http
            .post(
              uri,
              headers: headers,
              body: jsonEncode(body ?? {}),
            )
            .timeout(ASCConfig.httpTimeout);
      } else {
        throw const ApiException('Unsupported API method.');
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? {} : jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'Server returned invalid JSON.',
        response.statusCode,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = decoded is Map
          ? decoded['detail']?.toString() ??
              decoded['message']?.toString() ??
              'Request failed.'
          : 'Request failed.';
      throw ApiException(msg, response.statusCode);
    }

    return Map<String, dynamic>.from(decoded as Map);
  }

  static Future<Session> googleLogin(
    String idToken,
  ) async {
    final j = await request(
      'POST',
      '/auth/google',
      body: {'id_token': idToken},
      auth: false,
    );

    final s = Session.fromJson(j);

    if (s.token.isEmpty) {
      throw const ApiException(
        'AS COIN login token was not received.',
      );
    }

    await ASCStore.setSession(s.token, s.phone);
    return s;
  }

  static Future<Map<String, dynamic>> createPurchase() async {
    return request(
      'POST',
      '/purchases/create',
    );
  }

  static Future<Map<String, dynamic>> purchaseStatus(
    String id,
  ) async {
    return request(
      'GET',
      '/purchases/$id',
    );
  }

  static Future<Session> me() async {
    final j = await request('GET', '/me');
    return Session.fromJson(j);
  }

  static Future<Session> startMining() async {
    final j = await request('POST', '/mining/start');
    return Session.fromJson(j);
  }

  static Future<Session> claimMining() async {
    final j = await request('POST', '/mining/claim');
    return Session.fromJson(j);
  }

  static Future<Map<String, dynamic>> createKycPayment() async {
    return request(
      'POST',
      '/kyc/payment',
      body: {'amount_usdt': ASCConfig.kycFeeUsdt, 'network': 'TRC20'},
    );
  }

  static Future<Session> checkKyc() async {
    final j = await request('GET', '/kyc/status');
    return Session.fromJson(j);
  }

  static Future<List<ASCTransaction>> transactions() async {
    final j = await request('GET', '/transactions');
    final list = (j['transactions'] as List<dynamic>? ?? []);
    return list
        .map((e) => ASCTransaction.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> send(
    String recipient,
    double amount,
  ) async {
    return request(
      'POST',
      '/wallet/send',
      body: {
        'address': recipient,
        'amount': amount,
      },
    );
  }

  static Future<Map<String, dynamic>> migrationStatus() async {
    return request('GET', '/migration/status');
  }

  static Future<Session> adminKycAuthorization(String oneTimeToken) async {
    final j = await request(
      'POST',
      '/admin/kyc-authorize',
      body: {'one_time_token': oneTimeToken},
    );
    return Session.fromJson(j);
  }
}

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

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(check);
  }

  Future<void> check() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monetization_on, size: 82),
            SizedBox(height: 12),
            Text(
              'AS COIN',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 5),
            Text('ASC Network'),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool googleLoading = false;

  void msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> googleSignIn() async {
    if (!ASCApi.configured) {
      msg('Backend connection is not configured.');
      return;
    }

    if (googleLoading) return;

    setState(() => googleLoading = true);

    try {
      final signIn = GoogleSignIn.instance;

      await signIn.initialize(
        serverClientId:
            '236630075813-t27posuu4jb0m1lc9s0qm500eel43id.apps.googleusercontent.com',
      );

      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const ApiException(
          'Google ID token was not received.',
        );
      }

      final session = await ASCApi.googleLogin(idToken);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(session: session),
        ),
      );
    } catch (e) {
      msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => googleLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  const CircleAvatar(
                    radius: 65,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.attach_money,
                      size: 75,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'AS COIN',
                    style: TextStyle(
                      fontSize: 34,
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
                  const SizedBox(height: 45),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed:
                          googleLoading ? null : googleSignIn,
                      icon: googleLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.account_circle,
                              size: 27,
                            ),
                      label: Text(
                        googleLoading
                            ? 'Signing in...'
                            : 'Continue with Google',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Sign in securely with your Google account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'One verified Google identity = one AS COIN account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final Session initial;
  const HomePage({super.key, required Session session}) : initial = session;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Session session;
  bool loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    session = widget.initial;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final s = await ASCApi.me();
      if (mounted) setState(() => session = s);
    } catch (e) {
      msg(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Duration get remaining {
    final last = session.lastClaim;
    if (last == null) return Duration.zero;
    final next = last.toUtc().add(const Duration(hours: 24));
    final d = next.difference(DateTime.now().toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  String countdown() {
    final d = remaining;
    if (d == Duration.zero) return 'READY';
    return '${d.inHours.toString().padLeft(2, '0')}:'
        '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  bool get migrationReady {
    final start = session.miningStarted;
    if (start == null) return false;
    return DateTime.now().toUtc().difference(start.toUtc()) >=
        Duration(days: ASCConfig.migrationDays);
  }

  bool get endReached => DateTime.now().year >= ASCConfig.miningEndYear;

  Future<void> startMining() async {
    if (!session.kycVerified) {
      msg('Pehle KYC complete karo.');
      return;
    }
    if (endReached) {
      msg('Mining period ended.');
      return;
    }
    setState(() => loading = true);
    try {
      setState(() => session = await ASCApi.startMining());
      msg('Mining started.');
    } catch (e) {
      msg(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> claim() async {
    if (!session.kycVerified) {
      msg('KYC verification required.');
      return;
    }
    if (endReached) {
      msg('Mining period ended.');
      return;
    }
    if (remaining != Duration.zero) {
      msg('Next claim: ${countdown()}');
      return;
    }
    setState(() => loading = true);
    try {
      setState(() => session = await ASCApi.claimMining());
      msg('0.14 ASC credited by server.');
    } catch (e) {
      msg(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> kyc() async {
    final updated = await Navigator.push<Session>(
      context,
      MaterialPageRoute(builder: (_) => KycPage(session: session)),
    );
    if (updated != null && mounted) setState(() => session = updated);
  }

  Future<void> wallet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WalletPage(session: session)),
    );
    await refresh();
  }

  Future<void> history() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
  }

  Future<void> account() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountPage(session: session)),
    );
  }

  Future<void> logout() async {
    await ASCStore.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void msg(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AS COIN • ASC'),
        actions: [
          IconButton(onPressed: wallet, icon: const Icon(Icons.account_balance_wallet)),
          IconButton(onPressed: account, icon: const Icon(Icons.person)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AS COIN', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('ASC • Network', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 20),
                    Text(
                      '${session.balance.toStringAsFixed(8)} ASC',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('Maximum mining reward: 0.14 ASC / 24 hours'),
                    const SizedBox(height: 8),
                    Text(session.accountId, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Mining', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                        ),
                        Text(session.miningActive ? 'ACTIVE' : 'STOPPED'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: session.miningActive ? 1 : 0),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: loading || session.miningActive ? null : startMining,
                        child: Text(session.miningActive ? 'MINING ACTIVE' : 'START MINING'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: loading ? null : claim,
                        child: Text(
                          remaining == Duration.zero
                              ? 'CLAIM 0.14 ASC'
                              : 'NEXT CLAIM ${countdown()}',
                        ),
                      ),
                    ),
                    if (session.migrated)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text('Migration completed', style: TextStyle(color: Colors.green)),
                      )
                    else if (migrationReady)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text('365-day migration is now eligible'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.shopping_cart),
                title: const Text('Buy ASC'),
                subtitle: const Text('50 USDT → 5,000 ASC • TRC20'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PurchasePage(session: session),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(session.kycVerified ? Icons.verified : Icons.verified_user_outlined),
                title: const Text('KYC Verification'),
                subtitle: Text(
                  session.kycVerified
                      ? 'Verified'
                      : 'Available immediately • 1 USDT TRC20',
                ),
                trailing: FilledButton(
                  onPressed: session.kycVerified ? null : kyc,
                  child: Text(session.kycVerified ? 'VERIFIED' : 'KYC'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('AS COIN PROTOCOL', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                    SizedBox(height: 12),
                    Text('Maximum Supply: 20,000,000 ASC'),
                    Text('Daily Maximum: 0.14 ASC'),
                    Text('Mining End: 2130'),
                    Text('KYC: Immediate'),
                    Text('Normal KYC Fee: 1 USDT • TRC20'),
                    Text('Migration: 365 days'),
                    Text('Transfers: Verified accounts'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet),
                    title: const Text('Wallet'),
                    subtitle: const Text('Send / Receive ASC'),
                    onTap: wallet,
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Transaction History'),
                    onTap: history,
                  ),
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Account'),
                    onTap: account,
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Logout'),
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
}


class PurchasePage extends StatefulWidget {
  final Session session;

  const PurchasePage({
    super.key,
    required this.session,
  });

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  Map<String, dynamic>? order;
  bool loading = false;
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> createOrder() async {
    if (loading) return;

    setState(() => loading = true);

    try {
      final data = await ASCApi.createPurchase();

      if (!mounted) return;

      setState(() {
        order = data;
        loading = false;
      });

      final id = data['id']?.toString() ??
          data['purchase_id']?.toString() ??
          '';

      if (id.isNotEmpty) {
        timer?.cancel();
        timer = Timer.periodic(
          const Duration(seconds: 10),
          (_) => checkOrder(id),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        message(e.toString());
      }
    }
  }

  Future<void> checkOrder(String id) async {
    try {
      final data = await ASCApi.purchaseStatus(id);

      if (!mounted) return;

      setState(() => order = data);

      final status =
          data['status']?.toString().toLowerCase() ?? '';

      if (status == 'confirmed' ||
          status == 'completed' ||
          status == 'paid') {
        timer?.cancel();
        message('Payment verified by server.');
      }
    } catch (_) {}
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final address = o?['deposit_address']?.toString() ?? '';
    final status = o?['status']?.toString() ?? 'Not created';

    return Scaffold(
      appBar: AppBar(title: const Text('BUY ASC')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: const [
                  Text(
                    'ASC Purchase',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 15),
                  Text('50 USDT → 5,000 ASC'),
                  SizedBox(height: 6),
                  Text('Network: TRC20 (TRON)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          if (address.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Text(
                      'USDT Deposit Address',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    QrImageView(
                      data: address,
                      size: 230,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 15),
                    SelectableText(
                      address,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: address),
                        );
                        message('Address copied.');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('COPY ADDRESS'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 15),
          Card(
            child: ListTile(
              title: const Text('Server Payment Status'),
              subtitle: Text(status),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: loading ? null : createOrder,
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      o == null
                          ? 'CREATE PAYMENT ORDER'
                          : 'CREATE NEW PAYMENT ORDER',
                    ),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'ASC is credited only after the backend confirms the blockchain payment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

class KycPage extends StatefulWidget {
  final Session session;
  const KycPage({super.key, required this.session});

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  bool loading = false;
  String paymentId = '';
  String paymentAddress = '';

  Future<void> createPayment() async {
    setState(() => loading = true);
    try {
      final j = await ASCApi.createKycPayment();
      setState(() {
        paymentId = j['payment_id']?.toString() ?? '';
        paymentAddress = j['deposit_address']?.toString() ?? '';
      });
      if (paymentAddress.isEmpty) {
        msg('Payment order created. Follow the server payment instructions.');
      }
    } catch (e) {
      msg(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> check() async {
    setState(() => loading = true);
    try {
      final s = await ASCApi.checkKyc();
      if (!mounted) return;
      if (s.kycVerified) {
        Navigator.pop(context, s);
      } else {
        msg('Payment/KYC is not confirmed yet.');
      }
    } catch (e) {
      msg(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> admin() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Owner authorization'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'One-time authorization token',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('VERIFY'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token == null || token.isEmpty) return;

    setState(() => loading = true);
    try {
      final s = await ASCApi.adminKycAuthorization(token);
      if (!mounted) return;
      Navigator.pop(context, s);
    } catch (e) {
      msg(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void msg(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KYC Verification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.verified_user, size: 75),
          const SizedBox(height: 16),
          const Text(
            'KYC available immediately',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Normal KYC fee: 1 USDT • TRC20',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text('Normal User', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text(
                    'Create a server payment order. KYC is approved only after the backend verifies the required blockchain payment.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: loading ? null : createPayment,
                      child: const Text('CREATE 1 USDT PAYMENT'),
                    ),
                  ),
                  if (paymentId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SelectableText('Payment ID: $paymentId'),
                  ],
                  if (paymentAddress.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('TRC20 deposit address'),
                    SelectableText(paymentAddress, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: paymentAddress));
                        msg('Address copied.');
                      },
                      child: const Text('COPY ADDRESS'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: loading ? null : check,
                    child: const Text('CHECK KYC STATUS'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text('Owner / Admin', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Only a server-issued one-time authorization token is accepted. No permanent admin secret is stored in the APK.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: loading ? null : admin,
                    child: const Text('ADMIN AUTHORIZATION'),
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

class WalletPage extends StatefulWidget {
  final Session session;
  const WalletPage({super.key, required this.session});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  late Session session;

  @override
  void initState() {
    super.initState();
    session = widget.session;
  }

  Future<void> send() async {
    if (!session.kycVerified) {
      msg('KYC verification required.');
      return;
    }
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SendPage(session: session)),
    );
    if (updated == true) {
      try {
        final updatedSession = await ASCApi.me();
        if (mounted) {
          setState(() {
            session = updatedSession;
          });
        }
      } catch (_) {}
    }
  }

  void receive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceivePage(address: session.walletAddress),
      ),
    );
  }

  void copy() {
    Clipboard.setData(ClipboardData(text: session.walletAddress));
    msg('Wallet address copied.');
  }

  void msg(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ASC WALLET')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(Icons.account_balance_wallet, size: 55),
                  const SizedBox(height: 12),
                  const Text('Wallet Balance'),
                  const SizedBox(height: 6),
                  Text(
                    '${session.balance.toStringAsFixed(8)} ASC',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ASC Wallet Address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SelectableText(session.walletAddress),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton.icon(onPressed: copy, icon: const Icon(Icons.copy), label: const Text('COPY'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(onPressed: receive, icon: const Icon(Icons.qr_code), label: const Text('QR'))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: receive,
              icon: const Icon(Icons.download),
              label: const Padding(padding: EdgeInsets.all(13), child: Text('RECEIVE ASC')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: send,
              icon: const Icon(Icons.send),
              label: const Padding(padding: EdgeInsets.all(13), child: Text('SEND ASC')),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'The address and balance shown here come from the AS COIN backend. Real blockchain transactions are accepted only after server validation.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReceivePage extends StatelessWidget {
  final String address;
  const ReceivePage({super.key, required this.address});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RECEIVE ASC')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Your ASC receiving address',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(data: address, size: 240),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(address, textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: address));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Address copied.')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('COPY ADDRESS'),
          ),
        ],
      ),
    );
  }
}

class SendPage extends StatefulWidget {
  final Session session;
  const SendPage({super.key, required this.session});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final address = TextEditingController();
  final amount = TextEditingController();
  bool loading = false;

  Future<void> scan() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (result != null && result.trim().isNotEmpty) {
      setState(() => address.text = result.trim());
    }
  }

  Future<void> send() async {
    final recipient = address.text.trim();
    final value = double.tryParse(amount.text.trim());

    if (!widget.session.kycVerified) {
      msg('KYC verification required.');
      return;
    }
    if (recipient.isEmpty) {
      msg('Recipient address enter karo.');
      return;
    }
    if (value == null || value <= 0) {
      msg('Valid ASC amount enter karo.');
      return;
    }
    if (value > widget.session.balance) {
      msg('Insufficient ASC balance.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Transfer'),
        content: Text(
          '${value.toStringAsFixed(8)} ASC\n\nTo:\n$recipient',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => loading = true);
    try {
      final j = await ASCApi.send(recipient, value);
      msg(
        'Transfer submitted. Status: ${j['status']?.toString() ?? 'PENDING'}',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      msg(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void msg(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
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
      appBar: AppBar(title: const Text('SEND ASC')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              title: const Text('Available Balance'),
              subtitle: Text('${widget.session.balance.toStringAsFixed(8)} ASC'),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: address,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Recipient ASC Address',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: scan,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount ASC',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : send,
              icon: const Icon(Icons.send),
              label: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(loading ? 'PROCESSING...' : 'SEND ASC'),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'The server must validate KYC, balance, recipient, nonce/idempotency and authorization before the transfer is finalized.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool found = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SCAN ASC QR')),
      body: MobileScanner(
        onDetect: (capture) {
          if (found) return;
          for (final b in capture.barcodes) {
            final value = b.rawValue;
            if (value != null && value.trim().isNotEmpty) {
              found = true;
              Navigator.pop(context, value.trim());
              return;
            }
          }
        },
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
  List<ASCTransaction> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await ASCApi.transactions();
      if (mounted) setState(() => items = result);
    } catch (e) {
      if (mounted) msg(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void msg(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TRANSACTION HISTORY')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('No transactions yet.'))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final x = items[i];
                      final incoming = x.type.toUpperCase().contains('RECEIVE') ||
                          x.type.toUpperCase().contains('MINING');
                      return Card(
                        child: ListTile(
                          leading: Icon(incoming ? Icons.arrow_downward : Icons.arrow_upward),
                          title: Text(x.type),
                          subtitle: Text(
                            '${x.status}'
                            '${x.date == null ? '' : '\n${x.date!.toLocal()}'}'
                            '${x.txHash.isEmpty ? '' : '\nTX: ${x.txHash}'}',
                          ),
                          trailing: Text(
                            '${incoming ? '+' : '-'}${x.amount.toStringAsFixed(8)}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class AccountPage extends StatelessWidget {
  final Session session;
  const AccountPage({super.key, required this.session});

  void copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ACCOUNT')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge),
              title: const Text('AS COIN ID'),
              subtitle: SelectableText(session.accountId),
              trailing: IconButton(
                onPressed: () => copy(context, session.accountId),
                icon: const Icon(Icons.copy),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Wallet Address'),
              subtitle: SelectableText(session.walletAddress),
              trailing: IconButton(
                onPressed: () => copy(context, session.walletAddress),
                icon: const Icon(Icons.copy),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'KYC: ${session.kycVerified ? 'Verified' : 'Not verified'}\n'
                'Mining: ${session.miningActive ? 'Active' : 'Stopped'}\n'
                'Migration: ${session.migrated ? 'Completed' : 'Pending'}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
