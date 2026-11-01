import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/family_group.dart';
import '../models/family_tree.dart';
import '../services/family_service.dart';
import 'family_page.dart';

/// Each subtree owns a separate vertical interval, so sibling cards never overlap.
class FamilyTreeLayout {
  FamilyTreeLayout(FamilyTreeSnapshot tree, {double textScale = 1}) {
    nodeSize = Size(260 * textScale, 156 * textScale);
    final outline = tree.outline;
    final children = <String, List<String>>{};
    for (final n in outline) {
      if (n['parent'] != null) {
        children.putIfAbsent(n['parent'], () => []).add(n['id']);
      }
    }
    double leaf = 0;
    double place(String id, int depth) {
      final kids = children[id] ?? [];
      final ys = [for (final c in kids) place(c, depth + 1)];
      final y = ys.isEmpty
          ? leaf++ * (nodeSize.height + 44)
          : (ys.first + ys.last) / 2;
      positions[id] = Offset(40 + depth * (nodeSize.width + 100), 40 + y);
      return y;
    }

    if (outline.isNotEmpty) place(tree.groupId, 0);
    size = Size(
        positions.values.fold(0.0, (v, p) => math.max(v, p.dx)) +
            nodeSize.width +
            40,
        positions.values.fold(0.0, (v, p) => math.max(v, p.dy)) +
            nodeSize.height +
            40);
  }
  final positions = <String, Offset>{};
  late final Size nodeSize, size;
}

class FamilyTreeCanvasPage extends StatefulWidget {
  const FamilyTreeCanvasPage(
      {super.key, required this.api, required this.initial});
  final FamilyService api;
  final FamilyTreeSnapshot initial;
  @override
  State<FamilyTreeCanvasPage> createState() => _FamilyTreeCanvasPageState();
}

