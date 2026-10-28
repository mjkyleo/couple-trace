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
  });

  final String id;
  final String userA;
  final String? userB;
  final String inviteCode;
  final DateTime? createdAt;

  factory Couple.fromJson(Map<String, dynamic> json) => Couple(
        id: json['id'] as String,
        userA: json['user_a'] as String,
        userB: json['user_b'] as String?,
        inviteCode: json['invite_code'] as String,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
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

/// 一条动态
class Moment {
  const Moment({
    required this.id,
    required this.coupleId,
    required this.publisherId,
    this.content,
    this.createdAt,
    this.updatedAt,
    this.media = const [],
  });

  final String id;
  final String coupleId;
  final String publisherId;
  final String? content;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<MomentMedia> media;

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
      );

  Moment copyWith({List<MomentMedia>? media}) => Moment(
        id: id,
        coupleId: coupleId,
        publisherId: publisherId,
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt,
        media: media ?? this.media,
      );
}
