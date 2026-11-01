import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_group.dart';
import '../services/auth_service.dart';
import '../services/family_service.dart';
import 'family_tree_page.dart';

const _blue = Color(0xFF246BCE);
const _muted = Color(0xFF687386);

class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key, this.service});
  final FamilyService? service;
  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  late final FamilyService api = widget.service ?? FamilyService();
  FamilyInbox? inbox;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    if (widget.service == null) api.close();
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await api.inbox();
      if (mounted) setState(() => inbox = data);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          inbox = null;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> enter(String id, [int section = 0]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            FamilyGroupPage(api: api, groupId: id, initialSection: section)));
    if (mounted) await load();
  }

  Future<void> add(bool join) async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => FamilyEntryPage(api: api, joining: join)));
    if (!mounted) return;
    if (id != null) {
      await load();
      if (mounted) await enter(id);
    }
  }

  Future<void> openTree(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FamilyTreePage(api: api, groupId: id)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final primary = inbox?.primary;
    final others =
        inbox?.groups.where((g) => g.id != inbox?.primaryId).toList() ?? [];
    return SafeArea(
        child: _FamilyWidth(
            child: Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(children: [
            const Expanded(
                child: Text('Family',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
            IconButton(
                tooltip: 'Refresh families',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh)),
            PopupMenuButton<bool>(
                tooltip: 'Create or join family',
                icon: const Icon(Icons.add_circle_outline),
                onSelected: add,
                itemBuilder: (_) => const [
                      PopupMenuItem(value: false, child: Text('Create family')),
                      PopupMenuItem(value: true, child: Text('Join family'))
                    ]),
          ])),
      Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? _Failure(message: error!, retry: load)
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          children: [
                            if (primary == null) ...[
                              const SizedBox(height: 44),
                              const Icon(Icons.family_restroom,
                                  size: 64, color: _blue),
                              const SizedBox(height: 20),
                              const Text('A space for your family',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold)),
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Text(
                                      'Keep up with the people who matter. Create a family or join with an invite code.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: _muted))),
                              FilledButton(
                                  onPressed: () => add(false),
                                  child: const Text('Create family')),
                              OutlinedButton(
                                  onPressed: () => add(true),
                                  child: const Text('Join family')),
                            ] else ...[
                              _Panel(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Row(children: [
                                      _Avatar(primary.name),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            const Text('PRIMARY FAMILY',
                                                style: TextStyle(
                                                    color: _blue,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 1)),
                                            const SizedBox(height: 4),
                                            Text(primary.name,
                                                style: const TextStyle(
                                                    fontSize: 22,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                            Text(
                                                '${primary.members.length} members · ${primary.me['kinship']}',
                                                style: const TextStyle(
                                                    color: _muted)),
                                          ])),
                                      IconButton(
                                          tooltip: 'Family settings',
                                          onPressed: () => enter(primary.id, 4),
                                          icon: const Icon(
                                              Icons.settings_outlined))
                                    ]),
                                    if (primary.description.isNotEmpty)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Text(primary.description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis)),
                                    const SizedBox(height: 16),
                                    _Summary(
                                        icon: Icons.event_outlined,
                                        title: 'Activities',
                                        value: primary.activitySummary(),
                                        onTap: () => enter(primary.id)),
                                    _Summary(
                                        icon: Icons.task_alt,
                                        title: 'Check-ins',
                                        value:
                                            '${primary.checkins.length} completed today · ${primary.records('tasks').length} tasks',
                                        onTap: () => enter(primary.id, 1)),
                                    _Summary(
                                        icon: Icons.people_outline,
                                        title: 'Member status',
                                        value:
                                            '${primary.checkins.map((c) => c['userId']).toSet().length} of ${primary.members.length} members checked in today',
                                        onTap: () => enter(primary.id, 2)),
                                  ])),
                              const SizedBox(height: 14),
                              _Panel(
                                  child: Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                            Icons.account_tree_outlined,
                                            color: _blue),
                                        title: const Text('Family tree'),
                                        subtitle: Text(
                                            'Families in this tree: ${primary.data['treeSummary']?['familyCount'] ?? 1} · ${primary.data['treeSummary']?['pendingCount'] ?? 0} awaiting your review'),
                                        trailing:
                                            const Icon(Icons.chevron_right),
                                        onTap: () => openTree(primary.id),
                                      ))),
                              const SizedBox(height: 26),
                              const Text('Other families',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              if (others.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Text(
                                        'No other families yet. Use + to create or join another.',
                                        style: TextStyle(color: _muted))),
                              for (final g in others)
                                ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    leading: _Avatar(g.name, small: true),
                                    title: Text(g.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    subtitle: Text(
                                        g.latest?['summary']?.toString() ??
                                            'No updates yet',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(_time(g.latest?['createdAt']),
                                              style: const TextStyle(
                                                  fontSize: 11, color: _muted)),
                                          if (g.unread > 0)
                                            Container(
                                                margin: const EdgeInsets.only(
                                                    top: 5),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                    color: _blue,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12)),
                                                child: Text('${g.unread}',
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11)))
                                        ]),
                                    onTap: () => enter(g.id, 3)),
                            ],
                          ]))),
    ])));
  }
}

