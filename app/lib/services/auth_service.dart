import '../core/api_client.dart';
import '../models/models.dart';

/// 登录认证服务（MemFire Auth）
class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  String? get currentUserId => _api.currentUserId;

  Future<User> signUp(String email, String password) async {
    final data = await _api.signUp(email, password);
    final user = data['user'] as Map<String, dynamic>?;
    if (user == null) {
      throw Exception('signup failed: no user in response');
    }
    return User.fromJson(user);
  }

  Future<User> signIn(String email, String password) async {
    final data = await _api.signIn(email, password);
    final user = data['user'] as Map<String, dynamic>?;
    if (user == null) {
      throw Exception('login failed: no user in response');
    }
    return User.fromJson(user);
  }

  Future<void> signOut() => _api.signOut();
}
