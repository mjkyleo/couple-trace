import 'dart:io';
import 'dart:math';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../core/error_text.dart';
import '../models/models.dart';
import 'moment_service.dart';
import 'storage_service.dart';

/// 一张待上传的本地媒体
class PendingMedia {
  const PendingMedia({
    required this.mediaType,
    required this.bytes,
    required this.extension,
  });

  final String mediaType;
  final List<int> bytes;
  final String extension;
}

/// 媒体上传链路：本地文件 -> （图片压缩）-> 签名 URL PUT -> moment_media 行。
///
/// 压缩只处理图片；视频直传原文件。video_compress 那类插件的原生依赖
/// 在 Dart 3.13 上尚未验证，先用「原文件 + 限时签名 URL 播放」兜住。
class MediaService {
  MediaService(
    this._storage,
    this._moments, {
    Random? random,
    this._imageMaxEdge = 1600,
    this._imageQuality = 82,
  }) : _random = random ?? Random.secure();

  final StorageService _storage;
  final MomentService _moments;
  final Random _random;
  final int _imageMaxEdge;
  final int _imageQuality;

  static const _imageExtensions = {
    '.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.gif',
  };
  static const _videoExtensions = {'.mp4', '.mov', '.m4v', '.webm', '.mkv'};

  static String extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot).toLowerCase();
  }

  static String mediaTypeOf(String path) {
    final ext = extensionOf(path);
    if (_videoExtensions.contains(ext)) return 'video';
    if (_imageExtensions.contains(ext)) return 'image';
    // 无扩展名或未知后缀按图片处理：image_picker 给的路径基本都带扩展名，
    // 真出现未知格式时上传仍会成功，只是客户端按图片渲染。
    return 'image';
  }

  String _fileId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return '$ts$rnd';
  }

  /// 读取本地文件，图片走压缩，视频原样读入
  Future<PendingMedia> load(String path) async {
    final ext = extensionOf(path);
    final type = mediaTypeOf(path);
    if (type == 'image' && _compressible(ext)) {
      final compressed = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: _imageMaxEdge,
        minHeight: _imageMaxEdge,
        quality: _imageQuality,
      );
      // 压缩失败（例如原生层不支持该输入）退回原文件直传，而不是整条动态发不出去
      if (compressed != null) {
        return PendingMedia(
          mediaType: 'image',
          bytes: compressed,
          extension: '.jpg',
        );
      }
    }
    return PendingMedia(
      mediaType: type,
      bytes: await File(path).readAsBytes(),
      extension: ext.isEmpty ? '.bin' : ext,
    );
  }

  static bool _compressible(String ext) =>
      ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp';

  /// 上传单个文件并登记 moment_media 行
  Future<MomentMedia> publish(
    String momentId,
    String coupleId,
    String path, {
    int sort = 0,
  }) async {
    final pending = await load(path);
    final objectKey =
        StorageService.buildObjectKey(coupleId, _fileId(), pending.extension);
    await _storage.upload(objectKey, pending.bytes);
    return _moments.addMedia(momentId, objectKey, pending.mediaType, sort: sort);
  }

  /// 发布整批媒体；单个失败不影响其余
  Future<MediaBatchResult> publishAll(
    String momentId,
    String coupleId,
    List<String> paths,
  ) async {
    final uploaded = <MomentMedia>[];
    String? error;
    for (var i = 0; i < paths.length; i++) {
      try {
        uploaded.add(await publish(momentId, coupleId, paths[i], sort: i));
      } catch (e) {
        error ??= describeError(e);
      }
    }
    return MediaBatchResult(uploaded: uploaded, error: error);
  }

  /// 删除动态时一并清掉对象存储里的文件，避免留下无人引用的计费对象
  Future<void> deleteObjects(Iterable<MomentMedia> media) async {
    for (final m in media) {
      try {
        await _storage.deleteObject(m.objectKey);
      } catch (_) {
        // 云端行已由外键级联删除，对象删除失败只留下孤儿文件，不阻断交互
      }
    }
  }
}

class MediaBatchResult {
  const MediaBatchResult({required this.uploaded, this.error});

  final List<MomentMedia> uploaded;
  final String? error;

  bool get hasError => error != null;
}
