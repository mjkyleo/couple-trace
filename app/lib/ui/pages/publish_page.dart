import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// 发布动态页（MVP：文字动态；媒体接入点已预留）
/// 接入真机媒体后，流程为：
///   1. 本地压缩图片/视频
///   2. storage.upload(objectKey, bytes) 上传到对象存储
///   3. momentService.addMedia(...) 记录媒体元数据
class PublishPage extends ConsumerStatefulWidget {
  const PublishPage({super.key});

  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  final _content = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _content.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final coupleService = ref.read(coupleServiceProvider);
      final momentService = ref.read(momentServiceProvider);
      final uid = auth.currentUserId;
      if (uid == null) throw StateError('not signed in');
      final couple = await coupleService.myCouple();
      if (couple == null) throw StateError('no couple bound');
      await momentService.createMoment(couple.id, uid, content: text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布动态')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _content,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: '写下今天想记录的事…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.photo_library_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '图片/视频：在真机接入 image_picker 后可用（见 README 二期说明）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _publish,
              child: Text(_busy ? '发布中…' : '发布'),
            ),
          ],
        ),
      ),
    );
  }
}
