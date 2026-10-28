import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../providers.dart';

/// 设置页：显示情侣空间信息、手动清理缓存、退出登录
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Couple? _couple;
  bool _clearing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    ref.read(coupleServiceProvider).myCouple().then((c) {
      if (mounted) setState(() => _couple = c);
    });
  }

  Future<void> _clearCache() async {
    setState(() {
      _clearing = true;
      _message = null;
    });
    await ref.read(cacheServiceProvider).clearCache();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _message = '本地缓存已清理（云端记录不受影响）';
    });
  }

  Future<void> _signOut() async {
    await ref.read(authServiceProvider).signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_couple != null) ...[
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('情侣空间'),
              subtitle: Text(
                'ID: ${_couple!.id.substring(0, 8)}…\n邀请码：${_couple!.inviteCode}',
              ),
            ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清理本地缓存'),
            subtitle: const Text('只删除手机上的图片/视频缓存，云端原文件保留'),
            trailing: _clearing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _clearing ? null : _clearCache,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}
