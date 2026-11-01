import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/mobile_page_shell.dart';
import 'login_page.dart';

class MainPlaceholderPage extends StatelessWidget {
  const MainPlaceholderPage({super.key});

  void _logout(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageShell(
      child: Column(
        children: [
          const GlobalVillageHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline, size: 76, color: AppTheme.ink),
                  const SizedBox(height: 20),
                  Text(
                    'Login Successful',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This is a temporary destination page. The team can connect the completed Chat, Activity, Family and Profile modules here later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted, height: 1.5),
                  ),
                  const SizedBox(height: 34),
                  PrimaryButton(label: 'Log Out', onPressed: () => _logout(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
