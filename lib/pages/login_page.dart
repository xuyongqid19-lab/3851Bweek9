import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/mobile_page_shell.dart';
import '../widgets/google_sign_in_web_button_stub.dart'
    if (dart.library.html) '../widgets/google_sign_in_web_button.dart';
import 'forgot_password_page.dart';
import 'home_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  static Future<void>? _googleInitialization;

  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  StreamSubscription<GoogleSignInAuthenticationEvent>?
      _googleAuthenticationSubscription;
  bool _isLoggingIn = false;
  bool _isGoogleSigningIn = false;
  bool _googleReady = false;
  bool _googleLoginCompleted = false;
  String? _googleSetupError;

  @override
  void initState() {
    super.initState();
    _prepareGoogleSignIn();
  }

  @override
  void dispose() {
    _googleAuthenticationSubscription?.cancel();
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false) || _isLoggingIn) return;

    setState(() => _isLoggingIn = true);
    try {
      await AuthService.login(
        account: _accountController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    } on AuthException catch (error) {
      if (mounted) _showGoogleMessage(error.message);
    } catch (_) {
      if (mounted) _showGoogleMessage('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _prepareGoogleSignIn() async {
    if (_googleWebClientId.isEmpty) {
      if (mounted) {
        setState(() {
          _googleSetupError =
              'Google Sign-In is not configured. Add GOOGLE_WEB_CLIENT_ID.';
        });
      }
      return;
    }

    try {
      _googleInitialization ??= _googleSignIn.initialize(
        clientId: kIsWeb ? _googleWebClientId : null,
        serverClientId: kIsWeb ? null : _googleWebClientId,
      );
      await _googleInitialization;

      _googleAuthenticationSubscription ??=
          _googleSignIn.authenticationEvents.listen(
        _handleGoogleAuthenticationEvent,
        onError: _handleGoogleAuthenticationError,
      );

      if (mounted) {
        setState(() {
          _googleReady = true;
          _googleSetupError = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _googleSetupError =
            'Google Sign-In setup failed. Check the OAuth client configuration.';
      });
    }
  }

  void _handleGoogleAuthenticationEvent(
    GoogleSignInAuthenticationEvent event,
  ) {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      unawaited(_completeGoogleSignIn(event.user));
    }
  }

  void _handleGoogleAuthenticationError(Object error) {
    if (!mounted) return;
    _showGoogleMessage('Google Sign-In failed. Please try again.');
  }

  Future<void> _loginWithGoogle() async {
    FocusScope.of(context).unfocus();
    if (_isGoogleSigningIn || !_googleReady) {
      _showGoogleSetupMessage();
      return;
    }

    // On the web, Google requires its SDK-rendered button. The button itself
    // starts the sign-in flow, so this method is only used on Android/mobile.
    if (kIsWeb) return;

    setState(() => _isGoogleSigningIn = true);

    try {
      await _googleSignIn.authenticate();
      // Successful authentication is handled by authenticationEvents on both
      // Android and Web so the database flow stays identical.
    } on GoogleSignInException catch (error) {
      if (!mounted || error.code == GoogleSignInExceptionCode.canceled) return;

      if (error.code == GoogleSignInExceptionCode.clientConfigurationError) {
        _showGoogleMessage(
          'Google Sign-In configuration error. Check the Web OAuth client ID, '
          'Android package name and SHA fingerprint.',
        );
      } else {
        _showGoogleMessage(
          error.description ?? 'Google Sign-In failed. Please try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showGoogleMessage('Google Sign-In failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleSigningIn = false);
      }
    }
  }

  Future<void> _completeGoogleSignIn(GoogleSignInAccount account) async {
    if (!mounted || _googleLoginCompleted) return;
    _googleLoginCompleted = true;

    try {
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException(
          'Google did not return an ID token. Please sign in again.',
        );
      }

      await AuthService.loginWithGoogle(idToken: idToken);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    } on AuthException catch (error) {
      _googleLoginCompleted = false;
      if (mounted) _showGoogleMessage(error.message);
    } catch (_) {
      _googleLoginCompleted = false;
      if (mounted) {
        _showGoogleMessage('Google account could not be saved. Please try again.');
      }
    }
  }

  void _showGoogleSetupMessage() {
    _showGoogleMessage(
      _googleSetupError ??
          'Google Sign-In is still initializing. Please try again.',
    );
  }

  void _showGoogleMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildGoogleSignInButton() {
    if (!_googleReady) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: _showGoogleSetupMessage,
          child: const Text('Continue with Google'),
        ),
      );
    }

    if (kIsWeb) {
      return Center(child: buildGoogleSignInWebButton());
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: _isGoogleSigningIn ? null : _loginWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.ink,
          side: const BorderSide(
            color: Color(0xFFB7BBC1),
            width: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: _isGoogleSigningIn
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'G',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageShell(
      child: Column(
        children: [
          const GlobalVillageHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(30, 34, 30, 34),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    children: [
                      const AuthPageTitle(
                        title: 'Login',
                        subtitle: 'Welcome back! Please login to your account.',
                      ),
                      const SizedBox(height: 38),
                      const FieldLabel('Username / Email'),
                      TextFormField(
                        controller: _accountController,
                        validator: _required,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        decoration: const InputDecoration(
                          hintText: 'Enter your username or email',
                        ),
                      ),
                      const SizedBox(height: 22),
                      const FieldLabel('Password'),
                      PasswordField(
                        controller: _passwordController,
                        hintText: 'Enter your password',
                        validator: _required,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ForgotPasswordPage(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.ink,
                          ),
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      OutlineActionButton(
                        label: _isLoggingIn ? 'Logging in...' : 'Login',
                        onPressed: _isLoggingIn ? null : _login,
                      ),
                      const SizedBox(height: 36),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: Color(0xFFCCCCCC))),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'or',
                              style: TextStyle(color: AppTheme.muted),
                            ),
                          ),
                          Expanded(child: Divider(color: Color(0xFFCCCCCC))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildGoogleSignInButton(),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const RegisterPage(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.ink,
                        ),
                        child: const Text('No account? Register'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
