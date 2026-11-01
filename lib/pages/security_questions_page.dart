import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/mobile_page_shell.dart';
import '../widgets/security_questions_form.dart';

class SecurityQuestionsPage extends StatefulWidget {
  const SecurityQuestionsPage({super.key});

  @override
  State<SecurityQuestionsPage> createState() => _SecurityQuestionsPageState();
}

class _SecurityQuestionsPageState extends State<SecurityQuestionsPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _questions = SecurityQuestionsController();
  bool _loading = true;
  bool _saving = false;
  bool _configured = false;
  bool _hasLocalPassword = false;
  List<String> _savedQuestions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _currentPassword.dispose();
    _questions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await AuthService.fetchSecurityQuestions();
      if (!mounted) return;
      setState(() {
        _configured = status['configured'] == true;
        _hasLocalPassword = status['hasLocalPassword'] == true;
        _savedQuestions = (status['questions'] as List).cast<String>();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is AuthException
            ? error.message
            : 'Unable to load security questions. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final values = _questions.values;
      await AuthService.saveSecurityQuestions(
        currentPassword: _currentPassword.text,
        securityQuestions: values,
      );
      if (!mounted) return;
      _currentPassword.clear();
      for (final answer in _questions.answers) {
        answer.clear();
      }
      setState(() {
        _configured = true;
        _savedQuestions = values.map((item) => item['question']!).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Security questions saved successfully.'),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is AuthException
              ? error.message
              : 'Unable to save security questions. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: MobilePageShell(
            child: Column(children: [
          AuthFlowHeader(
              onBack: _saving ? null : () => Navigator.of(context).pop()),
          Expanded(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(children: [
              const AuthPageTitle(
                  title: 'Security Questions',
                  subtitle:
                      'Set or replace all three questions. Your current password is required.'),
              const SizedBox(height: 24),
              if (_loading)
                const CircularProgressIndicator()
              else if (_error != null) ...[
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ] else ...[
                Text(_configured
                    ? 'Three security questions are configured.'
                    : 'Three security questions are not yet configured.'),
                for (var i = 0; i < _savedQuestions.length; i++)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Question ${i + 1}: ${_savedQuestions[i]}')),
                const SizedBox(height: 20),
                if (!_hasLocalPassword)
                  const Text(
                      'This account uses Google sign-in and has no local password. Security questions require a local password. Continue using Google sign-in.')
                else
                  Form(
                      key: _formKey,
                      child: AbsorbPointer(
                        absorbing: _saving,
                        child: Column(children: [
                          const Text(
                              'Existing answers are never displayed. Enter three new answers to save.'),
                          const SizedBox(height: 20),
                          const FieldLabel('Current Password'),
                          PasswordField(
                              controller: _currentPassword,
                              hintText: 'Enter your current password',
                              validator: (value) => (value?.isNotEmpty ?? false)
                                  ? null
                                  : 'Enter your current password.'),
                          const SizedBox(height: 20),
                          SecurityQuestionsForm(controller: _questions),
                          PrimaryButton(
                              label: 'Save Security Questions',
                              onPressed: _saving ? null : _save,
                              isBusy: _saving),
                        ]),
                      )),
              ],
            ]),
          )),
        ])),
      );
}
