import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../providers.dart';

/// 时光轴主页：云端拉取动态 + 本地缓存离线兜底
class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key});

  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  late Future<Couple> _coupleFuture;

  @override
  void initState() {
    super.initState();
    _coupleFuture = ref.read(coupleServiceProvider).myCouple().then(
          (c) => c ?? (throw StateError('no couple bound')),
        );
  }

  Future<List<Moment>> _load(Couple couple) async {
    final moments =
        await ref.read(momentServiceProvider).listMoments(couple.id);
    // 写入本地缓存（离线兜底）
    final db = ref.read(dbProvider);
    await db.upsertMoments(moments.map(_toLocal).toList());
    return moments;
  }

  LocalMoment _toLocal(Moment m) => LocalMoment(
        id: m.id,
        coupleId: m.coupleId,
        publisherId: m.publisherId,
        content: m.content,
        createdAt: m.createdAt ?? DateTime.now(),
        updatedAt: m.updatedAt ?? DateTime.now(),
      );

  Future<List<Moment>> _loadWithFallback(Couple couple) async {
    try {
      return await _load(couple);
    } catch (_) {
      // 离线：读本地缓存
      final rows =
          await ref.read(dbProvider).cachedMoments(couple.id, limit: 100);
      return rows.map((r) => Moment(
            id: r.id,
            coupleId: r.coupleId,
            publisherId: r.publisherId,
            content: r.content,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
          )).toList();
    }
  }

  Future<void> _delete(Moment m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条动态？'),
        content: const Text('删除后不可恢复（云端与本地同时移除）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(momentServiceProvider).deleteMoment(m.id);
    await ref.read(dbProvider).removeMoment(m.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('时光轴'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).pushNamed('/publish'),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<Couple>(
        future: _coupleFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('尚未绑定情侣空间'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/bind'),
                    child: const Text('去绑定'),
                  ),
                ],
              ),
            );
          }
          final couple = snap.data!;
          return FutureBuilder<List<Moment>>(
            future: _loadWithFallback(couple),
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final moments = s.data ?? const <Moment>[];
              if (moments.isEmpty) {
                return const Center(child: Text('还没有记录，点 + 写下第一条吧'));
              }
              return RefreshIndicator(
                onRefresh: () async {
                  await _load(couple);
                  if (mounted) setState(() {});
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: moments.length,
                  itemBuilder: (context, i) => _MomentCard(
                    moment: moments[i],
                    onDelete: () => _delete(moments[i]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.moment, this.onDelete});

  final Moment moment;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = moment.content == null || moment.content!.isEmpty
        ? '(无文字内容)'
        : moment.content!;
    final time = moment.createdAt == null
        ? ''
        : '${moment.createdAt!.year}-${_two(moment.createdAt!.month)}-${_two(moment.createdAt!.day)} '
            '${_two(moment.createdAt!.hour)}:${_two(moment.createdAt!.minute)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: Theme.of(context).textTheme.bodyLarge),
            if (moment.media.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: moment.media
                    .map((m) => Chip(
                          label: Text(
                            m.mediaType == 'video' ? '🎬 视频' : '🖼 图片',
                            style: const TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(time, style: Theme.of(context).textTheme.bodySmall),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
