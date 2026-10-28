import 'dart:math';

import '../core/api_client.dart';
import '../models/models.dart';

/// 情侣绑定服务（邀请码机制）
class CoupleService {
  CoupleService(this._api);

  final ApiClient _api;

  /// 生成 8 位邀请码（去除易混淆字符 I/O/0/1）
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String generateInviteCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(8, (_) => _alphabet[rng.nextInt(_alphabet.length)])
        .join();
  }

  /// 创建情侣空间（发起方），返回包含邀请码的 Couple
  Future<Couple> createCouple({String? inviteCode}) async {
    final uid = _api.currentUserId;
    if (uid == null) throw StateError('not signed in');
    final data = await _api.dbInsert('couples', {
      'user_a': uid,
      'invite_code': inviteCode ?? generateInviteCode(),
    });
    return Couple.fromJson(data);
  }

  /// 输入邀请码加入（加入方），通过 RPC 完成安全绑定
  Future<Couple> joinCouple(String code) async {
    final uid = _api.currentUserId;
    if (uid == null) throw StateError('not signed in');
    final coupleId = await _api.dbRpc('join_couple', {
      'p_invite_code': code.trim().toUpperCase(),
      'p_user': uid,
    });
    if (coupleId == null) {
      throw Exception('join failed: no couple id returned');
    }
    final list = await _api.dbGet('couples', query: {'id': 'eq.$coupleId'});
    if (list.isEmpty) throw Exception('couple not found');
    return Couple.fromJson(list.first as Map<String, dynamic>);
  }

  /// 查询当前用户所在的情侣空间（未绑定返回 null）
  Future<Couple?> myCouple() async {
    final list = await _api.dbGet('couples', query: {'limit': '1'});
    if (list.isEmpty) return null;
    return Couple.fromJson(list.first as Map<String, dynamic>);
  }
}