class FamilyEntryPage extends StatefulWidget {
  const FamilyEntryPage({super.key, required this.api, required this.joining});
  final FamilyService api;
  final bool joining;
  @override
  State<FamilyEntryPage> createState() => _FamilyEntryPageState();
}

class _FamilyEntryPageState extends State<FamilyEntryPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      description = TextEditingController(),
      realName = TextEditingController(),
      kinship = TextEditingController(),
      invite = TextEditingController();
  FamilyJson? preview;
  String? previewCode, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    prefill();
  }

  Future<void> prefill() async {
    final user = await AuthService.getCurrentUser();
    if (mounted && realName.text.isEmpty) {
      realName.text = user?['fullName']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [name, description, realName, kinship, invite]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> find() async {
    if (busy || invite.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      preview = null;
    });
    final code = invite.text.trim();
    try {
      final data = await widget.api
          .request('POST', '/families/preview', {'invite': code});
      if (mounted) {
        setState(() {
          preview = data;
          previewCode = code;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    if (widget.joining &&
        (preview == null || previewCode != invite.text.trim())) {
      setState(() => error = 'Preview the family before joining.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api
          .request('POST', widget.joining ? '/families/join' : '/families', {
        'name': name.text,
        'description': description.text,
        'realName': realName.text,
        'kinship': kinship.text,
        'invite': invite.text
      });
      if (mounted) Navigator.pop(context, result['id'] as String);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white,
      appBar:
          AppBar(title: Text(widget.joining ? 'Join family' : 'Create family')),
      body: Form(
          key: form,
          child: _FormScroll(padding: const EdgeInsets.all(24), children: [
            Text(
                widget.joining
                    ? 'Find your family'
                    : 'Bring your family together',
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
                'Your real name and relationship help everyone recognise you in this family.',
                style: TextStyle(color: _muted)),
            const SizedBox(height: 24),
            if (widget.joining) ...[
              _Field(
                  controller: invite,
                  label: 'Invite code',
                  max: 30,
                  onChanged: (_) => setState(() {
                        preview = null;
                        previewCode = null;
                      })),
              OutlinedButton(
                  onPressed: busy ? null : find,
                  child: const Text('Preview family')),
              if (preview != null)
                _Panel(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(preview!['name'] as String,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(preview!['description'] as String)
                    ])),
            ] else ...[
              _Field(controller: name, label: 'Family name', max: 80),
              _Field(
                  controller: description,
                  label: 'Family description (optional)',
                  max: 500,
                  required: false,
                  lines: 3)
            ],
            const SizedBox(height: 16),
            _Field(controller: realName, label: 'Your real name', max: 80),
            _Field(
                controller: kinship,
                label: 'Your family relationship',
                hint: 'Dad, Grandfather, Uncle…',
                max: 50),
            Wrap(spacing: 6, children: [
              for (final label in [
                'Mom',
                'Dad',
                'Grandparent',
                'Uncle',
                'Aunt',
                'Child'
              ])
                ActionChip(
                    label: Text(label),
                    onPressed: busy
                        ? null
                        : () => setState(() => kinship.text = label))
            ]),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                    'Your relationship can be different in each family. It does not determine your admin permissions.',
                    style: TextStyle(color: _muted, fontSize: 12))),
            if (error != null) _ErrorText(error!),
            FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy
                    ? 'Please wait…'
                    : widget.joining
                        ? 'Join family'
                        : 'Create family')),
          ])));
}

class FamilyGroupPage extends StatefulWidget {
  const FamilyGroupPage(
      {super.key,
      required this.api,
      required this.groupId,
      this.initialSection = 0});
  final FamilyService api;
  final String groupId;
  final int initialSection;
  @override
  State<FamilyGroupPage> createState() => _FamilyGroupPageState();
}

class _FamilyGroupPageState extends State<FamilyGroupPage> {
  FamilyGroup? group;
  String? error;
  bool loading = true, busy = false;
  late int section = widget.initialSection;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.api.group(widget.groupId);
      if (mounted) {
        setState(() => group = data);
        if (section == 3) await markRead(data);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          group = null;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> markRead(FamilyGroup g) async {
    if (g.events.isEmpty) return;
    try {
      await widget.api.request(
          'POST', '/families/${g.id}/read', {'lastId': g.events.first['id']});
    } catch (e) {
      if (mounted) _snack(context, e.toString());
    }
  }

  Future<void> changeTab(int i) async {
    setState(() => section = i);
    if (i == 3 && group != null) await markRead(group!);
  }

  Future<void> action(String method, String path,
      [FamilyJson? data, String? success]) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.api
          .request(method, '/families/${widget.groupId}$path', data ?? {});
      if (mounted) {
        if (success != null) _snack(context, success);
        await load();
      }
    } catch (e) {
      if (mounted) _snack(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(String kind) async {
    final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                FamilyFormPage(api: widget.api, group: group!, kind: kind)));
    if (done == true && mounted) await load();
  }

  Future<bool> confirm(String title, String content) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) =>
              AlertDialog(title: Text(title), content: Text(content), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirm'))
              ])) ??
      false;
  Future<void> leave() async {
    final g = group!;
    if (!await confirm(
        'Leave ${g.name}?',
        g.members.length == 1
            ? 'You are the last member. This will close the family and delete its records. Its family tree connections will also be removed; remaining branches may split. Other families and their records remain.'
            : 'You will lose access to this family. If it is your primary family, another will be selected.')) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.request('POST', '/families/${g.id}/leave', {});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        _snack(context, e.toString());
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = group;
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text(g?.name ?? 'Family'), actions: [
          IconButton(
              tooltip: 'Refresh family',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh))
        ]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? _Failure(message: error!, retry: load)
                : g == null
                    ? const SizedBox.shrink()
                    : _FamilyWidth(
                        child: Column(children: [
                        SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              for (final (i, label) in [
                                'Activities',
                                'Check-ins',
                                'Members',
                                'Updates',
                                'Settings'
                              ].indexed)
                                Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                        label: Text(label),
                                        selected: section == i,
                                        onSelected: (_) => changeTab(i)))
                            ])),
                        if (busy) const LinearProgressIndicator(),
                        Expanded(
                            child: RefreshIndicator(
                                onRefresh: load,
                                child: ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(20),
                                    children: [
                                      if (section == 0) ...activities(g),
                                      if (section == 1) ...tasks(g),
                                      if (section == 2) ...members(g),
                                      if (section == 3) ...updates(g),
                                      if (section == 4) ...settings(g)
                                    ]))),
                      ])));
  }

  List<Widget> activities(FamilyGroup g) {
    final all = g.records('activities');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final upcoming = all
        .where((r) => r['body']['date'].toString().compareTo(today) >= 0)
        .toList()
      ..sort((a, b) =>
          a['body']['date'].toString().compareTo(b['body']['date'].toString()));
    final past = all
        .where((r) => r['body']['date'].toString().compareTo(today) < 0)
        .toList();
    return [
      const _Heading('Family activities',
          subtitle: 'Make time for each other.'),
      FilledButton.icon(
          onPressed: busy ? null : () => edit('activities'),
          icon: const Icon(Icons.add),
          label: const Text('Create activity')),
      const SizedBox(height: 20),
      if (all.isEmpty)
        const _Empty('No activities yet. Plan something together.'),
      if (upcoming.isNotEmpty) const _Heading('Upcoming'),
      for (final r in upcoming) activityTile(g, r),
      if (past.isNotEmpty) const _Heading('History'),
      for (final r in past) activityTile(g, r)
    ];
  }

  Widget activityTile(FamilyGroup g, FamilyJson record) {
    final b = Map<String, dynamic>.from(record['body'] as Map);
    return _Panel(
        child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined, color: _blue),
            title: Text(b['title'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${b['date']} · ${b['location']}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => FamilyActivityView(group: g, body: b)))));
  }

  List<Widget> tasks(FamilyGroup g) => [
        const _Heading('Family check-ins',
            subtitle: 'Daily records use UTC dates. Check in for yourself.'),
        if (g.canManage)
          FilledButton.icon(
              onPressed: busy ? null : () => edit('tasks'),
              icon: const Icon(Icons.add),
              label: const Text('Create check-in task')),
        if (g.records('tasks').isEmpty) const _Empty('No check-in tasks yet.'),
        for (final r in g.records('tasks'))
          _Panel(child: Builder(builder: (_) {
            final b = r['body'] as Map;
            final assigned = (b['participantIds'] as List).contains(g.userId);
            final done = g.checked(r['id'] as String, g.userId);
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b['title'] as String,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('${_taskType(b['type'])} · ${b['repeat']}'),
                  Text(
                      (b['participantIds'] as List)
                          .map((id) => g.person(id as String))
                          .join(', '),
                      style: const TextStyle(color: _muted)),
                  if (b['type'] != 'manualDaily')
                    const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                            'Configuration saved. Automatic tracking is not enabled yet.',
                            style: TextStyle(color: _muted))),
                  if (b['type'] == 'manualDaily' && assigned)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.tonal(
                            onPressed: busy || done
                                ? null
                                : () => action('POST', '/checkins/${r['id']}'),
                            child: Text(
                                done ? 'Checked in today' : 'Check in now')))
                ]);
          })),
      ];
  List<Widget> members(FamilyGroup g) => [
        _Heading('Members',
            subtitle:
                '${g.members.length} people · ${g.members.where((m) => m['role'] != 'member').length} admins'),
        for (final m in g.members)
          _Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _Avatar(m['realName'] as String, small: true),
                    title: Text(
                        '${m['realName']}${m['userId'] == g.userId ? ' (you)' : ''}'),
                    subtitle: Text('${m['kinship']} · ${m['role']}')),
                Text(
                    g.checkins.any((c) => c['userId'] == m['userId'])
                        ? 'Checked in today'
                        : 'No check-in recorded today',
                    style: TextStyle(
                        color: g.checkins.any((c) => c['userId'] == m['userId'])
                            ? Colors.green.shade800
                            : _muted))
              ])),
        const SizedBox(height: 16),
        const _Heading('Health notes',
            subtitle: 'Shared with members of this family.'),
        if (g.canManage)
          OutlinedButton.icon(
              onPressed: busy ? null : () => edit('notes'),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Add health note')),
        if (g.records('notes').isEmpty) const _Empty('No health notes yet.'),
        for (final r in g.records('notes'))
          _Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(r['body']['title'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(r['body']['note'] as String),
                if (r['body']['photoTitle'] != '')
                  Text('Photo note: ${r['body']['photoTitle']}'),
                Text(_time(r['createdAt']),
                    style: const TextStyle(color: _muted, fontSize: 12))
              ])),
      ];
  List<Widget> updates(FamilyGroup g) => [
        const _Heading('Family updates',
            subtitle: 'Activities, check-ins and family changes in one place.'),
        if (g.events.isEmpty) const _Empty('No updates yet.'),
        for (final e in g.events)
          ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              leading: const Icon(Icons.notifications_none, color: _blue),
              title: Text(e['summary'] as String),
              subtitle: Text(_time(e['createdAt'])))
      ];
  List<Widget> settings(FamilyGroup g) => [
        const _Heading('Family settings'),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_tree_outlined),
            title: const Text('Family tree'),
            subtitle: const Text(
                'View connected families and manage connection requests'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy
                ? null
                : () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) =>
                            FamilyTreePage(api: widget.api, groupId: g.id)));
                    if (mounted) await load();
                  }),
        _Panel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.name,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(g.description),
          const SizedBox(height: 14),
          const Text('Primary family is your personal home-page preference.'),
          FilledButton.tonal(
              onPressed: busy
                  ? null
                  : () => action('POST', '/primary', {},
                      'This is now your primary family.'),
              child: const Text('Set as my primary family'))
        ])),
        ListTile(
            title: const Text('My name and relationship'),
            subtitle: Text('${g.me['realName']} · ${g.me['kinship']}'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: busy ? null : () => edit('identity')),
        if (g.canManage) ...[
          ListTile(
              title: const Text('Edit family information'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: busy ? null : () => edit('settings')),
          _Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Invite code',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('Share only with people you want to join.',
                    style: TextStyle(color: _muted)),
                const SizedBox(height: 8),
                SelectableText(g.invite ?? '',
                    style: const TextStyle(fontSize: 19, letterSpacing: 1)),
                Wrap(spacing: 8, children: [
                  TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: g.invite ?? ''));
                        if (mounted) _snack(context, 'Invite code copied.');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy')),
                  TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (await confirm('Replace invite code?',
                                  'The old code will stop working.')) {
                                await action('POST', '/invite');
                              }
                            },
                      child: const Text('Replace code'))
                ])
              ])),
        ],
        if (g.role == 'owner') ...[
          const _Heading('Manage permissions'),
          for (final m in g.members.where((m) => m['userId'] != g.userId))
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m['realName']} · ${m['kinship']}'),
                subtitle: Text(m['role'] as String),
                trailing: PopupMenuButton<String>(
                    enabled: !busy,
                    tooltip: 'Change permissions',
                    onSelected: (value) async {
                      if (await confirm(
                          'Change permissions?',
                          value == 'owner'
                              ? 'Transfer ownership to ${m['realName']}? You will become an admin.'
                              : 'Set ${m['realName']} as $value?')) {
                        await action(
                            'PUT', '/members/${m['userId']}', {'role': value});
                      }
                    },
                    itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'admin', child: Text('Make admin')),
                          PopupMenuItem(
                              value: 'member', child: Text('Make member')),
                          PopupMenuItem(
                              value: 'owner', child: Text('Transfer ownership'))
                        ])),
        ],
        const SizedBox(height: 20),
        OutlinedButton(
            onPressed: busy ? null : leave,
            child: const Text('Leave family',
                style: TextStyle(color: Colors.red))),
      ];
}

