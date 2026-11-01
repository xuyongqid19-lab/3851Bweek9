import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class FriendProfilePage extends StatefulWidget {
  const FriendProfilePage({
    super.key,
    required this.userId,
    this.fallbackName = '',
  });

  final String userId;
  final String fallbackName;

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends State<FriendProfilePage> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await AuthService.fetchUserById(widget.userId);
      if (!mounted) return;
      setState(() {
        _user = user;
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

  String get _displayName {
    final name = _user?['fullName']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    return widget.fallbackName.isNotEmpty ? widget.fallbackName : 'Friend';
  }

  String get _initials {
    final parts =
        _displayName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();
  }

  String? get _photoUrl => _user?['googlePhotoUrl']?.toString();

  int? get _age {
    final birthDate = DateTime.tryParse(
      _user?['birthDate']?.toString() ?? '',
    );
    if (birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age >= 0 && age < 130 ? age : null;
  }

  List<String> get _interests {
    final raw = _user?['interests'];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final legacy = _user?['interest']?.toString().trim();
    if (legacy != null && legacy.isNotEmpty) return [legacy];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
                'Profile',
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

  Widget _buildBody() {
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
            onPressed: _loadProfile,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        _buildAvatarSection(),
        const SizedBox(height: 24),
        _buildInfoCard(),
        if (_interests.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildInterestsSection(),
        ],
        const SizedBox(height: 24),
        _buildMessageButton(),
      ],
    );
  }

  Widget _buildAvatarSection() {
    final photoUrl = _photoUrl;
    final age = _age;
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: Color(0xFFF0F1F3),
            shape: BoxShape.circle,
          ),
          child: ClipOval(
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _initialsAvatar(),
                  )
                : _initialsAvatar(),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _displayName,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _user?['username']?.toString().isNotEmpty == true
              ? '@${_user!['username']}'
              : (_user?['email']?.toString() ?? ''),
          style: const TextStyle(fontSize: 14, color: Color(0xFF9A9A9A)),
        ),
        if (age != null) ...[
          const SizedBox(height: 4),
          Text(
            'Age $age',
            style: const TextStyle(fontSize: 13, color: Color(0xFF9A9A9A)),
          ),
        ],
      ],
    );
  }

  Widget _initialsAvatar() {
    return Center(
      child: Text(
        _initials,
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w600,
          color: Color(0xFF9A9A9A),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _infoRow(Icons.alternate_email, 'Email',
              _user?['email']?.toString() ?? ''),
          _infoRow(Icons.phone_outlined, 'Phone',
              _user?['phone']?.toString() ?? ''),
          _infoRow(Icons.location_on_outlined, 'Community',
              _user?['community']?.toString() ?? ''),
          _infoRow(Icons.home_outlined, 'Address',
              _user?['address']?.toString() ?? ''),
          _infoRow(Icons.cake_outlined, 'Birthday',
              _user?['birthDate']?.toString() ?? ''),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    final display =
        value.trim().isEmpty ? 'Not provided' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.muted),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              display,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: value.trim().isEmpty
                    ? const Color(0xFFB7BBC1)
                    : const Color(0xFF6F6F6F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Interests',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _interests
              .map(
                (tag) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F1F3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildMessageButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.chat_bubble_outline, size: 20),
        label: const Text(
          'Back to Chat',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.ink,
          side: const BorderSide(color: AppTheme.ink),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}
