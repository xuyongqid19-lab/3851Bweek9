import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_widgets.dart';
import 'add_friend_page.dart';
import 'home_page.dart';

class FindFriendsPage extends StatefulWidget {
  const FindFriendsPage({this.initialQuery, super.key});

  final String? initialQuery;

  @override
  State<FindFriendsPage> createState() => _FindFriendsPageState();
}

class _FindFriendsPageState extends State<FindFriendsPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  final List<_RecentSearch> _recentSearches = [];
  final Set<String> _friendIds = {};
  final Set<String> _pendingIds = {};
  int _nextRecentId = 1;

  List<ChatUser> _results = [];
  bool _searching = false;
  String? _searchError;

  ChatService? _chatService;

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery;
    if (initialQuery != null && initialQuery.trim().isNotEmpty) {
      _searchController.text = initialQuery.trim();
      _recentSearches.insert(
        0,
        _RecentSearch(id: _nextRecentId++, name: initialQuery.trim()),
      );
    } else {
      _focusNode.requestFocus();
    }
    _searchController.addListener(_onQueryChanged);
    _loadFriendStatus();
    final pendingQuery = _searchController.text.trim();
    if (pendingQuery.length >= 2) {
      _search(pendingQuery);
    }
  }

  ChatService _service() => _chatService ??= ChatService();

  @override
  void dispose() {
    _debounce?.cancel();
    _chatService?.close();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFriendStatus() async {
    try {
      final summary = await _service().fetchFriends();
      if (!mounted) return;
      setState(() {
        _friendIds
          ..clear()
          ..addAll(summary.friends.map((u) => u.id));
        _pendingIds
          ..clear()
          ..addAll(summary.outgoing.map((u) => u.id));
      });
    } catch (_) {}
  }

  void _onQueryChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      final exists = _recentSearches.any(
          (s) => s.name.toLowerCase() == query.toLowerCase());
      if (!exists) {
        _recentSearches.insert(
          0,
          _RecentSearch(id: _nextRecentId++, name: query),
        );
      }
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
    setState(() {});
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      if (mounted) setState(() => _results = []);
      return;
    }
    if (!mounted) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final users = await AuthService.searchUsers(query);
      if (!mounted) return;
      setState(() {
        _results = users
            .map((u) => ChatUser(
                  id: u['id']?.toString() ?? '',
                  fullName: u['fullName']?.toString() ?? '',
                  username: u['username']?.toString(),
                  email: u['email']?.toString(),
                  googlePhotoUrl: u['googlePhotoUrl']?.toString(),
                  interest: u['interest']?.toString(),
                  authProvider: u['authProvider']?.toString(),
                ))
            .where((u) => u.id.isNotEmpty)
            .toList();
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = e.toString();
      });
    }
  }

  void _removeRecent(int id) {
    setState(() => _recentSearches.removeWhere((s) => s.id == id));
  }

  void _clearAllRecent() {
    setState(() => _recentSearches.clear());
  }

  Future<void> _onAddUser(ChatUser user) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddFriendPage(user: user),
      ),
    );
    if (sent == true && mounted) {
      setState(() => _pendingIds.add(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const _FindFriendsHeader(),
          _FindSearchBar(controller: _searchController, focusNode: _focusNode),
          if (_recentSearches.isNotEmpty)
            _RecentSearchesSection(
              searches: _recentSearches,
              onRemove: _removeRecent,
              onClearAll: _clearAllRecent,
            ),
          Expanded(
            child: _buildResults(query),
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

  Widget _buildResults(String query) {
    if (query.length < 2) {
      return ListView(
        padding: EdgeInsets.zero,
        children: const [_InviteCard()],
      );
    }
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          Text(
            _searchError!,
            style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
          ),
          TextButton(onPressed: () => _search(query), child: const Text('Retry')),
          const _InviteCard(),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (_results.isNotEmpty) ...[
          const _SearchResultsHeader(),
          ..._results.map(
            (u) => _UserResultCard(
              user: u,
              isFriend: _friendIds.contains(u.id),
              isPending: _pendingIds.contains(u.id),
              onAdd: () => _onAddUser(u),
            ),
          ),
        ],
        if (_results.isEmpty && query.length >= 2)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Text(
              'No users found. Try searching by the Google email they used to sign in.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
            ),
          ),
        const _InviteCard(),
      ],
    );
  }
}

class _RecentSearch {
  final int id;
  final String name;
  _RecentSearch({required this.id, required this.name});
}

class _FindFriendsHeader extends StatelessWidget {
  const _FindFriendsHeader();

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
                'Find Friends',
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

class _FindSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _FindSearchBar({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F1F3),
          borderRadius: BorderRadius.circular(25),
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            hintText: 'Search by name, username or Google email',
            hintStyle: TextStyle(color: Color(0xFF9A9A9A), fontSize: 14),
            prefixIcon:
                Icon(Icons.search, color: Color(0xFF9A9A9A), size: 22),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _RecentSearchesSection extends StatelessWidget {
  final List<_RecentSearch> searches;
  final void Function(int id) onRemove;
  final VoidCallback onClearAll;

  const _RecentSearchesSection({
    required this.searches,
    required this.onRemove,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Recent Searches',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClearAll,
                child: const Text(
                  'Clear All',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9A9A9A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: searches.map((s) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1F3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 16, color: AppTheme.muted),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        s.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => onRemove(s.id),
                      child: const Icon(Icons.close, size: 14, color: AppTheme.muted),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SearchResultsHeader extends StatelessWidget {
  const _SearchResultsHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        'Search Results',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppTheme.ink,
        ),
      ),
    );
  }
}

class _UserResultCard extends StatelessWidget {
  final ChatUser user;
  final bool isFriend;
  final bool isPending;
  final VoidCallback onAdd;

  const _UserResultCard({
    required this.user,
    required this.isFriend,
    required this.isPending,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final initials = user.fullName
        .split(' ')
        .map((n) => n.isNotEmpty ? n[0] : '')
        .join()
        .toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
              initials,
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
          SizedBox(
            height: 34,
            child: isFriend
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF4CAF50)),
                    ),
                    child: const Text(
                      'Friends',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  )
                : isPending
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF9A9A9A)),
                        ),
                        child: const Text(
                          'Pending',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9A9A9A),
                          ),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: onAdd,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.ink,
                          side: const BorderSide(color: AppTheme.ink),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          minimumSize: const Size(0, 34),
                        ),
                        child: const Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F1F3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_alt, size: 20, color: Colors.red),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Can't find who you're looking for?",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Invite your friends to join Global Village!',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppTheme.muted),
          ],
        ),
      ),
    );
  }
}
