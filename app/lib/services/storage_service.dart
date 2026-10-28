import '../core/api_client.dart';

/// 统一存储服务：客户端只依赖三个固定接口，
/// 完全不感知后端是 COS / OSS / S3 / MinIO。
class StorageService {
  StorageService(this._api);

  final ApiClient _api;

  Future<String> getUploadSign(String objectKey) async {
    final res = await _api.storageCall(
      '/storage/get_upload_sign',
      {'objectKey': objectKey},
    );
    return res['url'] as String;
  }

  Future<String> getDownloadSign(String objectKey) async {
    final res = await _api.storageCall(
      '/storage/get_download_sign',
      {'objectKey': objectKey},
    );
    return res['url'] as String;
  }

  Future<void> deleteObject(String objectKey) async {
    await _api.storageCall('/storage/delete_object', {'objectKey': objectKey});
  }

  /// 上传文件字节到对象存储
  Future<void> upload(String objectKey, List<int> bytes) async {
    final url = await getUploadSign(objectKey);
    await _api.uploadToSignedUrl(url, bytes);
  }

  /// 下载对象存储文件到本地路径
  Future<void> download(String objectKey, String savePath) async {
    final url = await getDownloadSign(objectKey);
    await _api.downloadToFile(url, savePath);
  }

  /// 生成 objectKey：`<coupleId>/<uuid>.<ext>`
  static String buildObjectKey(
    String coupleId,
    String fileId,
    String extension,
  ) =>
      '$coupleId/$fileId$extension';
}
