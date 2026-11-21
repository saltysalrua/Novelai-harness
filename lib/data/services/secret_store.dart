import 'package:shared_preferences/shared_preferences.dart';

/// 敏感凭证存储抽象边界，隔离 API Key / Token 与普通应用偏好配置。
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 默认基于 SharedPreferences 的凭证存储实现，保持既有持久化键与零迁移兼容。
class SharedPreferencesSecretStore implements SecretStore {
  const SharedPreferencesSecretStore();

  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, value)) {
      throw StateError('密钥保存失败: $key');
    }
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(key)) {
      throw StateError('密钥删除失败: $key');
    }
  }
}
