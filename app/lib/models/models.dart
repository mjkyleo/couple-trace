/// 用户信息（对应 auth.users 的核心字段）
class User {
  const User({required this.id, this.email});

  final String id;
  final String? email;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String?,
      );
}

/// 情侣绑定关系
class Couple {
  const Couple({
    required this.id,
    required this.userA,
    required this.inviteCode,
    this.userB,
    this.createdAt,
    this.startedOn,
  });

  final String id;
  final String userA;
  final String? userB;
  final String inviteCode;
  final DateTime? createdAt;
  final DateTime? startedOn;

  /// 双方都填上才算绑定完成；未成对的半成品空间不能进时光轴
  bool get isPaired => userB != null && userB!.isNotEmpty;

  factory Couple.fromJson(Map<String, dynamic> json) => Couple(
        id: json['id'] as String,
        userA: json['user_a'] as String,
        userB: json['user_b'] as String?,
        inviteCode: json['invite_code'] as String,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
        startedOn: json['started_on'] != null
            ? DateTime.tryParse(json['started_on'] as String)
            : null,
      );
}

/// 一条动态的媒体资源
class MomentMedia {
  const MomentMedia({
    required this.id,
    required this.momentId,
    required this.objectKey,
    required this.mediaType,
    this.storageProvider,
    this.sort = 0,
  });

  final String id;
  final String momentId;
  final String objectKey;
  final String? storageProvider;

  /// image | video
  final String mediaType;
  final int sort;

  factory MomentMedia.fromJson(Map<String, dynamic> json) => MomentMedia(
        id: json['id'] as String,
        momentId: json['moment_id'] as String,
        objectKey: json['object_key'] as String,
        storageProvider: json['storage_provider'] as String?,
        mediaType: json['media_type'] as String,
        sort: (json['sort'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'moment_id': momentId,
        'object_key': objectKey,
        'storage_provider': storageProvider,
        'media_type': mediaType,
        'sort': sort,
      };
}

/// 一条动态的评论；[parentId] 非空表示对某条评论的回复
class MomentComment {
  const MomentComment({
    required this.id,
    required this.momentId,
    required this.authorId,
    required this.body,
    this.parentId,
    this.createdAt,
  });

  final String id;
  final String momentId;
  final String authorId;
  final String body;
  final String? parentId;
  final DateTime? createdAt;

  factory MomentComment.fromJson(Map<String, dynamic> json) => MomentComment(
        id: json['id'] as String,
        momentId: json['moment_id'] as String,
        authorId: json['author_id'] as String,
        body: json['body'] as String,
        parentId: json['parent_id'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'moment_id': momentId,
        'author_id': authorId,
        'body': body,
        'parent_id': parentId,
      };
}

/// 一条动态
class Moment {
  const Moment({
    required this.id,
    required this.coupleId,
    required this.publisherId,
    this.content,
    this.createdAt,
    this.updatedAt,
    this.locationText,
    this.media = const [],
    this.comments = const [],
  });

  final String id;
  final String coupleId;
  final String publisherId;
  final String? content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 手动输入的地点；经纬度留给后续地图 SDK
  final String? locationText;
  final List<MomentMedia> media;
  final List<MomentComment> comments;

  /// updated_at 由数据库触发器在 UPDATE 时刷新，
  /// 因此「晚于 created_at」即等价于「作者改过内容」。
  bool get isEdited {
    final c = createdAt;
    final u = updatedAt;
    if (c == null || u == null) return false;
    return u.isAfter(c.add(const Duration(seconds: 1)));
  }

  factory Moment.fromJson(Map<String, dynamic> json) => Moment(
        id: json['id'] as String,
        coupleId: json['couple_id'] as String,
        publisherId: json['publisher_id'] as String,
        content: json['content'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'] as String)
            : null,
        locationText: json['location_text'] as String?,
        media: _mediaFrom(json['moment_media']),
        comments: _commentsFrom(json['moment_comments']),
      );

  /// PostgREST 的资源内嵌（`select=*,moment_media(*)`）返回数组；
  /// 不带内嵌查询时该键缺失，此时保持空列表而不是抛类型转换异常。
  static List<MomentMedia> _mediaFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MomentMedia.fromJson)
        .toList();
  }

  static List<MomentComment> _commentsFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MomentComment.fromJson)
        .toList();
  }

  Moment copyWith({
    String? content,
    String? locationText,
    List<MomentMedia>? media,
    List<MomentComment>? comments,
    DateTime? updatedAt,
  }) =>
      Moment(
        id: id,
        coupleId: coupleId,
        publisherId: publisherId,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        locationText: locationText ?? this.locationText,
        media: media ?? this.media,
        comments: comments ?? this.comments,
      );
}
