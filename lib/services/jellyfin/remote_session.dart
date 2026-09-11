class RemoteQueueItem {
  const RemoteQueueItem({required this.itemId, this.playlistItemId});

  final String itemId;
  final String? playlistItemId;

  factory RemoteQueueItem.fromJson(Map<String, dynamic> json) =>
      RemoteQueueItem(
        itemId: json['Id'] as String? ?? '',
        playlistItemId: json['PlaylistItemId'] as String?,
      );
}

class RemoteSession {
  const RemoteSession({
    required this.id,
    required this.userId,
    required this.client,
    required this.deviceId,
    required this.deviceName,
    required this.supportsMediaControl,
    required this.isActive,
    required this.position,
    required this.duration,
    required this.paused,
    required this.canSeek,
    required this.volume,
    required this.repeatMode,
    required this.shuffle,
    required this.queue,
    this.nowPlayingItemId,
    this.nowPlayingItemName,
    this.nowPlayingArtist,
    this.nowPlayingAlbum,
    this.playlistItemId,
    this.lastActivity,
  });

  final String id;
  final String userId;
  final String client;
  final String deviceId;
  final String deviceName;
  final bool supportsMediaControl;
  final bool isActive;
  final String? nowPlayingItemId;
  final String? nowPlayingItemName;
  final String? nowPlayingArtist;
  final String? nowPlayingAlbum;
  final String? playlistItemId;
  final Duration position;
  final Duration duration;
  final bool paused;
  final bool canSeek;
  final int volume;
  final String repeatMode;
  final bool shuffle;
  final List<RemoteQueueItem> queue;
  final DateTime? lastActivity;

  bool get isPlaying => nowPlayingItemId != null && !paused;

  factory RemoteSession.fromJson(Map<String, dynamic> json) {
    final item = json['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = json['PlayState'] as Map<String, dynamic>? ?? const {};
    final artists = (item?['Artists'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .join(', ');
    final queue = (json['NowPlayingQueue'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteQueueItem.fromJson)
        .where((item) => item.itemId.isNotEmpty)
        .toList(growable: false);
    return RemoteSession(
      id: json['Id'] as String? ?? '',
      userId: json['UserId'] as String? ?? '',
      client: json['Client'] as String? ?? '',
      deviceId: json['DeviceId'] as String? ?? '',
      deviceName: json['DeviceName'] as String? ?? 'Spotifin device',
      supportsMediaControl: json['SupportsMediaControl'] as bool? ?? false,
      isActive: json['IsActive'] as bool? ?? false,
      nowPlayingItemId: item?['Id'] as String?,
      nowPlayingItemName: item?['Name'] as String?,
      nowPlayingArtist: artists.isEmpty ? null : artists,
      nowPlayingAlbum: item?['Album'] as String?,
      playlistItemId:
          item?['PlaylistItemId'] as String? ??
          playState['PlaylistItemId'] as String?,
      position: _durationFromTicks(playState['PositionTicks']),
      duration: _durationFromTicks(item?['RunTimeTicks']),
      paused: playState['IsPaused'] as bool? ?? true,
      canSeek: playState['CanSeek'] as bool? ?? false,
      volume: (playState['VolumeLevel'] as num?)?.round().clamp(0, 100) ?? 100,
      repeatMode: playState['RepeatMode'] as String? ?? 'RepeatNone',
      shuffle: playState['PlaybackOrder'] == 'Shuffle',
      queue: queue,
      lastActivity: DateTime.tryParse(
        json['LastActivityDate'] as String? ?? '',
      ),
    );
  }
}

Duration _durationFromTicks(Object? ticks) =>
    Duration(microseconds: ticks is num ? ticks.round() ~/ 10 : 0);
