import 'package:flutter/material.dart';

import '../models/profile_model.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import 'add_friend_page.dart';
import 'login_page.dart';
import 'change_password_page.dart';
import 'security_questions_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// 兴趣匹配候选人（后端真实用户）。两个 Tab 共用同一份数据。
  List<MatchUser> _candidates = const [];
  bool _candidatesLoading = true;
  String? _candidatesError;

  /// 好友/已发送请求状态，用于 tile 上的 Add / Pending / Friends 展示。
  final Set<String> _friendIds = <String>{};
  final Set<String> _pendingIds = <String>{};

  ChatService? _chatService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 首次加载不 setState，_candidatesLoading 初始就是 true。
    _fetchCandidates();
    _loadFriendStatus();
  }

  ChatService _service() => _chatService ??= ChatService();

  /// Retry / 手动刷新入口。
  Future<void> _loadCandidates() {
    if (mounted) {
      setState(() {
        _candidatesLoading = true;
        _candidatesError = null;
      });
    }
    return _fetchCandidates();
  }

  Future<void> _fetchCandidates() async {
    try {
      final rows = await AuthService.fetchMatchCandidates();
      if (!mounted) return;
      setState(() {
        // 去掉没有 id 的脏数据，无法据此加好友。
        _candidates =
            rows.map(MatchUser.fromJson).where((u) => u.id.isNotEmpty).toList();
        _candidatesLoading = false;
        _candidatesError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _candidates = const [];
        _candidatesLoading = false;
        _candidatesError = e.toString();
      });
    }
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
    } catch (_) {
      // 聊天服务不可用时不影响匹配列表，只是不展示好友状态。
    }
  }

  Future<void> _onAddFriend(MatchUser user) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddFriendPage(
          user: ChatUser(
            id: user.id,
            fullName: user.name,
            username: user.username,
            email: user.email,
            googlePhotoUrl: user.googlePhotoUrl,
            // ChatUser.interest 是单字段，拼成一句给加好友页展示。
            interest: user.interestTags.join(', '),
            authProvider: user.authProvider,
          ),
        ),
      ),
    );
    if (sent == true && mounted) {
      setState(() => _pendingIds.add(user.id));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatService?.close();
    super.dispose();
  }

  /// 两个匹配 Tab 共用的候选人 + 好友状态快照。
  _MatchTabConfig get _matchConfig => _MatchTabConfig(
        candidates: _candidates,
        loading: _candidatesLoading,
        error: _candidatesError,
        friendIds: _friendIds,
        pendingIds: _pendingIds,
        onRetry: _loadCandidates,
        onAddFriend: _onAddFriend,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.logout, color: AppTheme.ink),
                    tooltip: 'Logout',
                    onPressed: () async {
                      await AuthService.clearSession();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginPage(),
                        ),
                        (route) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.ink,
              unselectedLabelColor: const Color(0xFF9A9A9A),
              indicatorColor: AppTheme.ink,
              indicatorWeight: 2,
              tabs: const [
                Tab(text: 'My Profile'),
                Tab(text: 'Interest Match'),
                Tab(text: 'Recommended'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  const _MyProfileTab(),
                  _InterestMatchTab(config: _matchConfig),
                  _RecommendedMatchTab(config: _matchConfig),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyProfileTab extends StatefulWidget {
  const _MyProfileTab();

  @override
  State<_MyProfileTab> createState() => _MyProfileTabState();
}

class _MyProfileTabState extends State<_MyProfileTab> {
  bool _editing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _usernameCtrl;
  DateTime? _birthDate;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late List<String> _selectedInterests;
  late String _selectedCommunity;
  late TextEditingController _customCtrl;
  String _customCategory = 'Sports';
  late Map<String, String> _customCategories;

  @override
  void initState() {
    super.initState();
    _customCtrl = TextEditingController();
    _customCategory = interestCategories.keys.first;
    _initControllers(currentProfile.value);
    _loadRemoteProfile();
  }

  Future<void> _loadRemoteProfile() async {
    try {
      final user = await AuthService.fetchMe();
      if (!mounted || user == null) {
        return;
      }
      setState(() {
        currentProfile.value =
            profileFromAuthUser(user, fallback: currentProfile.value);
        _initControllers(currentProfile.value);
      });
    } on AuthException {
      // Offline or not logged in: keep local defaults.
    }
  }

  void _initControllers(ProfileData p) {
    _nameCtrl = TextEditingController(text: p.name);
    _usernameCtrl = TextEditingController(text: p.username);
    _birthDate = p.birthDate;
    _emailCtrl = TextEditingController(text: p.email);
    _phoneCtrl = TextEditingController(text: p.phone);
    _addressCtrl = TextEditingController(text: p.address);
    _selectedInterests = List.from(p.interestTags);
    _selectedCommunity = p.community;
    _customCategories = Map<String, String>.from(p.customInterestCategories);
    _customCtrl.clear();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial = _birthDate ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: now,
      helpText: 'Select birth date',
      cancelText: 'Cancel',
      confirmText: 'OK',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select birth date')),
      );
      return;
    }
    final age = calculateAge(_birthDate!);
    // Keep only custom mappings still in the selected list
    final customMap = <String, String>{};
    for (final e in _customCategories.entries) {
      if (_selectedInterests.contains(e.key)) customMap[e.key] = e.value;
    }
    final birthStr = formatBirthDate(_birthDate!);
    currentProfile.value = ProfileData(
      name: _nameCtrl.text,
      username: _usernameCtrl.text,
      age: age,
      birthDate: _birthDate,
      email: _emailCtrl.text,
      phone: _phoneCtrl.text,
      community: _selectedCommunity,
      address: _addressCtrl.text,
      interestTags: List.from(_selectedInterests),
      customInterestCategories: customMap,
    );
    setState(() => _editing = false);
    try {
      final user = await AuthService.updateProfile(
        fullName: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        birthDate: birthStr,
        phone: _phoneCtrl.text.trim(),
        community: _selectedCommunity,
        address: _addressCtrl.text.trim(),
        interests: List.from(_selectedInterests),
        customCategories: customMap,
      );
      if (user.isNotEmpty) {
        currentProfile.value =
            profileFromAuthUser(user, fallback: currentProfile.value);
        _initControllers(currentProfile.value);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved to database')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved locally only: ${e.message}')),
      );
    }
  }

  void _cancel() {
    _initControllers(currentProfile.value);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = currentProfile.value;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: AppTheme.ink,
                child: Text(
                  p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(p.username,
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 14)),
                  ],
                ),
              ),
              if (!_editing)
                TextButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.ink),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChangePasswordPage(),
                ),
              ),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Change Password'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.ink),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SecurityQuestionsPage(),
                ),
              ),
              icon: const Icon(Icons.security_outlined, size: 18),
              label: const Text('Security Questions'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.ink),
            ),
          ),
          if (_editing) ...[
            _buildSectionTitle('Personal Information'),
            const SizedBox(height: 12),
            _buildEditableField('Name', _nameCtrl),
            const SizedBox(height: 12),
            _buildEditableField('Username', _usernameCtrl),
            const SizedBox(height: 12),
            _buildBirthDateField(),
            const SizedBox(height: 12),
            _buildEditableField('Email', _emailCtrl,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _buildEditableField('Phone', _phoneCtrl,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            _buildEditableField('Address', _addressCtrl),
            const SizedBox(height: 18),
            _buildSectionTitle('Community'),
            const SizedBox(height: 8),
            _buildCommunityDropdown(),
            const SizedBox(height: 18),
            _buildSectionTitle('Interest Tags'),
            const SizedBox(height: 8),
            _buildInterestChips(editable: true),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildButton('Cancel', outlined: true, onTap: _cancel),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildButton('Save', onTap: _save),
                ),
              ],
            ),
          ] else ...[
            _buildSectionTitle('Personal Information'),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.person_outline, 'Name', p.name),
            _buildInfoRow(Icons.badge_outlined, 'Username', p.username),
            _buildInfoRow(
              Icons.cake_outlined,
              'Birth Date',
              p.birthDate == null ? 'Not set' : formatBirthDate(p.birthDate!),
            ),
            _buildInfoRow(Icons.numbers_outlined, 'Age', '${p.displayAge}'),
            _buildInfoRow(Icons.email_outlined, 'Email', p.email),
            _buildInfoRow(Icons.phone_outlined, 'Phone', p.phone),
            _buildInfoRow(Icons.home_outlined, 'Address', p.address),
            const SizedBox(height: 16),
            _buildSectionTitle('Community'),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.groups_outlined, 'Community', p.community),
            const SizedBox(height: 16),
            _buildSectionTitle('Interest Tags'),
            const SizedBox(height: 8),
            _buildInterestChips(editable: false),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink));
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.muted),
          const SizedBox(width: 10),
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      color: AppTheme.muted, fontWeight: FontWeight.w500))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController ctrl,
      {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted)),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppTheme.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppTheme.border)),
          ),
        ),
      ],
    );
  }

  Widget _buildBirthDateField() {
    final text = _birthDate == null
        ? 'Select birth date'
        : '${formatBirthDate(_birthDate!)}  ·  Age ${calculateAge(_birthDate!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Birth Date',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted)),
        const SizedBox(height: 4),
        InkWell(
          onTap: _pickBirthDate,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      color: _birthDate == null
                          ? const Color(0xFF9A9A9A)
                          : AppTheme.ink,
                      fontWeight: _birthDate == null
                          ? FontWeight.w400
                          : FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_month_outlined,
                    size: 20, color: AppTheme.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCommunity.isEmpty ? null : _selectedCommunity,
          isExpanded: true,
          hint: const Text('Select community',
              style: TextStyle(color: Color(0xFF9A9A9A))),
          items: availableCommunities
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _selectedCommunity = v);
          },
        ),
      ),
    );
  }

  void _togglePreset(String interest, bool select) {
    setState(() {
      if (select) {
        if (_selectedInterests.length >= 10) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Max 10 interests')),
          );
          return;
        }
        _selectedInterests.add(interest);
      } else {
        _selectedInterests.remove(interest);
      }
    });
  }

  void _addCustomInterest() {
    final text = _customCtrl.text.trim();
    if (text.isEmpty) return;
    if (text.length > 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Custom interest must be within 12 characters')),
      );
      return;
    }
    final lower = text.toLowerCase();
    final exists = _selectedInterests.any((e) => e.toLowerCase() == lower);
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This interest already exists')),
      );
      return;
    }
    final presetHit = availableInterests.any((e) => e.toLowerCase() == lower);
    if (presetHit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Already in presets, please select it above')),
      );
      return;
    }
    if (_selectedInterests.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max 10 interests')),
      );
      return;
    }
    final customCount =
        _selectedInterests.where((e) => !availableInterests.contains(e)).length;
    if (customCount >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max 5 custom interests')),
      );
      return;
    }
    setState(() {
      _selectedInterests.add(text);
      _customCategories[text] = _customCategory;
      _customCtrl.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedInterests.remove(tag);
      _customCategories.remove(tag);
    });
  }

  Widget _buildInterestChips({required bool editable}) {
    if (!editable) {
      // View mode: show selected only (custom tags with category suffix)
      final tags = currentProfile.value.interestTags;
      final customMap = currentProfile.value.customInterestCategories;
      if (tags.isEmpty) {
        return const Text('No interests',
            style: TextStyle(color: AppTheme.muted, fontSize: 14));
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags.map((tag) {
          final isCustom = !availableInterests.contains(tag);
          final suffix = isCustom && (customMap[tag]?.isNotEmpty ?? false)
              ? ' · ${customMap[tag]}'
              : '';
          return Chip(
            label: Text('$tag$suffix', style: const TextStyle(fontSize: 13)),
            backgroundColor: isCustom
                ? AppTheme.ink.withValues(alpha: 0.12)
                : AppTheme.ink.withValues(alpha: 0.06),
            side: BorderSide(color: isCustom ? AppTheme.ink : AppTheme.border),
          );
        }).toList(),
      );
    }
    final customTags = _selectedInterests
        .where((e) => !availableInterests.contains(e))
        .toList();
    final total = _selectedInterests.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selected $total/10 · Custom ${customTags.length}/5',
            style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availableInterests.map((interest) {
            final selected = _selectedInterests.contains(interest);
            return FilterChip(
              label: Text(interest, style: const TextStyle(fontSize: 13)),
              selected: selected,
              onSelected: (val) => _togglePreset(interest, val),
              selectedColor: AppTheme.ink.withValues(alpha: 0.15),
              checkmarkColor: AppTheme.ink,
              side: BorderSide(
                color: selected ? AppTheme.ink : AppTheme.border,
              ),
            );
          }).toList(),
        ),
        if (customTags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: customTags.map((tag) {
              final big = _customCategories[tag] ?? '';
              return InputChip(
                label:
                    Text('$tag · $big', style: const TextStyle(fontSize: 13)),
                onDeleted: () => _removeTag(tag),
                deleteIcon: const Icon(Icons.close, size: 16),
                backgroundColor: AppTheme.ink.withValues(alpha: 0.12),
                side: const BorderSide(color: AppTheme.ink),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        const Text('Add custom interest',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customCtrl,
                maxLength: 12,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. Lure fishing, Board games (1-12 chars)',
                  counterText: '',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.border)),
                ),
                onSubmitted: (_) => _addCustomInterest(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _customCategory,
                  items: interestCategories.keys
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _customCategory = v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _addCustomInterest,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildButton(String label,
      {bool outlined = false, required VoidCallback onTap}) {
    if (outlined) {
      return SizedBox(
        height: 44,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.ink,
            side: const BorderSide(color: AppTheme.ink),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// 匹配 Tab 公共参数：候选人来自后端，不再是写死的假数据。
class _MatchTabConfig {
  const _MatchTabConfig({
    required this.candidates,
    required this.loading,
    required this.error,
    required this.friendIds,
    required this.pendingIds,
    required this.onRetry,
    required this.onAddFriend,
  });

  final List<MatchUser> candidates;
  final bool loading;
  final String? error;
  final Set<String> friendIds;
  final Set<String> pendingIds;
  final VoidCallback onRetry;
  final ValueChanged<MatchUser> onAddFriend;
}

class _InterestMatchTab extends StatelessWidget {
  const _InterestMatchTab({required this.config});

  final _MatchTabConfig config;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileData>(
      valueListenable: currentProfile,
      builder: (context, profile, _) {
        final matches = interestMatch(profile, config.candidates);
        return _MatchList(
          matches: matches,
          emptyMessage: config.candidates.isEmpty
              ? 'No other users to match with yet.'
              : 'Add interest tags to get match suggestions.',
          title: 'Based on your interests and age',
          config: config,
        );
      },
    );
  }
}

class _RecommendedMatchTab extends StatelessWidget {
  const _RecommendedMatchTab({required this.config});

  final _MatchTabConfig config;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileData>(
      valueListenable: currentProfile,
      builder: (context, profile, _) {
        final matches = recommendMatch(profile, config.candidates);
        return _MatchList(
          matches: matches,
          emptyMessage: config.candidates.isEmpty
              ? 'No other users to match with yet.'
              : 'Update your profile to get recommendations.',
          title: 'Based on community, age & interests',
          config: config,
        );
      },
    );
  }
}

class _MatchList extends StatelessWidget {
  final List<MatchUser> matches;
  final String emptyMessage;
  final String title;
  final _MatchTabConfig config;

  const _MatchList({
    required this.matches,
    required this.emptyMessage,
    required this.title,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(title,
              style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (config.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (config.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(config.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 15)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: config.onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.ink,
                  side: const BorderSide(color: AppTheme.ink),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Retry',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted, fontSize: 15)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: matches.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
      itemBuilder: (_, i) {
        final user = matches[i];
        return _MatchTile(
          user: user,
          isFriend: config.friendIds.contains(user.id),
          isPending: config.pendingIds.contains(user.id),
          onAdd: () => config.onAddFriend(user),
        );
      },
    );
  }
}

class _MatchTile extends StatelessWidget {
  final MatchUser user;
  final bool isFriend;
  final bool isPending;
  final VoidCallback onAdd;

  const _MatchTile({
    required this.user,
    required this.isFriend,
    required this.isPending,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = user.matchScore >= 70
        ? Colors.green
        : user.matchScore >= 40
            ? Colors.orange
            : Colors.grey;
    // 已是好友或已发过请求时，整块 tile 不再可点。
    final canAdd = !isFriend && !isPending;
    return InkWell(
      onTap: canAdd ? onAdd : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppTheme.ink.withValues(alpha: 0.1),
              child: Text(
                user.avatarInitial,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 没有生日时 age 为 0，不展示，避免 "0 yrs"。
                      if (user.age > 0) ...[
                        Text('${user.age} yrs',
                            style: const TextStyle(fontSize: 12)),
                        if (user.community.isNotEmpty) const SizedBox(width: 8),
                      ],
                      if (user.community.isNotEmpty) ...[
                        const Icon(Icons.location_on_outlined,
                            size: 12, color: AppTheme.muted),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(user.community,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.muted),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ],
                  ),
                  if (user.interestTags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 24,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: user.interestTags.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 4),
                        itemBuilder: (_, i) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.ink.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(user.interestTags[i],
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${user.matchScore.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: scoreColor,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _buildAction(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 复用 Find Friends 页的三种状态：Friends / Pending / Add。
  Widget _buildAction() {
    if (isFriend) {
      return _statusPill('Friends', const Color(0xFF4CAF50));
    }
    if (isPending) {
      return _statusPill('Pending', AppTheme.muted);
    }
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        onPressed: onAdd,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.ink,
          side: const BorderSide(color: AppTheme.ink),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 30),
        ),
        child: const Text('Add',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
