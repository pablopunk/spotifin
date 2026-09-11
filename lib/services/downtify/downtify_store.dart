import 'package:shared_preferences/shared_preferences.dart';

import 'downtify_client.dart';

class DowntifyStore {
  const DowntifyStore();

  static const _serverUrlKey = 'downtifyServerUrl';

  Future<String?> loadServerUrl() async {
    final value = (await SharedPreferences.getInstance()).getString(
      _serverUrlKey,
    );
    return value == null || value.isEmpty ? null : value;
  }

  Future<String> saveServerUrl(String value) async {
    final normalized = DowntifyClient.normalizeServerUrl(value);
    await (await SharedPreferences.getInstance()).setString(
      _serverUrlKey,
      normalized,
    );
    return normalized;
  }

  Future<void> clearServerUrl() async {
    await (await SharedPreferences.getInstance()).remove(_serverUrlKey);
  }
}
