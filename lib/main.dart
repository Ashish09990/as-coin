import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const AsCoinApp());
}

class AsCoinApp extends StatelessWidget {
  const AsCoinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AS COIN',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const MiningPage(),
    );
  }
}

class MiningPage extends StatefulWidget {
  const MiningPage({super.key});

  @override
  State<MiningPage> createState() => _MiningPageState();
}

class _MiningPageState extends State<MiningPage> {
  static const int totalMiningDays = 365;
  static const double yearlyMaximum = 50.0;
  static const double maxSupply = 20000000.0;

  int miningDays = 0;
  double balance = 0.0;

  bool mining = false;
  bool kycVerified = false;
  bool coinsLocked = true;

  Timer? timer;

  double get dailyReward => yearlyMaximum / totalMiningDays;

  void startMining() {
    if (!kycVerified) {
      showMessage('KYC verification required.');
      return;
    }

    if (miningDays >= totalMiningDays) {
      showMessage('Your 365-day mining period is complete.');
      return;
    }

    timer?.cancel();

    setState(() {
      mining = true;
    });

    // DEMO ONLY:
    // 1 second represents 1 mining day.
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        miningDays++;

        balance = dailyReward * miningDays;

        if (miningDays >= totalMiningDays) {
          miningDays = totalMiningDays;
          balance = yearlyMaximum;
          mining = false;
          timer.cancel();

          showMessage('Mining completed. You earned 50 ASC.');
        }
      });
    });
  }

  void stopMining() {
    timer?.cancel();

    setState(() {
      mining = false;
    });
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = miningDays / totalMiningDays;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AS COIN • ASC'),
      ),

      body: ListView(
        padding: const EdgeInsets.all(18),

        children: [

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(
                    'AS COIN',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium,
                  ),

                  const Text(
                    'ASC • Testnet',
                  ),

                  const SizedBox(height: 20),

                  Text(
                    '${balance.toStringAsFixed(6)} ASC',
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall,
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Mining: $miningDays / 365 days',
                  ),

                  const SizedBox(height: 10),

                  LinearProgressIndicator(
                    value: progress,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Column(
              children: [

                SwitchListTile(
                  title: const Text(
                    'KYC Verification',
                  ),

                  subtitle: const Text(
                    'Demo verification status',
                  ),

                  value: kycVerified,

                  onChanged: (value) {

                    setState(() {
                      kycVerified = value;
                    });

                  },
                ),

                ListTile(
                  leading: Icon(
                    coinsLocked
                        ? Icons.lock
                        : Icons.lock_open,
                  ),

                  title: const Text(
                    'Coin Lock',
                  ),

                  subtitle: Text(
                    coinsLocked
                        ? 'Coins locked before launch'
                        : 'Coins unlocked',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 52,

            child: FilledButton.icon(

              onPressed:
                  miningDays >= totalMiningDays
                      ? null
                      : mining
                          ? stopMining
                          : startMining,

              icon: Icon(
                mining
                    ? Icons.pause
                    : Icons.bolt,
              ),

              label: Text(
                mining
                    ? 'STOP MINING'
                    : miningDays >= totalMiningDays
                        ? 'MINING COMPLETE'
                        : 'START MINING',
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [

                  Text(
                    'AS COIN PROTOCOL',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge,
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Maximum Supply: '
                    '${maxSupply.toStringAsFixed(0)} ASC',
                  ),

                  const Text(
                    'First Year Maximum: 50 ASC / User',
                  ),

                  Text(
                    'Daily Mining Rate: '
                    '${dailyReward.toStringAsFixed(15)} ASC',
                  ),

                  const Text(
                    'Mining Period: 365 Days',
                  ),

                  const Text(
                    'Quarterly Reward Cycle: 90 Days',
                  ),

                  const Text(
                    'Launch Lock: Enabled',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(

            onPressed: () {

              showMessage(
                coinsLocked
                    ? 'Wallet transfers are locked until launch.'
                    : 'Wallet transfer enabled.',
              );

            },

            icon: const Icon(
              Icons.account_balance_wallet,
            ),

            label: const Text(
              'WALLET',
            ),
          ),
        ],
      ),
    );
  }
}
