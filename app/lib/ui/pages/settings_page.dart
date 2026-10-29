import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../providers.dart';
import '../theme.dart';

/// 设置页：情侣空间信息、在一起起始日、字号、清理缓存、退出登录
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

  Future<void> _pickStartedOn() async {
    final couple = _couple;
    if (couple == null) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: couple.startedOn ?? now,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      helpText: '在一起的第一天',
    );
    if (picked == null) return;
    try {
      await ref.read(coupleServiceProvider).setStartedOn(picked);
      if (!mounted) return;
      setState(() {
        _couple = Couple(
          id: couple.id,
          userA: couple.userA,
          userB: couple.userB,
          inviteCode: couple.inviteCode,
          createdAt: couple.createdAt,
          startedOn: picked,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _message = '保存失败：$e');
    }
  }

  Future<void> _setTextScale(TextScaleLevel level) async {
    ref.read(textScaleProvider.notifier).state = level;
    await ref
        .read(dbProvider)
        .setPref('text_scale', level.name);
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
      _message = '本地缓存已清理（云端记录与字号设置不受影响）';
    });
  }

  Future<void> _signOut() async {
    await ref.read(authServiceProvider).signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final couple = _couple;
    final scale = ref.watch(textScaleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (couple != null) ...[
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('情侣空间'),
              subtitle: Text(
                'ID: ${couple.id.substring(0, 8)}…\n邀请码：${couple.inviteCode}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('在一起的第一天'),
              subtitle: Text(
                couple.startedOn == null
                    ? '未设置（设了以后时光轴顶部才显示天数）'
                    : _ymd(couple.startedOn!),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickStartedOn,
            ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('字号'),
            subtitle: Text(_scaleLabel(scale)),
          ),
          SegmentedButton<TextScaleLevel>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TextScaleLevel.small, label: Text('小')),
              ButtonSegment(value: TextScaleLevel.normal, label: Text('标准')),
              ButtonSegment(value: TextScaleLevel.large, label: Text('大')),
            ],
            selected: {scale},
            onSelectionChanged: (s) => _setTextScale(s.first),
          ),
          const Divider(),
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

  static String _scaleLabel(TextScaleLevel level) => switch (level) {
        TextScaleLevel.small => '小',
        TextScaleLevel.normal => '标准',
        TextScaleLevel.large => '大',
      };

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
