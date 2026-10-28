import '../core/api_client.dart';
import '../models/models.dart';

/// 动态数据服务（PostgREST CRUD）
class MomentService {
  MomentService(this._api);

  final ApiClient _api;

  /// 拉取某情侣空间的动态（按时间倒序，支持分页）
  Future<List<Moment>> listMoments(
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

  /// 发布一条动态（文字部分；媒体随后 addMedia）
  Future<Moment> createMoment(
    String coupleId,
    String publisherId, {
    String? content,
  }) async {
    final data = await _api.dbInsert('moments', {
      'couple_id': coupleId,
      'publisher_id': publisherId,
      'content': content,
    });
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
}
