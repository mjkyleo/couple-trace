import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/error_text.dart';
import '../../models/models.dart';
import '../providers.dart';
import '../theme.dart';

/// 发布 / 编辑动态。
///
/// 传 [editing] 即编辑模式：只有文字与定位可改（服务端 moment_update
/// 策略限定作者本人，且列级授权没放开媒体表），发布后把更新后的
/// Moment 弹回给调用方。
class PublishPage extends ConsumerStatefulWidget {
  const PublishPage({super.key, this.editing});

  final Moment? editing;

  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  final _content = TextEditingController();
  final _location = TextEditingController();
  final List<XFile> _picks = [];
  bool _busy = false;
  String? _error;
  String? _progress;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _content.text = widget.editing?.content ?? '';
    _location.text = widget.editing?.locationText ?? '';
  }

  @override
  void dispose() {
    _content.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pick(bool video) async {
    final picker = ImagePicker();
    try {
      if (video) {
        final v = await picker.pickVideo(source: ImageSource.gallery);
        if (v != null) setState(() => _picks.add(XFile(v.path)));
      } else {
        final list = await picker.pickMultiImage();
        if (list.isNotEmpty) setState(() => _picks.addAll(list));
      }
    } catch (e) {
      // 无相册权限 / 桌面端没有实现 —— 降级为纯文字动态，不阻断发布
      developer.log('$e', name: 'trace.pick');
      if (mounted) setState(() => _error = '选图或选视频没成功，可以先只发文字');
    }
  }

  Future<void> _submit() async {
    final text = _content.text.trim();
    final place = _location.text.trim();
    if (text.isEmpty && place.isEmpty && _picks.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final momentService = ref.read(momentServiceProvider);
      final uid = ref.read(authServiceProvider).currentUserId;
      if (uid == null) throw StateError('not signed in');
      final couple = await ref.read(coupleServiceProvider).myPairedCouple();
      if (couple == null) throw StateError('no couple bound');

      if (_isEdit) {
        final updated = await momentService.updateMoment(
          widget.editing!.id,
          content: text,
          locationText: place,
        );
        if (!mounted) return;
        Navigator.of(context).pop(updated);
        return;
      }

      final created = await momentService.createMoment(
        couple.id,
        uid,
        content: text.isEmpty ? null : text,
        locationText: place.isEmpty ? null : place,
      );
      if (_picks.isNotEmpty) {
        setState(() => _progress = '上传媒体 0/${_picks.length}');
        final r = await ref.read(mediaServiceProvider).publishAll(
              created.id,
              couple.id,
              _picks.map((e) => e.path).toList(),
            );
        if (r.error != null) setState(() => _error = '部分媒体上传失败：${r.error}');
      }
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑动态' : '发布动态')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _content,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: '写下今天想记录的事…',
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _location,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: '地点（可留空）',
                hintText: '自己写，例如「公司楼下 · 馄饨摊」',
                counterText: '',
                prefixIcon: Icon(Icons.place_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            if (_isEdit)
              Text(
                '媒体不支持增删，需要换图请删掉这条重发。',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else ...[
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(false),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('图片'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(true),
                    icon: const Icon(Icons.videocam_outlined, size: 18),
                    label: const Text('视频'),
                  ),
                ],
              ),
              if (_picks.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in _picks)
                      InputChip(
                        label: Text(
                          _shortName(p.path),
                          style: const TextStyle(fontSize: 11),
                        ),
                        onDeleted: _busy
                            ? null
                            : () => setState(() => _picks.remove(p)),
                      ),
                  ],
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: TraceColors.alert, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy
                  ? (_progress ?? '处理中…')
                  : (_isEdit ? '保存修改' : '发布')),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortName(String path) {
    final i = path.replaceAll('\\', '/').lastIndexOf('/');
    final name = i >= 0 ? path.substring(i + 1) : path;
    return name.length <= 18 ? name : '${name.substring(0, 15)}…';
  }
}
