import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/mobile_page_shell.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailKey = GlobalKey<FormFieldState<String>>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _accountController = TextEditingController();
  final _answerControllers = List.generate(3, (_) => TextEditingController());
  bool _securityMode = false;
  List<String>? _questions;
  String? _challenge;
  String? _resetToken;
  Timer? _timer;
  DateTime? _resendAt;
  int _secondsLeft = 0;
  bool _sending = false;
  bool _resetting = false;
  String? _requestedEmail;
  String? _notice;

  bool get _busy => _sending || _resetting;
  String get _email => _emailController.text.trim().toLowerCase();

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _accountController.dispose();
    for (final answer in _answerControllers) {
      answer.dispose();
    }
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    return email.length <= 254 &&
            RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                .hasMatch(email)
        ? null
        : 'Enter a valid email address.';
  }

  String? _validateCode(String? value) {
    return RegExp(r'^\d{6}$').hasMatch((value ?? '').trim())
        ? null
        : 'Enter the 6-digit code.';
  }

  String? _validatePassword(String? value) {
    if (value == null || value.length < 6) return 'Use at least 6 characters.';
    if (utf8.encode(value).length > 72) {
      return 'Password is too long (maximum 72 UTF-8 bytes).';
    }
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _switchMethod(bool security) {
    if (_busy || security == _securityMode) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    setState(() {
      _securityMode = security;
      _emailController.clear();
      _codeController.clear();
      _accountController.clear();
      for (final answer in _answerControllers) {
        answer.clear();
      }
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _requestedEmail = null;
      _notice = null;
      _questions = null;
      _challenge = null;
      _resetToken = null;
    });
    // Keep the existing email resend deadline even when its inputs are cleared.
  }

  Future<void> _securityContinue() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _resetting = true);
    try {
      if (_challenge == null && _resetToken == null) {
        final response = await AuthService.identifySecurityQuestion(
          _accountController.text,
        );
        final questions = response['questions'];
        final challenge = response['challenge'];
        if (questions is! List ||
            questions.length != 3 ||
            questions
                .any((question) => question is! String || question.isEmpty) ||
            challenge is! String ||
            challenge.isEmpty) {
          throw const AuthException(
              'The login server returned an invalid response.');
        }
        if (!mounted) return;
        setState(() {
          _questions = questions.cast<String>();
          _challenge = challenge;
        });
      } else if (_resetToken == null) {
        final response = await AuthService.verifySecurityAnswer(
          challenge: _challenge!,
          answers: _answerControllers.map((answer) => answer.text).toList(),
        );
        final token = response['resetToken'];
        if (token is! String || token.isEmpty) {
          throw const AuthException(
              'The login server returned an invalid response.');
        }
        if (!mounted) return;
        setState(() {
          _resetToken = token;
          for (final answer in _answerControllers) {
            answer.clear();
          }
          _challenge = null;
        });
      } else {
        await AuthService.resetPasswordWithSecurityQuestion(
          resetToken: _resetToken!,
          newPassword: _newPasswordController.text,
          confirmNewPassword: _confirmPasswordController.text,
        );
        if (!mounted) return;
        _resetToken = null;
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password Reset Successfully')),
        );
        setState(() {
          _questions = null;
          _challenge = null;
          _resetting = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } on AuthException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) {
        _showError(
            'Unable to verify or reset your password. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  void _restartSecurity() {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    setState(() {
      _questions = null;
      _challenge = null;
      _resetToken = null;
      for (final answer in _answerControllers) {
        answer.clear();
      }
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    });
  }

  void _goBack() {
    if (_busy) return;
    if (_securityMode && (_challenge != null || _resetToken != null)) {
      _restartSecurity();
    } else {
      Navigator.of(context).pop();
    }
  }

  List<Widget> _securityFields() {
    return [
      const Text(
        'Use your registered email address or username. Email access is not required. '
        'If this method cannot verify your account, try Email Verification. '
        'Google-only accounts should use Google sign-in.',
        style: TextStyle(color: AppTheme.muted, fontSize: 12.5, height: 1.4),
      ),
      const SizedBox(height: 24),
      if (_resetToken == null) ...[
        const FieldLabel('Email Address or Username'),
        TextFormField(
          key: const ValueKey('security-account'),
          controller: _accountController,
          readOnly: _busy || _challenge != null,
          validator: (value) => (value ?? '').trim().isEmpty
              ? 'Enter your email address or username.'
              : null,
          decoration:
              const InputDecoration(hintText: 'Enter your email or username'),
        ),
        if (_questions != null)
          for (var index = 0; index < 3; index++) ...[
            const SizedBox(height: 20),
            FieldLabel('Question ${index + 1}'),
            Align(
                alignment: Alignment.centerLeft,
                child: Text(_questions![index])),
            const SizedBox(height: 10),
            FieldLabel('Answer ${index + 1}'),
            PasswordField(
              key: ValueKey('security-answer-$index'),
              controller: _answerControllers[index],
              hintText: 'Enter your security answer',
              validator: (value) =>
                  (value ?? '').trim().isEmpty || value!.trim().length > 200
                      ? 'Enter an answer of 1 to 200 characters.'
                      : null,
              textInputAction:
                  index == 2 ? TextInputAction.done : TextInputAction.next,
              onFieldSubmitted: index == 2 ? (_) => _securityContinue() : null,
            ),
          ],
      ] else ...[
        const Text(
            'All three answers are verified. Reset your password within 5 minutes.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
        const SizedBox(height: 20),
        const FieldLabel('New Password'),
        PasswordField(
          key: const ValueKey('security-new-password'),
          controller: _newPasswordController,
          hintText: 'Create a new password',
          validator: _validatePassword,
        ),
        const SizedBox(height: 20),
        const FieldLabel('Confirm New Password'),
        PasswordField(
          key: const ValueKey('security-confirm-password'),
          controller: _confirmPasswordController,
          hintText: 'Confirm your new password',
          validator: (value) => value == _newPasswordController.text &&
                  (value?.isNotEmpty ?? false)
              ? null
              : 'Passwords do not match.',
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _securityContinue(),
        ),
      ],
      const SizedBox(height: 24),
      PrimaryButton(
        label: _resetToken != null
            ? 'Reset Password'
            : _challenge != null
                ? 'Verify Answers'
                : 'Continue',
        onPressed: _busy ? null : _securityContinue,
        isBusy: _resetting,
      ),
      if (_questions != null)
        TextButton(
          onPressed: _busy ? null : _restartSecurity,
          child: Text(_resetToken != null ? 'Start again' : 'Back to account'),
        ),
      const SizedBox(height: 6),
      UnderlineTextButton(
        label: 'Back to Login',
        onPressed: () {
          if (!_busy) Navigator.of(context).pop();
        },
      ),
    ];
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    _resendAt = DateTime.now().add(Duration(seconds: seconds));
    setState(() => _secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining =
          (_resendAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
      setState(() => _secondsLeft = remaining > 0 ? remaining : 0);
      if (_secondsLeft == 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (_busy || _secondsLeft > 0) return;
    if (!(_emailKey.currentState?.validate() ?? false)) return;
    final target = _email;
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      final response = await AuthService.requestPasswordResetCode(target);
      if (!mounted) return;
      setState(() {
        _requestedEmail = target;
        _codeController.clear();
        _notice = response['message']?.toString() ??
            'If this email has a password account, check your inbox and spam folder.';
      });
      _startCountdown((response['retryAfterSeconds'] as num?)?.toInt() ?? 60);
    } on AuthException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Unable to send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_requestedEmail != _email) {
      _showError('Request a code for this email address first.');
      return;
    }
    setState(() => _resetting = true);
    try {
      await AuthService.resetPassword(
        email: _email,
        code: _codeController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset successfully. Sign in with your new password.',
          ),
        ),
      );
      setState(() => _resetting = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } on AuthException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) {
        _showError('Unable to reset your password. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy &&
          !(_securityMode && (_challenge != null || _resetToken != null)),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBack();
      },
      child: MobilePageShell(
        child: Column(
          children: [
            AuthFlowHeader(onBack: _busy ? null : _goBack),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const AuthPageTitle(
                        title: 'Forgot Password',
                        subtitle: 'Choose a way to reset your password.',
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                          builder: (context, constraints) => ToggleButtons(
                                constraints: BoxConstraints(
                                    minHeight: 48,
                                    maxWidth: (constraints.maxWidth - 3) / 2),
                                textStyle: const TextStyle(fontSize: 14),
                                isSelected: [!_securityMode, _securityMode],
                                onPressed: _busy
                                    ? null
                                    : (index) => _switchMethod(index == 1),
                                color: AppTheme.ink,
                                selectedColor: Colors.white,
                                fillColor: AppTheme.ink,
                                borderColor: AppTheme.border,
                                selectedBorderColor: AppTheme.ink,
                                borderRadius: BorderRadius.circular(7),
                                children: const [
                                  Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 10),
                                      child: Text('Email Verification')),
                                  Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 10),
                                      child: Text('Security Question')),
                                ],
                              )),
                      const SizedBox(height: 24),
                      if (_securityMode)
                        ..._securityFields()
                      else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F8F8),
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Text(
                            'Use the email address you registered with. Codes expire in 10 minutes. '
                            'Only the newest code works. If you signed up only with Google, use Google sign-in.',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const FieldLabel('Email Address'),
                        TextFormField(
                          key: _emailKey,
                          controller: _emailController,
                          readOnly: _busy,
                          validator: _validateEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          onChanged: (_) {
                            if (_requestedEmail != null &&
                                _email != _requestedEmail) {
                              setState(() {
                                _requestedEmail = null;
                                _notice = null;
                                _codeController.clear();
                              });
                            }
                          },
                          decoration: const InputDecoration(
                            hintText: 'Enter your registered email',
                          ),
                        ),
                        const SizedBox(height: 18),
                        OutlineActionButton(
                          label: _sending
                              ? 'Sending...'
                              : _secondsLeft > 0
                                  ? 'Resend in ${_secondsLeft}s'
                                  : 'Send Code',
                          onPressed:
                              _busy || _secondsLeft > 0 ? null : _sendCode,
                        ),
                        if (_notice != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _notice!,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const FieldLabel('Verification Code'),
                        TextFormField(
                          controller: _codeController,
                          readOnly: _busy,
                          validator: _validateCode,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          autofillHints: const [AutofillHints.oneTimeCode],
                          maxLength: 6,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Enter the 6-digit code',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 20),
                        const FieldLabel('New Password'),
                        PasswordField(
                          controller: _newPasswordController,
                          hintText: 'Create a new password',
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 20),
                        const FieldLabel('Confirm Password'),
                        PasswordField(
                          controller: _confirmPasswordController,
                          hintText: 'Confirm your new password',
                          validator: (value) =>
                              value == _newPasswordController.text &&
                                      (value?.isNotEmpty ?? false)
                                  ? null
                                  : 'Passwords do not match.',
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _resetPassword(),
                        ),
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: 'Reset Password',
                          onPressed: _busy ? null : _resetPassword,
                          isBusy: _resetting,
                        ),
                        const SizedBox(height: 6),
                        UnderlineTextButton(
                          label: 'Back to Login',
                          onPressed: () {
                            if (!_busy) Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ],
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