class FamilyActivityView extends StatelessWidget {
  const FamilyActivityView(
      {super.key, required this.group, required this.body});
  final FamilyGroup group;
  final FamilyJson body;
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Family activity')),
      body: _FormScroll(padding: const EdgeInsets.all(24), children: [
        _Heading(body['title'] as String),
        for (final key in [
          'date',
          'duration',
          'location',
          'goal',
          'description',
          'requirements',
          'tags'
        ])
          if (body[key]?.toString().isNotEmpty == true)
            Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(key[0].toUpperCase() + key.substring(1),
                          style: const TextStyle(
                              color: _muted, fontWeight: FontWeight.bold)),
                      Text(body[key].toString(),
                          style: const TextStyle(fontSize: 17))
                    ])),
        const Text('Participants',
            style: TextStyle(color: _muted, fontWeight: FontWeight.bold)),
        for (final id in body['participantIds'] as List)
          Text(group.person(id as String))
      ]));
}

class FamilyFormPage extends StatefulWidget {
  const FamilyFormPage(
      {super.key, required this.api, required this.group, required this.kind});
  final FamilyService api;
  final FamilyGroup group;
  final String kind;
  @override
  State<FamilyFormPage> createState() => _FamilyFormPageState();
}

class _FamilyFormPageState extends State<FamilyFormPage> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final participants = <String>{};
  String type = 'manualDaily';
  String? error;
  bool busy = false;
  TextEditingController field(String name) =>
      fields.putIfAbsent(name, () => TextEditingController());
  @override
  void initState() {
    super.initState();
    participants.add(widget.group.userId);
    field('repeat').text = 'Every day';
    if (widget.kind == 'identity') {
      field('realName').text = widget.group.me['realName'] as String;
      field('kinship').text = widget.group.me['kinship'] as String;
    }
    if (widget.kind == 'settings') {
      field('name').text = widget.group.name;
      field('description').text = widget.group.description;
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (['activities', 'tasks'].contains(widget.kind) && participants.isEmpty) {
      setState(() => error = 'Select at least one family member.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final body = <String, dynamic>{
      for (final e in fields.entries) e.key: e.value.text,
      'participantIds': participants.toList(),
      'type': type
    };
    final kind = widget.kind;
    try {
      await widget.api.request(
          kind == 'settings'
              ? 'PATCH'
              : kind == 'identity'
                  ? 'PUT'
                  : 'POST',
          '/families/${widget.group.id}${kind == 'settings' ? '' : '/$kind'}',
          body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget input(String key, String label,
          {int max = 120, int lines = 1, bool required = true}) =>
      _Field(
          controller: field(key),
          label: label,
          max: max,
          lines: lines,
          required: required);
  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final title = {
      'activities': 'Create activity',
      'tasks': 'Create check-in task',
      'notes': 'Add health note',
      'identity': 'My family identity',
      'settings': 'Edit family information'
    }[kind]!;
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text(title)),
        body: Form(
            key: form,
            child: _FormScroll(padding: const EdgeInsets.all(24), children: [
              if (kind == 'identity') ...[
                input('realName', 'Your real name', max: 80),
                input('kinship', 'Your family relationship', max: 50)
              ] else if (kind == 'settings') ...[
                input('name', 'Family name', max: 80),
                input('description', 'Family description (optional)',
                    max: 500, lines: 3, required: false)
              ] else ...[
                input('title', 'Title', max: 100),
                if (kind == 'notes') ...[
                  input('note', 'Health note', max: 2000, lines: 5),
                  input('photoTitle', 'Photo description (optional)',
                      max: 200, required: false),
                  const Text(
                      'Text description only; photo upload is not available.',
                      style: TextStyle(color: _muted))
                ],
                if (kind == 'activities') ...[
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                          controller: field('date'),
                          readOnly: true,
                          decoration: const InputDecoration(
                              labelText: 'Date',
                              suffixIcon: Icon(Icons.calendar_today)),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Select a date' : null,
                          onTap: () async {
                            final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100));
                            if (date != null && mounted) {
                              setState(() => field('date').text =
                                  date.toIso8601String().substring(0, 10));
                            }
                          })),
                  input('duration', 'Duration', max: 80),
                  input('location', 'Location', max: 160),
                  input('goal', 'Goal (optional)', max: 300, required: false),
                  input('description', 'Description (optional)',
                      max: 2000, lines: 3, required: false),
                  input('requirements', 'Requirements (optional)',
                      max: 1000, lines: 2, required: false),
                  input('tags', 'Tags (optional)', max: 200, required: false),
                ],
                if (kind == 'tasks') ...[
                  DropdownButtonFormField<String>(
                      initialValue: type,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Check-in type'),
                      items: [
                        for (final t in [
                          'manualDaily',
                          'autoLogin',
                          'exerciseTarget'
                        ])
                          DropdownMenuItem(value: t, child: Text(_taskType(t)))
                      ],
                      onChanged: (v) => setState(() => type = v!)),
                  const SizedBox(height: 16),
                  input('repeat', 'Repeat rule', max: 100),
                  if (type != 'manualDaily')
                    const Text(
                        'This saves the task definition. Automatic tracking is not yet enabled.',
                        style: TextStyle(color: _muted))
                ],
                if (kind == 'activities' || kind == 'tasks') ...[
                  const _Heading('Participants'),
                  for (final m in widget.group.members)
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(m['realName'] as String),
                        subtitle: Text(m['kinship'] as String),
                        value: participants.contains(m['userId']),
                        onChanged: (yes) => setState(() {
                              if (yes == true) {
                                participants.add(m['userId'] as String);
                              } else {
                                participants.remove(m['userId']);
                              }
                            }))
                ],
              ],
              if (error != null) _ErrorText(error!),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Saving…' : 'Save')),
            ])));
  }
}

