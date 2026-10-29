import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/token_store.dart';
import '../db/app_database.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/couple_service.dart';
import '../services/media_service.dart';
import '../services/moment_service.dart';
import '../services/storage_service.dart';
import 'theme.dart';

/// 全局依赖注入（main 中必须 override tokenStoreProvider）

/// 字号档位：观感类偏好只存本机（每对情侣独立部署，没必要上云）
final textScaleProvider = StateProvider<TextScaleLevel>(
  (ref) => TextScaleLevel.normal,
);

final dioProvider = Provider<Dio>((ref) => Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    ));

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => throw UnimplementedError('override in main()'),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    dio: ref.watch(dioProvider),
    tokens: ref.watch(tokenStoreProvider),
  ),
);

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final authServiceProvider =
    Provider<AuthService>((ref) => AuthService(ref.watch(apiClientProvider)));

final coupleServiceProvider = Provider<CoupleService>(
  (ref) => CoupleService(ref.watch(apiClientProvider)),
);

final momentServiceProvider = Provider<MomentService>(
  (ref) => MomentService(ref.watch(apiClientProvider)),
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(ref.watch(apiClientProvider)),
);

final mediaServiceProvider = Provider<MediaService>(
  (ref) => MediaService(
    ref.watch(storageServiceProvider),
    ref.watch(momentServiceProvider),
  ),
);

final cacheServiceProvider = Provider<CacheService>(
  (ref) => CacheService(ref.watch(apiClientProvider), ref.watch(dbProvider)),
);
