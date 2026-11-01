import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Hamburger (☰) drawer for the chat home page.
///
/// Hover design on the menu button:
///  - a tooltip "Menu" appears
///  - the icon lifts with a soft circular highlight background
///  - the icon scales up slightly and shifts to the brand blue
///  - the mouse cursor becomes a click pointer (web)
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    required this.onFindFriends,
    required this.onFriendRequests,
    required this.onTabSelected,
    required this.onChangePassword,
    required this.onSecurityQuestions,
    this.requestCount = 0,
    super.key,
  });

  final VoidCallback onFindFriends;
  final VoidCallback onFriendRequests;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onChangePassword;
  final VoidCallback onSecurityQuestions;
  final int requestCount;

  Future<Map<String, dynamic>?> _loadUser() => AuthService.getCurrentUser();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      width: 300,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: Column(
        children: [
          FutureBuilder<Map<String, dynamic>?>(
            future: _loadUser(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              final name =
                  user?['fullName']?.toString().trim().isNotEmpty == true
                      ? user!['fullName'].toString().trim()
                      : 'Guest';
              final email = user?['email']?.toString() ?? '';
              final initials = name
                  .split(' ')
                  .where((p) => p.isNotEmpty)
                  .take(2)
                  .map((p) => p[0])
                  .join()
                  .toUpperCase();
              return Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 22,
                  bottom: 20,
                  left: 20,
                  right: 20,
                ),
                decoration: const BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(28),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.65),
                          width: 1.6,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initials.isEmpty ? '?' : initials,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 14),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    'QUICK ACTIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Color(0xFF9A9A9A),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _DrawerTile(
                  icon: Icons.search,
                  label: 'Find Friends',
                  subtitle: 'Search users and add friends',
                  colors: AppTheme.blueGradientColors,
                  onTap: () => _closeThen(context, onFindFriends),
                ),
                _DrawerTile(
                  icon: Icons.notifications_active_outlined,
                  label: 'Friend Requests',
                  subtitle: 'View and accept requests',
                  colors: AppTheme.orangeGradientColors,
                  badge: requestCount,
                  onTap: () => _closeThen(context, onFriendRequests),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    'GO TO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Color(0xFF9A9A9A),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _DrawerTile(
                  icon: Icons.chat_bubble_outline,
                  label: 'Messages',
                  subtitle: 'Chats and group chats',
                  colors: AppTheme.tealGradientColors,
                  onTap: () => _closeThen(context, () => onTabSelected(0)),
                ),
                _DrawerTile(
                  icon: Icons.people_outline,
                  label: 'Community',
                  subtitle: 'Activities and members nearby',
                  colors: AppTheme.greenGradientColors,
                  onTap: () => _closeThen(context, () => onTabSelected(1)),
                ),
                _DrawerTile(
                  icon: Icons.family_restroom,
                  label: 'Family',
                  subtitle: 'Family groups and check-ins',
                  colors: AppTheme.purpleGradientColors,
                  onTap: () => _closeThen(context, () => onTabSelected(2)),
                ),
                _DrawerTile(
                  icon: Icons.person_outline,
                  label: 'My Profile',
                  subtitle: 'Profile and interest match',
                  colors: AppTheme.pinkGradientColors,
                  onTap: () => _closeThen(context, () => onTabSelected(3)),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    'SECURITY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Color(0xFF9A9A9A),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _DrawerTile(
                  icon: Icons.lock_outline,
                  label: 'Change Password',
                  colors: const [Color(0xFF9A9A9A), Color(0xFF6F6F6F)],
                  onTap: () => _closeThen(context, onChangePassword),
                ),
                _DrawerTile(
                  icon: Icons.security_outlined,
                  label: 'Security Questions',
                  colors: const [Color(0xFF9A9A9A), Color(0xFF6F6F6F)],
                  onTap: () => _closeThen(context, onSecurityQuestions),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFF0F0F0)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.public, size: 13, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Global Village · v1.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A9A9A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }
}

class _DrawerTile extends StatefulWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.subtitle,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final List<Color> colors;
  final VoidCallback onTap;
  final int badge;

  @override
  State<_DrawerTile> createState() => _DrawerTileState();
}

class _DrawerTileState extends State<_DrawerTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovering ? const Color(0xFFF0F6FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: _hovering
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: widget.colors,
                        )
                      : null,
                  color: _hovering ? null : const Color(0xFFF0F1F3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: _hovering ? Colors.white : AppTheme.ink,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _hovering ? AppTheme.brandDeep : AppTheme.ink,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF9A9A9A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.badge > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: AppTheme.redGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.badge > 9 ? '9+' : '${widget.badge}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