// Keep every form field mounted so validation also covers fields off screen.
class _FamilyWidth extends StatelessWidget {
  const _FamilyWidth({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720), child: child));
}

class _FormScroll extends StatelessWidget {
  const _FormScroll({required this.padding, required this.children});
  final EdgeInsets padding;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => _FamilyWidth(
          child: SingleChildScrollView(
        padding: padding,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ));
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.controller,
      required this.label,
      this.hint,
      this.max = 120,
      this.lines = 1,
      this.required = true,
      this.onChanged});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int max, lines;
  final bool required;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
          controller: controller,
          maxLines: lines,
          maxLength: max,
          onChanged: onChanged,
          decoration: InputDecoration(
              labelText: label, hintText: hint, counterText: ''),
          validator: (v) => required && (v == null || v.trim().isEmpty)
              ? '$label is required'
              : null));
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          border: Border.all(color: const Color(0xFFE3E8EF)),
          borderRadius: BorderRadius.circular(18)),
      child: child);
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {this.small = false});
  final String name;
  final bool small;
  @override
  Widget build(BuildContext context) => CircleAvatar(
      radius: small ? 22 : 27,
      backgroundColor: const Color(0xFFE3EDFC),
      foregroundColor: _blue,
      child: Text(name.characters.firstOrNull ?? 'F',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)));
}

class _Summary extends StatelessWidget {
  const _Summary(
      {required this.icon,
      required this.title,
      required this.value,
      required this.onTap});
  final IconData icon;
  final String title, value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: Icon(icon, color: _blue),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle:
                  Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right, size: 19),
              onTap: onTap)));
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (subtitle != null)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(subtitle!, style: const TextStyle(color: _muted)))
      ]));
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Text(message,
          textAlign: TextAlign.center, style: const TextStyle(color: _muted)));
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message,
          style: TextStyle(color: Theme.of(context).colorScheme.error)));
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: _muted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: retry, child: const Text('Retry'))
          ])));
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
String _taskType(dynamic value) => switch (value) {
      'autoLogin' => 'Auto on login',
      'exerciseTarget' => 'Exercise target',
      _ => 'Manual daily'
    };
String _time(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
