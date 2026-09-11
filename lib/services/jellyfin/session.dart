class JellyfinSession {
  const JellyfinSession({
    required this.serverUrl,
    required this.serverId,
    required this.deviceId,
    required this.userId,
    required this.userName,
    required this.accessToken,
  });

  final String serverUrl;
  final String serverId;
  final String deviceId;
  final String userId;
  final String userName;
  final String accessToken;
}
