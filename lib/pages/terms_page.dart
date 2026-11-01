import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/mobile_page_shell.dart';

class TermsPage extends StatefulWidget {
  const TermsPage({super.key});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  bool _agreed = false;

  static const _sections = <_TermSection>[
    _TermSection(
      '1. Acceptance of Terms',
      'By creating an account or using Global Village, you agree to follow these Terms and Conditions and the applicable community rules.',
    ),
    _TermSection(
      '2. Use of the Service',
      'Global Village supports communication, friend discovery, family groups and community activity planning. Users must use these services lawfully and respectfully.',
    ),
    _TermSection(
      '3. User Accounts',
      'You are responsible for providing accurate registration information, protecting your password and reporting unauthorised access to your account.',
    ),
    _TermSection(
      '4. Location Sharing',
      'Location information is shared only when the user chooses to enable a related feature. Users should review the selected audience before sharing a location.',
    ),
    _TermSection(
      '5. Activity and Reservations',
      'Users should provide accurate activity information, respect other participants and update or cancel an activity when plans change.',
    ),
    _TermSection(
      '6. Limitation of Liability',
      'Global Village provides tools for communication and planning. Users remain responsible for their own decisions, meetings and participation in activities.',
    ),
    _TermSection(
      '7. Changes to Terms',
      'These terms may be updated when the service changes. Important updates will be presented to users for review.',
    ),
  ];

  void _continue() {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms and Conditions first.')),
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageShell(
      child: Column(
        children: [
          const GlobalVillageHeader(showBackButton: true),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
              child: Column(
                children: [
                  const AuthPageTitle(
                    title: 'Terms and Conditions',
                    subtitle: 'Please read the following terms carefully.',
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFD7DADF)),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sections.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 18),
                        itemBuilder: (context, index) {
                          final section = _sections[index];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                section.title,
                                style: const TextStyle(
                                  color: AppTheme.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                section.body,
                                style: const TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: 12.5,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: _agreed,
                        activeColor: AppTheme.ink,
                        onChanged: (value) => setState(() => _agreed = value ?? false),
                      ),
                      const Expanded(child: Text('I agree to the Terms and Conditions')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  PrimaryButton(label: 'Agree and Continue', onPressed: _continue),
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.ink),
                    child: const Text('‹ Back to Register'),
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

class _TermSection {
  const _TermSection(this.title, this.body);

  final String title;
  final String body;
}
