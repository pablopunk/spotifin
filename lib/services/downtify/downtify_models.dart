enum DowntifyJobStatus { queued, downloading, done, error, unknown }

class DowntifySong {
  const DowntifySong({
    required this.id,
    required this.name,
    required this.artists,
    required this.albumName,
    required this.coverUri,
    required this.duration,
    required this.sourceUri,
    required this.explicit,
    required this.year,
    required this.raw,
  });

  factory DowntifySong.fromJson(Map<String, dynamic> json) {
    final id = json['song_id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('Downtify returned an invalid song.');
    }
    final artists = switch (json['artists']) {
      final List<dynamic> values => values.whereType<String>().toList(),
      _ => <String>[],
    };
    final fallbackArtist = json['artist'];
    if (artists.isEmpty &&
        fallbackArtist is String &&
        fallbackArtist.isNotEmpty) {
      artists.add(fallbackArtist);
    }
    return DowntifySong(
      id: id,
      name: name,
      artists: artists,
      albumName: json['album_name'] as String? ?? '',
      coverUri: _httpsUri(json['cover_url']),
      duration: _duration(json['duration']),
      sourceUri: _youtubeUri(json['url'], id),
      explicit: json['explicit'] as bool? ?? false,
      year: json['year']?.toString() ?? '',
      raw: Map.unmodifiable(json),
    );
  }

  final String id;
  final String name;
  final List<String> artists;
  final String albumName;
  final Uri? coverUri;
  final Duration? duration;
  final Uri sourceUri;
  final bool explicit;
  final String year;
  final Map<String, dynamic> raw;

  String get artist => artists.isEmpty ? 'Unknown artist' : artists.join(', ');

  static Duration? _duration(Object? value) {
    final seconds = switch (value) {
      final int seconds => seconds,
      final num seconds => seconds.round(),
      final String seconds => int.tryParse(seconds),
      _ => null,
    };
    return seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
  }

  static Uri? _httpsUri(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'https' ? uri : null;
  }

  static Uri _youtubeUri(Object? value, String id) {
    if (value is String) {
      final uri = Uri.tryParse(value);
      if (uri != null &&
          uri.scheme == 'https' &&
          const {
            'youtube.com',
            'www.youtube.com',
            'music.youtube.com',
          }.contains(uri.host)) {
        return uri;
      }
    }
    return Uri.https('music.youtube.com', '/watch', {'v': id});
  }
}

class DowntifyJob {
  const DowntifyJob({
    required this.song,
    required this.status,
    required this.progress,
    required this.message,
    required this.filename,
  });

  factory DowntifyJob.fromJson(Map<String, dynamic> json) {
    final song = json['song'];
    if (song is! Map<String, dynamic>) {
      throw const FormatException('Downtify returned an invalid job.');
    }
    final progress = switch (json['progress']) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value) ?? 0,
      _ => 0.0,
    };
    return DowntifyJob(
      song: DowntifySong.fromJson(song),
      status: switch (json['status']) {
        'queued' => DowntifyJobStatus.queued,
        'downloading' => DowntifyJobStatus.downloading,
        'done' => DowntifyJobStatus.done,
        'error' => DowntifyJobStatus.error,
        _ => DowntifyJobStatus.unknown,
      },
      progress: progress.clamp(0, 100),
      message: json['message'] as String? ?? '',
      filename: json['filename'] as String?,
    );
  }

  final DowntifySong song;
  final DowntifyJobStatus status;
  final double progress;
  final String message;
  final String? filename;
}
