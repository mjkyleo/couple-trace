import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../providers.dart';
import '../theme.dart';
import 'timeline_page.dart' show MediaGrid, formatMomentTime;

/// 动态详情：完整媒体 + 评论与回复。
/// 双方都能评论、能回复别人的评论；删除权限与服务端策略一致：
/// 评论作者删自己的，动态作者删自己动态下的任意评论。
class MomentDetailPage extends ConsumerStatefulWidget {
  const MomentDetailPage({super.key, required this.moment});

  final Moment moment;

  @override
  ConsumerState<MomentDetailPage> createState() => _MomentDetailPageState();
}

class _MomentDetailPageState extends ConsumerState<MomentDetailPage> {
  final _input = TextEditingController();
  Moment? _moment;
  String? _replyTo;
  bool _busy = false;

  String get _myId => ref.read(authServiceProvider).currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _moment = widget.moment;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final comments =
        await ref.read(momentServiceProvider).listComments(_moment!.id);
    if (mounted) setState(() => _moment = _moment!.copyWith(comments: comments));
  }

  Future<void> _submit() async {
    final body = _input.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(momentServiceProvider).addComment(
            _moment!.id,
            _myId,
            body,
            parentId: _replyTo,
          );
      _input.clear();
      setState(() => _replyTo = null);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteComment(MomentComment c) async {
    try {
      await ref.read(momentServiceProvider).deleteComment(c.id);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context)
        .pushNamed('/publish', arguments: _moment);
    if (updated is Moment) setState(() => _moment = updated);
  }

  @override
  Widget build(BuildContext context) {
    final m = _moment;
    if (m == null) return const Scaffold(body: SizedBox.shrink());
    final mine = m.publisherId == _myId;
    final roots = m.comments.where((c) => c.parentId == null).toList();
    final repliesOf = <String, List<MomentComment>>{};
    for (final c in m.comments) {
      final p = c.parentId;
      if (p != null) repliesOf.putIfAbsent(p, () => []).add(c);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('动态'),
        actions: [
          if (mine)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: _edit,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _Dot(id: m.publisherId, myId: _myId),
                    const SizedBox(width: 6),
                    Text(mine ? '我' : 'TA',
                        style: TextStyle(
                            fontSize: 12,
                            color: authorColor(m.publisherId, _myId))),
                    const Spacer(),
                    Text(formatMomentTime(m.createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: TraceColors.inkSoft)),
                  ],
                ),
                if (m.content != null && m.content!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(m.content!,
                      style: const TextStyle(fontSize: 15, height: 1.7)),
                ],
                if (m.media.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  MediaGrid(media: m.media),
                ],
                if (m.locationText != null && m.locationText!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined,
                          size: 14, color: TraceColors.inkSoft),
                      const SizedBox(width: 4),
                      Text(m.locationText!,
                          style: const TextStyle(
                              fontSize: 12, color: TraceColors.inkSoft)),
                    ],
                  ),
                ],
                if (m.isEdited) ...[
                  const SizedBox(height: 6),
                  const Text('已编辑',
                      style:
                          TextStyle(fontSize: 11, color: TraceColors.inkSoft)),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1),
                ),
                Text('评论 ${m.comments.length}',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (roots.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('还没有评论，说点什么吧',
                        style: TextStyle(color: TraceColors.inkSoft)),
                  ),
                for (final c in roots) ...[
                  _CommentRow(
                    comment: c,
                    myId: _myId,
                    canDelete: c.authorId == _myId || mine,
                    onReply: () => setState(() => _replyTo = c.id),
                    onDelete: () => _deleteComment(c),
                  ),
                  for (final r in repliesOf[c.id] ?? const <MomentComment>[])
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: _CommentRow(
                        comment: r,
                        myId: _myId,
                        canDelete: r.authorId == _myId || mine,
                        onReply: () => setState(() => _replyTo = c.id),
                        onDelete: () => _deleteComment(r),
                      ),
                    ),
                ],
              ],
            ),
          ),
          _CommentBar(
            controller: _input,
            busy: _busy,
            replyToLabel: _replyTo == null
                ? null
                : '回复 ${_authorLabel(roots, repliesOf, _replyTo!)}',
            onCancelReply: () => setState(() => _replyTo = null),
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }

  static String _authorLabel(
    List<MomentComment> roots,
    Map<String, List<MomentComment>> repliesOf,
    String id,
  ) {
    for (final c in [...roots, ...repliesOf.values.expand((v) => v)]) {
      if (c.id == id) return c.authorId;
    }
    return '';
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.id, required this.myId});

  final String id;
  final String myId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: authorColor(id, myId),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.myId,
    required this.canDelete,
    required this.onReply,
    required this.onDelete,
  });

  final MomentComment comment;
  final String myId;
  final bool canDelete;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final mine = comment.authorId == myId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: _Dot(id: comment.authorId, myId: myId),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mine ? '我' : 'TA',
                    style: TextStyle(
                        fontSize: 11,
                        color: authorColor(comment.authorId, myId))),
                Text(comment.body,
                    style: const TextStyle(fontSize: 13.5, height: 1.5)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.reply, size: 16),
            tooltip: '回复',
            onPressed: onReply,
          ),
          if (canDelete)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              tooltip: '删除',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _CommentBar extends StatelessWidget {
  const _CommentBar({
    required this.controller,
    required this.busy,
    required this.replyToLabel,
    required this.onCancelReply,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final String? replyToLabel;
  final VoidCallback onCancelReply;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: TraceColors.surface,
          border: Border(top: BorderSide(color: TraceColors.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (replyToLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text('回复 $replyToLabel',
                        style: const TextStyle(
                            fontSize: 11, color: TraceColors.inkSoft)),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onCancelReply,
                      child: const Icon(Icons.close, size: 14),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: 500,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      hintText: '说点什么…',
                      counterText: '',
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : onSubmit,
                  child: const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
