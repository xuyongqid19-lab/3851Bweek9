import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_widgets.dart';
import 'home_page.dart';

class AddFriendPage extends StatefulWidget {
  final ChatUser user;

  const AddFriendPage({super.key, required this.user});

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final _messageController = TextEditingController();
  int _charCount = 0;
  bool _requestSent = false;
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final service = ChatService();
      final status =
          await service.sendFriendRequest(widget.user, _messageController.text);
      service.close();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _requestSent = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'accepted'
              ? 'You are now friends'
              : 'Friend request sent successfully'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _AddFriendHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 28),
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.white,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFB7BBC1),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_outlined,
                        size: 40,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Send Friend Request',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "You're about to send a friend request to",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email ?? user.username ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Add a message (optional)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFB7BBC1)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Stack(
                      children: [
                        TextField(
                          controller: _messageController,
                          maxLength: 120,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(120),
                          ],
                          onChanged: (v) {
                            setState(() => _charCount = v.length);
                          },
                          decoration: const InputDecoration(
                            hintText: 'Write a short message...',
                            hintStyle: TextStyle(
                              color: Color(0xFF9A9A9A),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                            counterText: '',
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 10,
                          child: Text(
                            '$_charCount/120',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9A9A9A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFB7BBC1)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.alternate_email,
                          title: 'Email',
                          subtitle: user.email ?? 'Not provided',
                        ),
                        const Divider(height: 1, color: Color(0xFFF0F0F0)),
                        _InfoRow(
                          icon: Icons.star_outline,
                          title: 'Interest',
                          subtitle: (user.interest?.isNotEmpty ?? false)
                              ? user.interest!
                              : 'Not provided',
                        ),
                        const Divider(height: 1, color: Color(0xFFF0F0F0)),
                        _InfoRow(
                          icon: Icons.login,
                          title: 'Sign-in provider',
                          subtitle:
                              (user.authProvider ?? 'local').contains('google')
                                  ? 'Google account'
                                  : 'Email and password',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _requestSent || _sending ? null : _sendRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.ink,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF777777),
                        disabledForegroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _requestSent
                            ? 'Request Sent'
                            : (_sending ? 'Sending...' : 'Send Request'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.ink,
                        side: const BorderSide(color: Color(0xFFB7BBC1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          BottomNav(
            selectedIndex: 0,
            onSelected: (i) => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => HomePage(initialTabIndex: i)),
              (route) => false,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddFriendHeader extends StatelessWidget {
  const _AddFriendHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      color: Colors.white,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 48),
            Expanded(
              child: Text(
                'Add Friend',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ),
            SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppTheme.ink),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
