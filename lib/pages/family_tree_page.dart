import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/family_group.dart';
import '../models/family_tree.dart';
import '../services/family_service.dart';
import 'family_page.dart';
import 'family_tree_canvas_page.dart';

class FamilyTreePage extends StatefulWidget {
  const FamilyTreePage({super.key, required this.api, required this.groupId});
  final FamilyService api;
  final String groupId;
  @override
  State<FamilyTreePage> createState() => _FamilyTreePageState();
}

class _FamilyTreePageState extends State<FamilyTreePage> {
  late String selected = widget.groupId;
  FamilyTreeSnapshot? tree;
  List<FamilyGroup> groups = [];
  int section = 0, generation = 0;
  bool loading = true, busy = false, uncertainSend = false, consent = false;
  String? loadError, actionError, notice;
  FamilyJson? preview;
  final code = TextEditingController();
  final custom = TextEditingController();
  final explanation = TextEditingController();
  String relationship = 'Related households';
  final form = GlobalKey<FormState>();
  String get base => '/families/$selected/tree';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    code.dispose();
    custom.dispose();
    explanation.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final requestGeneration = ++generation;
    final id = selected;
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final inbox = await widget.api.inbox();
      if (!inbox.groups.any((g) => g.id == id)) {
        throw const FamilyApiException(
            'You no longer belong to this family. Go back to Family to choose another group.');
      }
      final data = await widget.api.request('GET', '/families/$id/tree');
      if (!mounted || requestGeneration != generation) return;
      setState(() {
        tree = FamilyTreeSnapshot(data);
        groups = inbox.groups;
        uncertainSend = false;
      });
    } catch (e) {
      if (mounted && requestGeneration == generation) {
        setState(() {
          tree = null;
          loadError = e.toString();
        });
      }
    } finally {
      if (mounted && requestGeneration == generation) {
        setState(() => loading = false);
      }
    }
  }

  void switchGroup(String? id) {
    if (id == null || id == selected || busy) return;
    setState(() {
      selected = id;
      tree = null;
      preview = null;
      consent = false;
      actionError = null;
      notice = null;
      uncertainSend = false;
      code.clear();
      custom.clear();
      explanation.clear();
      relationship = 'Related households';
    });
    load();
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                constraints: const BoxConstraints(maxWidth: 600),
                scrollable: true,
                title: Text(title),
                content: Text(text),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Confirm')),
                ],
              )) ??
      false;

  Future<void> action(String path, FamilyJson body, String success,
      {bool sending = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      actionError = null;
      notice = null;
    });
    try {
      final result = await widget.api.request('POST', '$base$path', body);
      if (!mounted) return;
      setState(() {
        notice = result['status'] == 'pending' && !sending
            ? 'Your family approved. Waiting for the remaining families.'
            : success;
        if (sending) {
          preview = null;
          consent = false;
          section = 1;
          code.clear();
          explanation.clear();
        }
      });
      await load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        actionError = e.toString();
        if (sending) {
          uncertainSend = true;
          section = 1;
        }
      });
      if (e is FamilyApiException && [401, 403, 404].contains(e.status)) {
        await load();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> findDestination() async {
    if (code.text.trim().isEmpty) {
      setState(() => actionError = 'Enter a tree connection code.');
      return;
    }
    setState(() {
      busy = true;
      actionError = null;
      notice = null;
      preview = null;
      consent = false;
    });
    try {
      final result = await widget.api
          .request('POST', '$base/preview', {'code': code.text.trim()});
      if (mounted) setState(() => preview = result);
    } catch (e) {
      if (mounted) setState(() => actionError = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (preview == null || !consent || !form.currentState!.validate()) return;
    await action(
        '/requests',
        {
          'code': code.text.trim(),
          'snapshot': preview!['snapshot'],
          'label': relationship == 'Custom' ? custom.text.trim() : relationship,
          'message': explanation.text.trim(),
          'confirmed': true,
        },
        'Request sent. The connection appears after every family approves.',
        sending: true);
  }

  Future<void> decide(FamilyJson r, String decision) async {
    final description = decision == 'approve'
        ? 'Approve ${r['sourceName']} and ${r['targetName']} as "${r['label']}"? After all ${r['requiredCount']} families approve, their members can see the combined group names and connections. Private records stay separate.'
        : '${decision == 'reject' ? 'Reject' : 'Cancel'} this proposal for all participating families? No connection will be created.';
    if (await confirm(
            '${decision[0].toUpperCase()}${decision.substring(1)} connection?',
            description) &&
        mounted) {
      await action(
          '/requests/${r['id']}',
          {'decision': decision},
          decision == 'approve'
              ? 'Connection accepted. The tree is updated.'
              : 'Request ${decision == 'reject' ? 'rejected' : 'cancelled'}.');
    }
  }

  Widget heading(String title, [String? subtitle]) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        if (subtitle != null)
          Padding(
              padding: const EdgeInsets.only(top: 6), child: Text(subtitle)),
      ]));
  Widget panel(Widget child) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(16), child: child));
  List<Widget> treeView(FamilyTreeSnapshot t) => [
        heading(
            '${t.nodes.length} ${t.nodes.length == 1 ? 'family' : 'families'} connected',
            'Group-based family tree. Lines show agreed connections, not ancestry or generations. Private family records stay separate.'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => FamilyTreeCanvasPage(
                                api: widget.api, initial: t)));
                    if (mounted) await load();
                  },
            icon: const Icon(Icons.open_in_full),
            label: const Text('Open large tree'),
          ),
        ),
        if (t.connections.isEmpty)
          panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('No connected families yet'),
            Text(t.canManage
                ? 'Use Manage to connect your family to another group.'
                : 'Ask a family administrator to arrange a connection.'),
            if (t.canManage)
              TextButton(
                  onPressed: () => setState(() => section = 2),
                  child: const Text('Connect a family')),
          ])),
        for (final n in t.outline)
          Padding(
            padding: EdgeInsets.only(
                left: ((n['depth'] as int).clamp(0, 3) * 12).toDouble()),
            child: Container(
              decoration: n['depth'] == 0
                  ? null
                  : const BoxDecoration(
                      border: Border(
                          left:
                              BorderSide(color: Color(0xFF83A8DC), width: 2))),
              padding: EdgeInsets.only(left: n['depth'] == 0 ? 0 : 8),
              child: panel(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.account_tree_outlined,
                          color: Color(0xFF246BCE)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(n['name'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 18)))
                    ]),
                    const SizedBox(height: 6),
                    Text(n['id'] == selected
                        ? 'Selected family · Your viewing point'
                        : '${n['label']} · Connected to ${t.name(n['parent'])}'),
                    Text(n['depth'] == 0
                        ? 'Distance: 0 connections'
                        : 'Distance: ${n['depth']} connections'),
                    if (n['canOpen'] == true)
                      TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => FamilyGroupPage(
                                              api: widget.api,
                                              groupId: n['id'])));
                                  if (mounted) await load();
                                },
                          child: const Text('Open family'))
                    else
                      const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                              'Connected group only. Ask its administrator for a membership invite to join.')),
                  ])),
            ),
          ),
      ];
  List<Widget> requestsView(FamilyTreeSnapshot t) => [
        heading('Connection requests',
            'Every affected family must approve before a new connection becomes visible. Requests expire after seven days.'),
        if (!t.canManage)
          const Text(
              'Only family administrators can view and decide connection requests.')
        else ...[
          if (t.requests.isEmpty) const Text('No requests yet.'),
          for (final r in t.requests)
            panel(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['sourceName']} and ${r['targetName']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17)),
              Text(r['label']),
              const SizedBox(height: 8),
              Text('Status: ${r['status']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                  '${r['approvedCount']} of ${r['requiredCount']} families approved'),
              if (r['myApproval'] == true)
                const Text('Your family has approved.'),
              if ((r['message'] as String? ?? '').isNotEmpty)
                Text('Explanation: ${r['message']}'),
              Text(
                  'Expires: ${DateTime.parse(r['expiresAt']).toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC'),
              if ((r['reason'] as String? ?? '').isNotEmpty) Text(r['reason']),
              if (r['status'] == 'pending')
                Wrap(spacing: 8, children: [
                  if (r['myApproval'] != true)
                    FilledButton(
                        onPressed: busy ? null : () => decide(r, 'approve'),
                        child: const Text('Approve')),
                  OutlinedButton(
                      onPressed: busy ? null : () => decide(r, 'reject'),
                      child: const Text('Reject')),
                  if (r['canCancel'] == true)
                    TextButton(
                        onPressed: busy ? null : () => decide(r, 'cancel'),
                        child: const Text('Cancel request')),
                ]),
            ])),
          const Text(
              'Pending requests and up to 100 recent resolved requests are shown. Refresh to check for changes.'),
        ],
      ];
  List<Widget> manageView(FamilyTreeSnapshot t) => [
        heading('Manage connections'),
        if (!t.canManage)
          const Text(
              'You can view this tree. Ask a family administrator to manage connections.')
        else ...[
          panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your tree connection code',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                'Share with another family administrator. This is not a membership invite.'),
            const SizedBox(height: 8),
            SelectableText(t.code),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy tree code'),
                  onPressed: busy
                      ? null
                      : () async {
                          try {
                            await Clipboard.setData(
                                ClipboardData(text: t.code));
                            if (mounted) {
                              setState(() =>
                                  notice = 'Tree connection code copied.');
                            }
                          } catch (_) {
                            if (mounted) {
                              setState(() => actionError =
                                  'Copy failed. Select the code and copy it manually.');
                            }
                          }
                        }),
              TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await confirm('Reset tree code?',
                                  'The old code and requests sent to it will become invalid. Confirmed connections and membership invites stay unchanged.') &&
                              mounted) {
                            await action(
                                '/code', {}, 'Tree connection code reset.');
                          }
                        },
                  child: const Text('Reset tree code')),
            ]),
          ])),
          heading('Connect another family'),
          Form(
              key: form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                        controller: code,
                        enabled: !busy,
                        maxLength: 48,
                        decoration: const InputDecoration(
                            labelText: 'Destination tree connection code',
                            border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {
                              preview = null;
                              consent = false;
                            })),
                    OutlinedButton(
                        onPressed: busy ? null : findDestination,
                        child: const Text('Preview family')),
                    if (preview != null) ...[
                      const SizedBox(height: 12),
                      panel(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Connect ${t.name(selected)} to ${preview!['name']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(
                                '${preview!['requiredApprovals']} families must approve. Only group names and confirmed relationships will be shared.'),
                          ])),
                      DropdownButtonFormField<String>(
                          initialValue: relationship,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Relationship label',
                              border: OutlineInputBorder()),
                          items: [
                            'Related households',
                            'Maternal branch',
                            'Paternal branch',
                            'Extended family',
                            'Custom'
                          ]
                              .map((v) =>
                                  DropdownMenuItem(value: v, child: Text(v)))
                              .toList(),
                          onChanged: busy
                              ? null
                              : (v) => setState(() => relationship = v!)),
                      if (relationship == 'Custom')
                        TextFormField(
                            controller: custom,
                            enabled: !busy,
                            maxLength: 80,
                            decoration: const InputDecoration(
                                labelText: 'Custom relationship label'),
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? 'Enter a relationship label.'
                                : null),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: explanation,
                          enabled: !busy,
                          maxLength: 500,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'Explanation (optional)',
                              border: OutlineInputBorder())),
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: consent,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => consent = v ?? false),
                          title: const Text(
                              'I approve sharing the combined group names and connections on behalf of my family. All other affected families must also approve. Private records stay separate.')),
                      FilledButton(
                          onPressed:
                              busy || !consent || uncertainSend ? null : send,
                          child: const Text('Send connection request')),
                    ],
                  ])),
          heading('Direct connections',
              'Disconnecting splits the tree. It does not delete a family or its records.'),
          if (!t.connections
              .any((e) => e['a'] == selected || e['b'] == selected))
            const Text('No direct connections.'),
          for (final e in t.connections
              .where((e) => e['a'] == selected || e['b'] == selected))
            panel(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t.name(e['a'])} and ${t.name(e['b'])}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(e['label']),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final sizes = e['disconnectSizes'] as List;
                          if (await confirm('Disconnect families?',
                                  '${t.name(e['a'])} and ${t.name(e['b'])} will no longer be directly linked. This splits the tree into ${sizes[0]} and ${sizes[1]} families. Pending proposals may become invalid. All family records remain.') &&
                              mounted) {
                            await action(
                                '/disconnect/${e['id']}',
                                {'version': t.version},
                                'Connection removed. Remaining branches are kept.');
                          }
                        },
                  child: const Text('Disconnect')),
            ])),
          if (t.role == 'owner' && t.connections.isNotEmpty) ...[
            heading('Leave this tree'),
            const Text(
                'Remove all connections for your family. Other branches may separate. Your family and its records remain.'),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final count = t.connections
                            .where(
                                (e) => e['a'] == selected || e['b'] == selected)
                            .length;
                        if (await confirm('Leave all tree connections?',
                                'Remove $count direct connections for ${t.name(selected)}? Remaining branches may split into separate trees. Rejoining requires a new request. No other family or private record is deleted.') &&
                            mounted) {
                          await action('/leave', {'version': t.version},
                              'Your family is now separate from its former tree.');
                        }
                      },
                child: const Text('Leave tree')),
          ],
        ],
      ];
  @override
  Widget build(BuildContext context) {
    final t = tree;
    return Scaffold(
      appBar: AppBar(title: const Text('Family tree'), actions: [
        IconButton(
            tooltip: 'Refresh tree',
            onPressed: loading || busy
                ? null
                : () {
                    setState(() {
                      actionError = null;
                      notice = null;
                      preview = null;
                      consent = false;
                    });
                    load();
                  },
            icon: const Icon(Icons.refresh))
      ]),
      body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(children: [
                if (busy) const LinearProgressIndicator(),
                if (groups.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: DropdownButtonFormField<String>(
                          key: ValueKey(selected),
                          initialValue: selected,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Viewing as family',
                              border: OutlineInputBorder()),
                          items: groups
                              .map((g) => DropdownMenuItem(
                                  value: g.id,
                                  child: Text(g.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: busy || loading ? null : switchGroup)),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                      for (final (i, label) in [
                        'Tree',
                        'Requests${t != null && t.waiting > 0 ? ' (${t.waiting})' : ''}',
                        'Manage'
                      ].indexed)
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(label),
                                selected: section == i,
                                onSelected: busy
                                    ? null
                                    : (_) => setState(() => section = i))),
                    ])),
                Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: busy ? () async {} : load,
                            child: ListView(
                                key: ValueKey('$selected-$section'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                children: [
                                  if (loadError != null) ...[
                                    Text(loadError!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                    TextButton(
                                        onPressed: busy ? null : load,
                                        child: const Text('Retry'))
                                  ],
                                  if (actionError != null)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(actionError!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                  if (uncertainSend)
                                    panel(Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                              'The send result could not be confirmed. Your input is kept. Refresh Requests before trying again.'),
                                          TextButton(
                                              onPressed: busy ? null : load,
                                              child: const Text(
                                                  'Check requests before retrying')),
                                        ])),
                                  if (notice != null)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(notice!,
                                            style: const TextStyle(
                                                color: Color(0xFF165E3C)))),
                                  if (t != null) ...[
                                    if (section == 0) ...treeView(t),
                                    if (section == 1) ...requestsView(t),
                                    if (section == 2) ...manageView(t)
                                  ],
                                ]))),
              ]))),
    );
  }
}
