import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/app_database.dart';
import '../../models/models.dart';
import '../providers.dart';
import '../theme.dart';

/// 时光轴主页：绑定门禁 + 动态列表 + 本地缓存离线兜底
class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key});

  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  /// null = 加载中；couple == null = 未创建空间
  bool _loaded = false;
  Couple? _couple;
  List<Moment> _moments = const [];
  String? _loadError;

  String get _myId => ref.read(authServiceProvider).currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _couple = await ref.read(coupleServiceProvider).myCouple();
      if (_couple != null && _couple!.isPaired) {
        _moments = await _loadMoments(_couple!);
      }
    } catch (e) {
      _loadError = e.toString();
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<List<Moment>> _loadMoments(Couple couple) async {
    try {
      final moments =
          await ref.read(momentServiceProvider).listMoments(couple.id);
      await _cache(couple.id, moments);
      return moments;
    } catch (_) {
      final rows =
          await ref.read(dbProvider).cachedMoments(couple.id, limit: 100);
      return rows
          .map((r) => Moment(
                id: r.id,
                coupleId: r.coupleId,
                publisherId: r.publisherId,
                content: r.content,
                locationText: r.locationText,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt,
              ))
          .toList();
    }
  }

  Future<void> _cache(String coupleId, List<Moment> moments) async {
    final db = ref.read(dbProvider);
    await db.upsertMoments([
      for (final m in moments)
        LocalMoment(
          id: m.id,
          coupleId: m.coupleId,
          publisherId: m.publisherId,
          content: m.content,
          locationText: m.locationText,
          createdAt: m.createdAt ?? DateTime.now(),
          updatedAt: m.updatedAt ?? DateTime.now(),
        ),
    ]);
    await db.upsertComments([
      for (final m in moments)
        for (final c in m.comments)
          LocalMomentComment(
            id: c.id,
            momentId: c.momentId,
            authorId: c.authorId,
            parentId: c.parentId,
            body: c.body,
            createdAt: c.createdAt ?? DateTime.now(),
          ),
    ]);
  }

  Future<void> _refresh() async {
    final couple = _couple;
    if (couple == null || !couple.isPaired) return;
    final moments = await _loadMoments(couple);
    if (mounted) setState(() => _moments = moments);
  }

  Future<void> _delete(Moment m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条动态？'),
        content: const Text('文字、图片与视频一并删除，不可恢复。'),
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
    await ref.read(mediaServiceProvider).deleteObjects(m.media);
    await ref.read(dbProvider).removeMoment(m.id);
    await _refresh();
  }

  Future<void> _openDetail(Moment m) async {
    await Navigator.of(context).pushNamed('/moment', arguments: m);
    await _refresh();
  }

  Future<void> _openPublish({Moment? editing}) async {
    await Navigator.of(context).pushNamed('/publish', arguments: editing);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('同迹'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      floatingActionButton: (_couple?.isPaired ?? false)
          ? FloatingActionButton(
              onPressed: () => _openPublish(),
              child: const Icon(Icons.add),
            )
          : null,
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _body(),
    );
  }

  Widget _body() {
    final couple = _couple;
    if (couple == null) {
      return _Gate(
        title: '还没有你们的空间',
        message: '创建情侣空间或输入对方的邀请码，记录只属于你们两个人。',
        actionLabel: '去绑定',
        onAction: () => Navigator.of(context).pushReplacementNamed('/bind'),
      );
    }
    if (!couple.isPaired) {
      return _Gate(
        title: '空间已建好，等 TA 进来',
        message: '把这串邀请码发给对方，TA 输入后你们就可以互相记录了。',
        inviteCode: couple.inviteCode,
        actionLabel: '刷新',
        onAction: _bootstrap,
      );
    }
    if (_loadError != null && _moments.isEmpty) {
      return _Gate(
        title: '没能载入动态',
        message: _loadError!,
        actionLabel: '重试',
        onAction: _bootstrap,
      );
    }
    if (_moments.isEmpty) {
      return _Gate(
        title: '还没有记录',
        message: '点右下角 + 写下第一条，文字、照片、短视频都可以。',
        actionLabel: '写一条',
        onAction: () => _openPublish(),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: _moments.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _DaysHeader(couple: couple);
          final m = _moments[i - 1];
          return _MomentCard(
            moment: m,
            myId: _myId,
            onTap: () => _openDetail(m),
            onEdit: () => _openPublish(editing: m),
            onDelete: () => _delete(m),
          );
        },
      ),
    );
  }
}

