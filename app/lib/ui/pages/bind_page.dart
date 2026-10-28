import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// 情侣绑定页：创建空间（生成邀请码）或输入邀请码加入
class BindPage extends ConsumerStatefulWidget {
  const BindPage({super.key});

  @override
  ConsumerState<BindPage> createState() => _BindPageState();
}

class _BindPageState extends ConsumerState<BindPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final couple = await ref.read(coupleServiceProvider).myCouple();
      if (!mounted) return;
      if (couple != null) {
        Navigator.of(context).pushReplacementNamed('/timeline');
      }
    } catch (_) {
      // 网络异常时停留在绑定页，允许重试
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(coupleServiceProvider).createCouple();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/timeline');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(coupleServiceProvider).joinCouple(_code.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/timeline');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('情侣空间')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '创建属于两个人的私密空间',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '创建后生成邀请码，另一半输入即可绑定；'
              '所有记录仅你们二人可见。',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text('创建情侣空间'),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '输入对方邀请码',
                border: OutlineInputBorder(),
                hintText: '例如：A7K2Q9X4',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _join,
              child: const Text('加入情侣空间'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
