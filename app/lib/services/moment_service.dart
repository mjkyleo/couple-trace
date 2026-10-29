import '../core/api_client.dart';
import '../models/models.dart';

/// 动态数据服务（PostgREST CRUD + 评论）
class MomentService {
  MomentService(this._api);

  final ApiClient _api;

  /// 一次请求把动态、媒体、评论都取回（PostgREST 资源内嵌）。
  /// 少一次往返，也避免 feed 里逐条查评论。
  /// 作者昵称不走内嵌：auth.users 未对 PostgREST 暴露，
  /// 昵称由客户端按 Couple.userA/userB 对照本地资料渲染。
  static const _feedSelect = '*,moment_media(*),moment_comments(*)';

  /// 拉取某情侣空间的动态（按时间倒序，支持分页）
  Future<List<Moment>> listMoments(
    String coupleId, {
    int limit = 50,
    DateTime? before,
  }) async {
    final query = <String, String>{
      'select': _feedSelect,
      'couple_id': 'eq.$coupleId',
      'order': 'created_at.desc',
      'limit': '$limit',
    };
    if (before != null) {
      query['created_at'] = 'lt.${before.toIso8601String()}';
    }
    try {
      final list = await _api.dbGet('moments', query: query);
      return list
          .map((e) => Moment.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception {
      // 库还没执行 schema_v2 时，moment_comments 不存在会让整条内嵌查询报错。
      // 降级为只取动态，保证 feed 仍可浏览。
      return listMomentsPlain(coupleId, limit: limit, before: before);
    }
  }

  /// 不带内嵌的兜底查询（仅动态 + 媒体由 mediaOf 单独取）
  Future<List<Moment>> listMomentsPlain(
    String coupleId, {
    int limit = 50,
    DateTime? before,
  }) async {
    final query = <String, String>{
      'couple_id': 'eq.$coupleId',
      'order': 'created_at.desc',
      'limit': '$limit',
    };
    if (before != null) {
      query['created_at'] = 'lt.${before.toIso8601String()}';
    }
    final list = await _api.dbGet('moments', query: query);
    return list
        .map((e) => Moment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 发布一条动态（文字 + 可选定位；媒体随后 addMedia）
  Future<Moment> createMoment(
    String coupleId,
    String publisherId, {
    String? content,
    String? locationText,
  }) async {
    final data = await _api.dbInsert('moments', {
      'couple_id': coupleId,
      'publisher_id': publisherId,
      'content': content,
      'location_text': locationText,
    });
    return Moment.fromJson(data);
  }

  /// 作者编辑自己的动态。
  /// 服务端 moment_update 策略限定 publisher_id = auth.uid()，
  /// 且列级授权只放开 content/location_*，改不了归属。
  Future<Moment> updateMoment(
    String momentId, {
    String? content,
    String? locationText,
  }) async {
    final body = <String, dynamic>{
      'content': ?content,
      'location_text': ?locationText,
    };
    if (body.isEmpty) throw ArgumentError('updateMoment: 没有要改的字段');
    final data = await _api.dbUpdate(
      'moments',
      query: {'id': 'eq.$momentId'},
      body: body,
    );
    return Moment.fromJson(data);
  }

  /// 为动态添加媒体记录
  Future<MomentMedia> addMedia(
    String momentId,
    String objectKey,
    String mediaType, {
    String? storageProvider,
    int sort = 0,
  }) async {
    final data = await _api.dbInsert('moment_media', {
      'moment_id': momentId,
      'object_key': objectKey,
      'storage_provider': storageProvider,
      'media_type': mediaType,
      'sort': sort,
    });
    return MomentMedia.fromJson(data);
  }

  /// 删除动态（云端 moments 行删除；moment_media 由外键级联删除）
  Future<void> deleteMoment(String momentId) async {
    await _api.dbDelete('moments', query: {'id': 'eq.$momentId'});
  }

  // ---- 评论 ----

  Future<List<MomentComment>> listComments(String momentId) async {
    final list = await _api.dbGet(
      'moment_comments',
      query: {
        'moment_id': 'eq.$momentId',
        'order': 'created_at.asc',
      },
    );
    return list
        .map((e) => MomentComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 发表评论或回复（[parentId] 非空即回复某条评论）
  Future<MomentComment> addComment(
    String momentId,
    String authorId,
    String body, {
    String? parentId,
  }) async {
    final data = await _api.dbInsert('moment_comments', {
      'moment_id': momentId,
      'author_id': authorId,
      'body': body,
      'parent_id': parentId,
    });
    return MomentComment.fromJson(data);
  }

  /// 删除评论：本人评论自己的，动态作者可删自己动态下的任意评论
  Future<void> deleteComment(String commentId) async {
    await _api.dbDelete('moment_comments', query: {'id': 'eq.$commentId'});
  }
}
