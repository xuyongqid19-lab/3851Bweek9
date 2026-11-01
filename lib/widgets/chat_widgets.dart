import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../services/chat_sessions_state.dart';
import '../theme/app_theme.dart';

/// Circular icon button with a rich web hover treatment:
/// tooltip + soft highlight circle + scale lift + brand color shift.
class HoverIconButton extends StatefulWidget {
  const HoverIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.size = 24,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  @override
  State<HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<HoverIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: widget.onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) {
          if (widget.onTap != null) setState(() => _hovering = true);
        },
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _hovering ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 160),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _hovering
                    ? const Color(0xFFEAF2FE)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  widget.icon,
                  key: ValueKey('icon-${widget.icon}-$_hovering'),
                  size: widget.size,
                  color: _hovering ? AppTheme.brand : AppTheme.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Navbar extends StatelessWidget {
  const Navbar({
    this.notificationCount = 0,
    this.onNotificationTap,
    this.onMenuTap,
    super.key,
  });

  final int notificationCount;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                HoverIconButton(
                  icon: Icons.menu,
                  tooltip: 'Menu · Messages, friends and settings',
                  onTap: onMenuTap ??
                      () => Scaffold.of(context).openDrawer(),
                ),
                const Spacer(),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BrandDot(),
                    SizedBox(width: 8),
                    Text(
                      'Global Village',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                HoverIconButton(
                  icon: Icons.notifications_outlined,
                  tooltip: notificationCount > 0
                      ? '$notificationCount new friend request(s)'
                      : 'Friend requests',
                  onTap: onNotificationTap,
                ),
              ],
            ),
          ),
          Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  AppTheme.brandTeal.withValues(alpha: 0.55),
                  AppTheme.brand.withValues(alpha: 0.55),
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandDot extends StatelessWidget {
  const _BrandDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        gradient: AppTheme.brandGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x59246BCE),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.public, size: 16, color: Colors.white),
    );
  }
}

class MessagesHeader extends StatelessWidget {
  const MessagesHeader({this.onAddTap, super.key});

  final VoidCallback? onAddTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => AppTheme.brandGradient.createShader(
              Rect.fromLTWH(0, 0, bounds.width, bounds.height),
            ),
            child: const Text(
              'Messages',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          _GradientIconButton(
            icon: Icons.add,
            tooltip: 'Start a new chat',
            gradient: AppTheme.brandGradient,
            onTap: onAddTap,
          ),
        ],
      ),
    );
  }
}

class _GradientIconButton extends StatefulWidget {
  const _GradientIconButton({
    required this.icon,
    required this.tooltip,
    required this.gradient,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Gradient gradient;
  final VoidCallback? onTap;

  @override
  State<_GradientIconButton> createState() => _GradientIconButtonState();
}

class _GradientIconButtonState extends State<_GradientIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: widget.onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) {
          if (widget.onTap != null) setState(() => _hovering = true);
        },
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hovering ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 160),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: widget.gradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brand
                        .withValues(alpha: _hovering ? 0.45 : 0.25),
                    blurRadius: _hovering ? 14 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryTabs extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const CategoryTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const _tabs = ['All', 'Friends', 'Groups', 'Communities'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F1F3),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: _tabs.map((tab) {
            final isActive = tab == selected;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelected(tab),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      gradient: isActive ? AppTheme.brandGradient : null,
                      color: isActive ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color:
                                    AppTheme.brand.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      tab,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? Colors.white : const Color(0xFF9A9A9A),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class ChatItem extends StatefulWidget {
  final Chat chat;
  final VoidCallback? onTap;

  const ChatItem({super.key, required this.chat, this.onTap});

  @override
  State<ChatItem> createState() => _ChatItemState();
}

class _ChatItemState extends State<ChatItem> {
  bool _hovering = false;

  String _initials(String name) {
    final parts = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    return parts.isEmpty ? '?' : parts;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) {
        if (widget.onTap != null) setState(() => _hovering = true);
      },
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ListenableBuilder(
          listenable: ChatSessionsState.instance,
          builder: (context, _) {
            final state = ChatSessionsState.instance;
            final preview = state.previewOf(widget.chat);
            final time = state.timeOf(widget.chat);
            final unreadCount = state.unreadCountOf(widget.chat);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              margin: EdgeInsets.symmetric(
                  horizontal: _hovering ? 8 : 12, vertical: 3),
                  decoration: BoxDecoration(
                    color: _hovering ? const Color(0xFFEAF2FE) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _hovering
                          ? AppTheme.brand.withValues(alpha: 0.25)
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: AppTheme.avatarGradientFor(
                              widget.chat.name),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.brand
                                  .withValues(alpha: _hovering ? 0.3 : 0.14),
                              blurRadius: _hovering ? 12 : 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: widget.chat.isGroup
                              ? const Icon(Icons.group,
                                  color: Colors.white, size: 23)
                              : Text(
                                  _initials(widget.chat.name),
                                  style: const TextStyle(
                                    fontSize: 16,
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.chat.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ),
                                Text(
                                  time,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF9A9A9A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF9A9A9A),
                                    ),
                                  ),
                                ),
                                if (unreadCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    constraints:
                                        const BoxConstraints(minWidth: 22),
                                    height: 22,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    decoration: BoxDecoration(
                                      gradient: AppTheme.redGradient,
                                      borderRadius:
                                          BorderRadius.circular(11),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.red.withValues(
                                              alpha: 0.35),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      unreadCount > 9
                                          ? '9+'
                                          : '$unreadCount',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
          },
        ),
      ),
    );
  }
}

class ChatList extends StatelessWidget {
  final List<Chat> chats;
  final void Function(Chat chat)? onChatTap;

  const ChatList({super.key, required this.chats, this.onChatTap});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      itemCount: chats.length,
      itemBuilder: (_, i) => ChatItem(
        chat: chats[i],
        onTap: onChatTap != null ? () => onChatTap!(chats[i]) : null,
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const BottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const _items = [
    ('Chat', Icons.chat_bubble_outline),
    ('Community', Icons.people_outline),
    ('Family', Icons.family_restroom),
    ('Profile', Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE8E8E8), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: _items.asMap().entries.map((entry) {
              final i = entry.key;
              final label = entry.value.$1;
              final icon = entry.value.$2;
              final isActive = i == selectedIndex;
              return Expanded(
                child: _BottomNavItem(
                  icon: icon,
                  label: label,
                  isActive: isActive,
                  onTap: () => onSelected(i),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatefulWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_BottomNavItem> createState() => _BottomNavItemState();
}

class _BottomNavItemState extends State<_BottomNavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final highlight = active || _hovering;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            gradient: active ? AppTheme.brandGradient : null,
            color: !active && _hovering
                ? const Color(0xFFEAF2FE)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: highlight ? (active ? Colors.white : AppTheme.brand) : const Color(0xFF9A9A9A),
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: highlight ? (active ? Colors.white : AppTheme.brand) : const Color(0xFF9A9A9A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
