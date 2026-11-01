import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_widgets.dart';
import 'home_page.dart';

class FriendRequestsPage extends StatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  State<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends State<FriendRequestsPage> {
  final ChatService _chatService = ChatService();
  List<ChatFriendRequest> _requests = [];
  bool _loading = true;
  String? _error;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _chatService.close();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _chatService.fetchFriends();
      if (!mounted) return;
      setState(() {
        _requests = summary.incoming;
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

  Future<void> _accept(ChatFriendRequest request) async {
    final userId = request.user.id;
    if (_processing.contains(userId)) return;
    setState(() => _processing.add(userId));
    try {
      await _chatService.acceptFriendRequest(userId);
      if (!mounted) return;
      setState(() {
        _processing.remove(userId);
        _requests.removeWhere((r) => r.user.id == userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You are now friends with ${request.user.fullName}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing.remove(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _decline(ChatFriendRequest request) async {
    final userId = request.user.id;
    if (_processing.contains(userId)) return;
    setState(() => _processing.add(userId));
    try {
      await _chatService.declineFriendRequest(userId);
      if (!mounted) return;
      setState(() {
        _processing.remove(userId);
        _requests.removeWhere((r) => r.user.id == userId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing.remove(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const _RequestsHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: BottomNav(
        selectedIndex: 0,
        onSelected: (i) => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomePage(initialTabIndex: i)),
          (route) => false,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 14),
          ),
          TextButton(
            onPressed: _loadRequests,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (_requests.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        children: const [
          Icon(Icons.notifications_none, size: 56, color: Color(0xFFB7BBC1)),
          SizedBox(height: 16),
          Text(
            'No friend requests',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF777777),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'When someone sends you a friend request, it will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 13, height: 1.4),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return _RequestCard(
            request: request,
            isProcessing: _processing.contains(request.user.id),
            onAccept: () => _accept(request),
            onDecline: () => _decline(request),
          );
        },
      ),
    );
  }
}

class _RequestsHeader extends StatelessWidget {
  const _RequestsHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              color: AppTheme.ink,
              tooltip: 'Back',
            ),
            const Expanded(
              child: Text(
                'Friend Requests',
                textAlign: TextAlign.center,
                style: TextStyle(
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
}

class _RequestCard extends StatelessWidget {
  final ChatFriendRequest request;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RequestCard({
    required this.request,
    required this.isProcessing,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final user = request.user;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
            ],
          ),
          if (request.message != null && request.message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '"${request.message}"',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF777777),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.ink,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF777777),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Accept',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton(
                    onPressed: isProcessing ? null : onDecline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.ink,
                      side: const BorderSide(color: Color(0xFFB7BBC1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
