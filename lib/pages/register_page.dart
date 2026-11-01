import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/security_questions_form.dart';
import '../widgets/mobile_page_shell.dart';
import 'terms_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _interestController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _securityQuestions = SecurityQuestionsController();
  bool _configureSecurityQuestions = false;

  bool _agreedToTerms = false;
  bool _isRegistering = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _birthDateController.dispose();
    _interestController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _securityQuestions.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final email = value!.trim();
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    return valid ? null : 'Enter a valid email address.';
  }

  String? _validatePhone(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final digits = value!.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8 ? null : 'Enter a valid phone number.';
  }

  String? _validatePassword(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    return value!.length >= 6 ? null : 'Use at least 6 characters.';
  }

  String? _validateConfirmPassword(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    return value == _passwordController.text ? null : 'Passwords do not match.';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (selected == null) return;
    _birthDateController.text = '${selected.day.toString().padLeft(2, '0')}/'
        '${selected.month.toString().padLeft(2, '0')}/'
        '${selected.year}';
  }

  Future<void> _openTerms() async {
    final agreed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const TermsPage()),
    );
    if (agreed == true && mounted) {
      setState(() => _agreedToTerms = true);
    }
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid || _isRegistering) return;

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Please read and agree to the Terms and Conditions.')),
      );
      return;
    }

    setState(() => _isRegistering = true);
    try {
      await AuthService.register(
        fullName: _fullNameController.text.trim(),
        birthDate: _birthDateController.text.trim(),
        interest: _interestController.text.trim(),
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        securityQuestions:
            _configureSecurityQuestions ? _securityQuestions.values : const [],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful. Please login.')),
      );
      Navigator.of(context).pop();
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  Widget _gap() => const SizedBox(height: 18);

  @override
  Widget build(BuildContext context) {
    return MobilePageShell(
      child: Column(
        children: [
          const GlobalVillageHeader(showBackButton: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const AuthPageTitle(
                      title: 'Register',
                      subtitle:
                          'Create your account to get started. Fields marked * are required.',
                    ),
                    const SizedBox(height: 30),
                    const FieldLabel('Full Name *'),
                    TextFormField(
                      controller: _fullNameController,
                      validator: _required,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          hintText: 'Enter your full name'),
                    ),
                    _gap(),
                    const FieldLabel('Date of Birth *'),
                    TextFormField(
                      controller: _birthDateController,
                      validator: _required,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: const InputDecoration(
                        hintText: 'Select your date of birth',
                        suffixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                    ),
                    _gap(),
                    const FieldLabel('Interest'),
                    TextFormField(
                      controller: _interestController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Enter your interest (optional)',
                      ),
                    ),
                    _gap(),
                    const FieldLabel('Username *'),
                    TextFormField(
                      controller: _usernameController,
                      validator: _required,
                      textInputAction: TextInputAction.next,
                      decoration:
                          const InputDecoration(hintText: 'Choose a username'),
                    ),
                    _gap(),
                    const FieldLabel('Email *'),
                    TextFormField(
                      controller: _emailController,
                      validator: _validateEmail,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration:
                          const InputDecoration(hintText: 'Enter your email'),
                    ),
                    _gap(),
                    const FieldLabel('Phone *'),
                    TextFormField(
                      controller: _phoneController,
                      validator: _validatePhone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          hintText: 'Enter your phone number'),
                    ),
                    _gap(),
                    const FieldLabel('Password *'),
                    PasswordField(
                      controller: _passwordController,
                      hintText: 'Create a password',
                      validator: _validatePassword,
                    ),
                    _gap(),
                    const FieldLabel('Confirm Password *'),
                    PasswordField(
                      controller: _confirmPasswordController,
                      hintText: 'Confirm your password',
                      validator: _validateConfirmPassword,
                    ),
                    _gap(),
                    Material(
                        color: Colors.white,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Security Questions (Optional)'),
                          subtitle: const Text(
                              'Set all three now, or add them later in My Profile.'),
                          value: _configureSecurityQuestions,
                          onChanged: _isRegistering
                              ? null
                              : (value) => setState(() {
                                    _configureSecurityQuestions = value;
                                    if (!value) _securityQuestions.clear();
                                  }),
                        )),
                    if (_configureSecurityQuestions)
                      SecurityQuestionsForm(controller: _securityQuestions),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _agreedToTerms,
                          activeColor: AppTheme.ink,
                          onChanged: (value) {
                            setState(() => _agreedToTerms = value ?? false);
                          },
                        ),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('I agree to the '),
                              InkWell(
                                onTap: _openTerms,
                                child: const Text(
                                  'Terms and Conditions',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlineActionButton(
                      label: _isRegistering ? 'Registering...' : 'Register',
                      onPressed: _isRegistering ? null : _register,
                    ),
                    const SizedBox(height: 8),
                    UnderlineTextButton(
                      label: 'Back to Login',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
