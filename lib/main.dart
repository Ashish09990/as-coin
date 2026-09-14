import 'package:flutter/material.dart';

void main() {
  runApp(const ASCoinApp());
}

class ASCoinApp extends StatelessWidget {
  const ASCoinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AS COIN',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const LoginPage(),
    );
  }
}

/* =========================
   LOGIN
========================= */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final country = TextEditingController(text: '+91');
  final phone = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.monetization_on,
                size: 90,
              ),
              const SizedBox(height: 15),
              const Text(
                'AS COIN',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'ASC • Digital Reward Network',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 45),

              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: country,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (phone.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mobile number enter karo'),
                        ),
                      );
                      return;
                    }

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HomePage(),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(15),
                    child: Text('CONTINUE'),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              const Text(
                'Production version mein OTP server verification required hai.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* =========================
   HOME
========================= */

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double balance = 0.0;
  bool mining = false;
  bool kyc = false;

  static const double dailyRate = 0.14;

  void startMining() {
    setState(() {
      mining = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mining started • Maximum 0.14 ASC/day'),
      ),
    );
  }

  void claimReward() {
    if (!mining) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pehle mining start karo'),
        ),
      );
      return;
    }

    setState(() {
      balance += dailyRate;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('0.14 ASC reward credited'),
      ),
    );
  }

  void openKyc() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KycPage(
          onVerified: () {
            setState(() {
              kyc = true;
            });
          },
        ),
      ),
    );
  }

  void openWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WalletPage(
          balance: balance,
          kyc: kyc,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AS COIN • ASC'),
        actions: [
          IconButton(
            onPressed: openWallet,
            icon: const Icon(Icons.account_balance_wallet),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          /* BALANCE */

          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AS COIN',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const Text(
                    'ASC • Network',
                    style: TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    '${balance.toStringAsFixed(8)} ASC',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Maximum mining rate: 0.14 ASC / day',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          /* MINING */

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
                        child: Text(
                          'Mining',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        mining ? 'ACTIVE' : 'STOPPED',
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

                  LinearProgressIndicator(
                    value: mining ? 0.5 : 0,
                  ),

                  const SizedBox(height: 15),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: startMining,
                      child: Text(
                        mining ? 'MINING ACTIVE' : 'START MINING',
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  OutlinedButton(
                    onPressed: claimReward,
                    child: const Text(
                      'SYNC / CLAIM DAILY REWARD',
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          /* KYC */

          Card(
            child: ListTile(
              leading: Icon(
                kyc
                    ? Icons.verified
                    : Icons.verified_user_outlined,
              ),
              title: const Text(
                'KYC Verification',
              ),
              subtitle: Text(
                kyc
                    ? 'KYC verified'
                    : 'KYC available immediately • Fee 1 USDT',
              ),
              trailing: FilledButton(
                onPressed: kyc ? null : openKyc,
                child: Text(
                  kyc ? 'VERIFIED' : 'KYC',
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          /* PROTOCOL */

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'AS COIN PROTOCOL',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 15),
                  Text('Daily Maximum: 0.14 ASC'),
                  Text('Mining End: 2130'),
                  Text('KYC: Immediate'),
                  Text('Normal KYC Fee: 1 USDT'),
                  Text('Migration: 365 days'),
                  Text('User Transfers: Available after verification'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================
   KYC
========================= */

class KycPage extends StatefulWidget {
  final VoidCallback onVerified;

  const KycPage({
    super.key,
    required this.onVerified,
  });

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  final code = TextEditingController();

  // IMPORTANT:
  // Production mein secret ko app ke andar hard-code mat karna.
  static const ownerCode = 'Ashish@09bs';

  bool processing = false;

  void submit() async {
    setState(() {
      processing = true;
    });

    await Future.delayed(const Duration(seconds: 1));

    if (code.text == ownerCode) {
      widget.onVerified();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Owner KYC authorization accepted'),
          ),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Production KYC mein 1 USDT payment blockchain se verify hogi.',
            ),
          ),
        );
      }
    }

    setState(() {
      processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KYC Verification'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.verified_user,
              size: 70,
            ),

            const SizedBox(height: 20),

            const Text(
              'KYC available immediately',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Normal users: 1 USDT • TRC20',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            TextField(
              controller: code,
              decoration: const InputDecoration(
                labelText: 'Special authorization code',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: processing ? null : submit,
                child: Text(
                  processing ? 'VERIFYING...' : 'VERIFY KYC',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   WALLET
========================= */

class WalletPage extends StatelessWidget {
  final double balance;
  final bool kyc;

  const WalletPage({
    super.key,
    required this.balance,
    required this.kyc,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASC WALLET'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [

            Card(
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      size: 55,
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Wallet Balance',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${balance.toStringAsFixed(8)} ASC',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            ListTile(
              leading: const Icon(Icons.verified),
              title: const Text('KYC Status'),
              subtitle: Text(
                kyc ? 'Verified' : 'Not verified',
              ),
            ),

            const Divider(),

            ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Send ASC'),
              subtitle: const Text(
                'Available for verified accounts',
              ),
              onTap: () {
                if (!kyc) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'KYC verification required',
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Production wallet transfer requires backend',
                      ),
                    ),
                  );
                }
              },
            ),

            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Transaction History'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Transaction ledger will be server controlled',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