/// 门禁/空态通用块
class _Gate extends StatelessWidget {
  const _Gate({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.inviteCode,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? inviteCode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: TraceColors.inkSoft),
            ),
            if (inviteCode != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                inviteCode!,
                style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 4,
                  color: TraceColors.ink,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _DaysHeader extends StatelessWidget {
  const _DaysHeader({required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final started = couple.startedOn;
    if (started == null) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(
          '还没设「在一起的第一天」，可在设置里补上',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final days = DateTime.now().difference(started).inDays + 1;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$days',
            style: const TextStyle(
                fontSize: 30, fontWeight: FontWeight.w300, height: 1),
          ),
          const SizedBox(width: 8),
          Text('在一起第 $days 天',
              style: const TextStyle(fontSize: 12, color: TraceColors.inkSoft)),
        ],
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({
    required this.moment,
    required this.myId,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Moment moment;
  final String myId;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final mine = moment.publisherId == myId;
    final color = authorColor(moment.publisherId, myId);
    final text = moment.content;
    final hasText = text != null && text.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    mine ? '我' : 'TA',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                  const Spacer(),
                  Text(
                    formatMomentTime(moment.createdAt),
                    style: const TextStyle(
                        fontSize: 11, color: TraceColors.inkSoft),
                  ),
                ],
              ),
              if (hasText) ...[
                const SizedBox(height: 8),
                Text(text, style: const TextStyle(fontSize: 14, height: 1.55)),
              ],
              if (moment.media.isNotEmpty) ...[
                const SizedBox(height: 8),
                MediaGrid(media: moment.media),
              ],
              if (moment.locationText != null &&
                  moment.locationText!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 14, color: TraceColors.inkSoft),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        moment.locationText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: TraceColors.inkSoft),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (moment.isEdited)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text('已编辑',
                          style: TextStyle(
                              fontSize: 11, color: TraceColors.inkSoft)),
                    ),
                  Icon(Icons.mode_comment_outlined,
                      size: 15, color: TraceColors.ink),
                  const SizedBox(width: 4),
                  Text('${moment.comments.length}',
                      style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  if (mine) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: '编辑',
                      onPressed: onEdit,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: '删除',
                      onPressed: onDelete,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 时间展示：今年只显示「月-日 时:分」，跨年补年份
String formatMomentTime(DateTime? t) {
  if (t == null) return '';
  final local = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(local.hour)}:${two(local.minute)}';
  final now = DateTime.now();
  if (local.year != now.year) {
    return '${local.year}-${two(local.month)}-${two(local.day)} $hm';
  }
  return '${two(local.month)}-${two(local.day)} $hm';
}

/// 动态的媒体网格：3 列缩略图，视频叠播放标记
class MediaGrid extends StatelessWidget {
  const MediaGrid({super.key, required this.media});

  final List<MomentMedia> media;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: media.map((m) => _Thumb(media: m)).toList(),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.media});

  final MomentMedia media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.read(cacheServiceProvider);
    final isVideo = media.mediaType == 'video';
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed('/preview', arguments: {
          'objectKey': media.objectKey,
          'mediaType': media.mediaType,
        }),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<String>(
              future: cache.signedUrl(media.objectKey),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Container(color: TraceColors.hairline);
                }
                if (snap.hasError) {
                  return Container(
                    color: TraceColors.hairline,
                    child: const Icon(Icons.broken_image_outlined, size: 18),
                  );
                }
                return Image.network(
                  snap.data!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Container(
                    color: TraceColors.hairline,
                    child: const Icon(Icons.broken_image_outlined, size: 18),
                  ),
                );
              },
            ),
            if (isVideo)
              const Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.play_circle_outline,
                      size: 18, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
