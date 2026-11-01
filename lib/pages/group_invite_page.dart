import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';

class GroupInvitePage extends StatefulWidget {
  const GroupInvitePage({
    super.key,
    required this.title,
    this.excludeIds = const {},
    this.fixedNote,
  });

  final String title;
  final Set<String> excludeIds;
  final String? fixedNote;

  @override
  State<GroupInvitePage> createState() => _GroupInvitePageState();
}

class _GroupInvitePageState extends State<GroupInvitePage> {
  final ChatService _chatService = ChatService();
  final Set<String> _selectedIds = {};
  List<ChatUser> _friends = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _chatService.close();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _chatService.fetchFriends();
      if (!mounted) return;
      setState(() {
        _friends = summary.friends
            .where((u) => !widget.excludeIds.contains(u.id))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _toggleUser(ChatUser user) {
    setState(() {
      if (_selectedIds.contains(user.id)) {
        _selectedIds.remove(user.id);
      } else {
        _selectedIds.add(user.id);
      }
    });
  }

  Future<void> _confirm() async {
    if (_selectedIds.isEmpty) return;
    final selected =
        _friends.where((u) => _selectedIds.contains(u.id)).toList();
    Navigator.of(context).pop(selected);
  }

  String _initials(String name) {
    return name
        .split(' ')
        .map((n) => n.isNotEmpty ? n[0] : '')
        .join()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(context),
            if (widget.fixedNote != null) _buildFixedNote(),
          Expanded(child: _buildList()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppTheme.ink),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedNote() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F1F3),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Color(0xFF4CAF50)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.fixedNote!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6F6F6F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _loadFriends,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (_friends.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No more friends to invite. Add friends first from the search page.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 14, height: 1.4),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final user = _friends[index];
        final selected = _selectedIds.contains(user.id);
        return _buildUserTile(user, selected);
      },
    );
  }

  Widget _buildUserTile(ChatUser user, bool selected) {
    return InkWell(
      onTap: () => _toggleUser(user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFF0F1F3),
              child: Text(
                _initials(user.fullName),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9A9A9A),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email ?? user.username ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9A9A9A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 24,
              color: selected
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFB7BBC1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final count = _selectedIds.length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE8E8E8), width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        left: 20,
        right: 20,
        top: 10,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton(
          onPressed: count > 0 ? _confirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.ink,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFE8E8E8),
            disabledForegroundColor: const Color(0xFF9A9A9A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(23),
            ),
          ),
          child: Text(
            count > 0
                ? 'Invite ${count == 1 ? '1 friend' : '$count friends'}'
                : 'Select friends above',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
