// ============================================================
// LOGIN - GOOGLE ONLY
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool googleLoading = false;

  void showMessage(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  String cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '');
  }

  Future<void> googleSignIn() async {
    if (!Config.backendReady) {
      showMessage(
        'Backend connection is not configured.',
      );
      return;
    }

    if (googleLoading) return;

    setState(() {
      googleLoading = true;
    });

    try {
      final signIn = GoogleSignIn.instance;

      await signIn.initialize(
        serverClientId:
            '236630075813-t27posuu4jb0m1lc9s0qm500eel43id.apps.googleusercontent.com',
      );

      final account = await signIn.authenticate();

      final authentication = account.authentication;

      final idToken = authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw ApiException(
          'Google ID token was not received.',
        );
      }

      final session = await Api.googleLogin(
        idToken,
      );

      if (session.token.isEmpty) {
        throw ApiException(
          'AS COIN login token was not received.',
        );
      }

      await TokenStore.save(
        session.token,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            session: session,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 520,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 30),

                  // AS COIN LOGO
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

                  // GOOGLE LOGIN
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: googleLoading
                          ? null
                          : googleSignIn,
                      icon: googleLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(
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
                    style: TextStyle(
                      color: Colors.white60,
                    ),
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

                  if (!Config.backendReady) ...[
                    const SizedBox(height: 25),
                    const Text(
                      'Backend connection is not configured.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
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