class _FamilyTreeCanvasPageState extends State<FamilyTreeCanvasPage> {
  final transform = TransformationController();
  late FamilyTreeSnapshot tree = widget.initial;
  FamilyTreeLayout? layout;
  Size viewport = Size.zero;
  String? error;
  bool loading = false;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  void fit() {
    final l = layout;
    if (l == null || viewport.isEmpty) return;
    final scale = math
        .min(viewport.width / l.size.width, viewport.height / l.size.height)
        .clamp(.01, 1.0);
    transform.value = Matrix4.identity()
      ..translateByDouble((viewport.width - l.size.width * scale) / 2,
          (viewport.height - l.size.height * scale) / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void zoom(double scale) {
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final scene = transform.toScene(center);
    final next = scale.clamp(.01, 3.0);
    transform.value = Matrix4.identity()
      ..translateByDouble(
          center.dx - scene.dx * next, center.dy - scene.dy * next, 0, 1)
      ..scaleByDouble(next, next, 1, 1);
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data =
          await widget.api.request('GET', '/families/${tree.groupId}/tree');
      if (!mounted) return;
      setState(() {
        tree = FamilyTreeSnapshot(data);
        layout = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> details(FamilyJson node) async {
    final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              constraints: const BoxConstraints(maxWidth: 600),
              scrollable: true,
              title: Text(node['name']),
              content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (node['id'] == tree.groupId)
                      const Text('Selected family'),
                    for (final edge in tree.connections.where(
                        (e) => e['a'] == node['id'] || e['b'] == node['id']))
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                              '${tree.name(edge['a'] == node['id'] ? edge['b'] : edge['a'])}: ${edge['label']}')),
                    Text(node['canOpen'] == true
                        ? 'You belong to this family and can open its details.'
                        : 'Connected group only. Ask its administrator for a membership invite to join. Private records stay separate.'),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Close')),
                if (node['canOpen'] == true)
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Open family'))
              ],
            ));
    if (open == true && mounted) {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) =>
                  FamilyGroupPage(api: widget.api, groupId: node['id'])));
      if (mounted) await refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (layout == null || layout!.nodeSize.width != 260 * scale) {
      layout = FamilyTreeLayout(tree, textScale: scale);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fit();
      });
    }
    final l = layout!;
    return Scaffold(
      appBar: AppBar(title: const Text('Large family tree'), actions: [
        IconButton(
            tooltip: 'Refresh tree',
            onPressed: loading ? null : refresh,
            icon: const Icon(Icons.refresh))
      ]),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(children: [
              Text(
                  error != null
                      ? 'Unable to load this tree.'
                      : '${tree.nodes.length} ${tree.nodes.length == 1 ? 'family' : 'families'} · Drag to move. Tap a family for details.',
                  textAlign: TextAlign.center),
              const Text(
                  'Lines show agreed connections. Position does not show ancestry.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                        onPressed: loading || error != null
                            ? null
                            : () =>
                                zoom(transform.value.getMaxScaleOnAxis() * 1.3),
                        icon: const Icon(Icons.add),
                        label: const Text('Zoom in')),
                    OutlinedButton.icon(
                        onPressed: loading || error != null
                            ? null
                            : () =>
                                zoom(transform.value.getMaxScaleOnAxis() / 1.3),
                        icon: const Icon(Icons.remove),
                        label: const Text('Zoom out')),
                    FilledButton.icon(
                        onPressed: loading || error != null ? null : fit,
                        icon: const Icon(Icons.fit_screen),
                        label: const Text('Show all')),
                    OutlinedButton(
                        onPressed:
                            loading || error != null ? null : () => zoom(1),
                        child: const Text('100%')),
                  ]),
            ])),
        Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(error!),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                      onPressed: refresh,
                                      child: const Text('Retry'))
                                ])))
                    : LayoutBuilder(builder: (context, constraints) {
                        final nextViewport = constraints.biggest;
                        if (nextViewport != viewport) {
                          viewport = nextViewport;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) fit();
                          });
                        }
                        return ColoredBox(
                            color: const Color(0xFFF0F5FA),
                            child: InteractiveViewer(
                              key: const ValueKey('tree-canvas'),
                              transformationController: transform,
                              constrained: false,
                              alignment: Alignment.topLeft,
                              boundaryMargin: const EdgeInsets.all(20000),
                              minScale: .01,
                              maxScale: 3,
                              child: SizedBox(
                                  width: l.size.width,
                                  height: l.size.height,
                                  child: Stack(children: [
                                    Positioned.fill(
                                        child: CustomPaint(
                                            painter:
                                                _ConnectionsPainter(tree, l))),
                                    for (final n in tree.outline)
                                      Positioned(
                                          left: l.positions[n['id']]!.dx,
                                          top: l.positions[n['id']]!.dy,
                                          width: l.nodeSize.width,
                                          height: l.nodeSize.height,
                                          child: Semantics(
                                              onTap: () => details(n),
                                              button: true,
                                              label:
                                                  '${n['name']}. ${n['id'] == tree.groupId ? 'Selected family.' : 'Connected family.'} View details',
                                              excludeSemantics: true,
                                              child: Card(
                                                  color: n['id'] == tree.groupId
                                                      ? const Color(0xFFDCEBFF)
                                                      : Colors.white,
                                                  margin: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      side: BorderSide(
                                                          color: n['id'] ==
                                                                  tree.groupId
                                                              ? const Color(
                                                                  0xFF246BCE)
                                                              : const Color(
                                                                  0xFF71889F),
                                                          width: 2)),
                                                  child: InkWell(
                                                    onTap: () => details(n),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(16),
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(n['name'],
                                                                  maxLines: 2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          20,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold)),
                                                              const SizedBox(
                                                                  height: 8),
                                                              Text(
                                                                  n['id'] ==
                                                                          tree
                                                                              .groupId
                                                                      ? 'Selected family'
                                                                      : n[
                                                                          'label'],
                                                                  maxLines: 2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          16)),
                                                              const Spacer(),
                                                              const Text(
                                                                  'Tap for details',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          14)),
                                                            ])),
                                                  )))),
                                  ])),
                            ));
                      })),
      ])),
    );
  }
}

class _ConnectionsPainter extends CustomPainter {
  _ConnectionsPainter(this.tree, this.layout);
  final FamilyTreeSnapshot tree;
  final FamilyTreeLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = const Color(0xFF456A91)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final node in tree.outline.where((n) => n['parent'] != null)) {
      final a = layout.positions[node['parent']]! +
          Offset(layout.nodeSize.width, layout.nodeSize.height / 2);
      final b =
          layout.positions[node['id']]! + Offset(0, layout.nodeSize.height / 2);
      final mid = (a.dx + b.dx) / 2;
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(mid, a.dy)
            ..lineTo(mid, b.dy)
            ..lineTo(b.dx, b.dy),
          pen);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) =>
      oldDelegate.tree != tree || oldDelegate.layout != layout;
}
