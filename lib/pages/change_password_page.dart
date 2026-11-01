import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/mobile_page_shell.dart';
import 'login_page.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateNew(String? value) {
    if (value == null || value.length < 6) return 'Use at least 6 characters.';
    if (utf8.encode(value).length > 72) {
      return 'Password is too long (maximum 72 UTF-8 bytes).';
    }
    if (value == _current.text) {
      return 'New password must be different from your current password.';
    }
    return null;
  }

  Future<void> _changePassword() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await AuthService.changePassword(
        currentPassword: _current.text,
        newPassword: _new.text,
        confirmNewPassword: _confirm.text,
      );
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _confirm.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password changed successfully. Please sign in again.'),
      ));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) {
        _showError('Unable to change your password. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: MobilePageShell(
        child: Column(
          children: [
            AuthFlowHeader(
                onBack: _busy ? null : () => Navigator.of(context).pop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                child: Form(
                  key: _formKey,
                  child: AbsorbPointer(
                    absorbing: _busy,
                    child: Column(
                      children: [
                        const AuthPageTitle(
                          title: 'Change Password',
                          subtitle:
                              'After changing your password, sign in again.',
                        ),
                        const SizedBox(height: 24),
                        const FieldLabel('Current Password'),
                        PasswordField(
                          controller: _current,
                          hintText: 'Enter your current password',
                          validator: (value) => (value?.isNotEmpty ?? false)
                              ? null
                              : 'Enter your current password.',
                        ),
                        const SizedBox(height: 20),
                        const FieldLabel('New Password'),
                        PasswordField(
                          controller: _new,
                          hintText: 'Create a new password',
                          validator: _validateNew,
                        ),
                        const SizedBox(height: 20),
                        const FieldLabel('Confirm New Password'),
                        PasswordField(
                          controller: _confirm,
                          hintText: 'Confirm your new password',
                          validator: (value) =>
                              value == _new.text && (value?.isNotEmpty ?? false)
                                  ? null
                                  : 'Passwords do not match.',
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _changePassword(),
                        ),
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: 'Change Password',
                          onPressed: _busy ? null : _changePassword,
                          isBusy: _busy,
                        ),
                      ],
                    ),
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
