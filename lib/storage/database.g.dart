// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, Track> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Unknown artist'),
  );
  static const VerificationMeta _artistIdsMeta = const VerificationMeta(
    'artistIds',
  );
  @override
  late final GeneratedColumn<String> artistIds = GeneratedColumn<String>(
    'artist_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _labelsMeta = const VerificationMeta('labels');
  @override
  late final GeneratedColumn<String> labels = GeneratedColumn<String>(
    'labels',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _durationTicksMeta = const VerificationMeta(
    'durationTicks',
  );
  @override
  late final GeneratedColumn<int> durationTicks = GeneratedColumn<int>(
    'duration_ticks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _imageTagMeta = const VerificationMeta(
    'imageTag',
  );
  @override
  late final GeneratedColumn<String> imageTag = GeneratedColumn<String>(
    'image_tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _containerMeta = const VerificationMeta(
    'container',
  );
  @override
  late final GeneratedColumn<String> container = GeneratedColumn<String>(
    'container',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('mp3'),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _normalizationGainMeta = const VerificationMeta(
    'normalizationGain',
  );
  @override
  late final GeneratedColumn<double> normalizationGain =
      GeneratedColumn<double>(
        'normalization_gain',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _albumNormalizationGainMeta =
      const VerificationMeta('albumNormalizationGain');
  @override
  late final GeneratedColumn<double> albumNormalizationGain =
      GeneratedColumn<double>(
        'album_normalization_gain',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastPlayedMeta = const VerificationMeta(
    'lastPlayed',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayed = GeneratedColumn<DateTime>(
    'last_played',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateCreatedMeta = const VerificationMeta(
    'dateCreated',
  );
  @override
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
    'date_created',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    album,
    albumId,
    artist,
    artistIds,
    labels,
    durationTicks,
    imageTag,
    container,
    favorite,
    playCount,
    normalizationGain,
    albumNormalizationGain,
    lastPlayed,
    dateCreated,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Track> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('artist_ids')) {
      context.handle(
        _artistIdsMeta,
        artistIds.isAcceptableOrUnknown(data['artist_ids']!, _artistIdsMeta),
      );
    }
    if (data.containsKey('labels')) {
      context.handle(
        _labelsMeta,
        labels.isAcceptableOrUnknown(data['labels']!, _labelsMeta),
      );
    }
    if (data.containsKey('duration_ticks')) {
      context.handle(
        _durationTicksMeta,
        durationTicks.isAcceptableOrUnknown(
          data['duration_ticks']!,
          _durationTicksMeta,
        ),
      );
    }
    if (data.containsKey('image_tag')) {
      context.handle(
        _imageTagMeta,
        imageTag.isAcceptableOrUnknown(data['image_tag']!, _imageTagMeta),
      );
    }
    if (data.containsKey('container')) {
      context.handle(
        _containerMeta,
        container.isAcceptableOrUnknown(data['container']!, _containerMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('normalization_gain')) {
      context.handle(
        _normalizationGainMeta,
        normalizationGain.isAcceptableOrUnknown(
          data['normalization_gain']!,
          _normalizationGainMeta,
        ),
      );
    }
    if (data.containsKey('album_normalization_gain')) {
      context.handle(
        _albumNormalizationGainMeta,
        albumNormalizationGain.isAcceptableOrUnknown(
          data['album_normalization_gain']!,
          _albumNormalizationGainMeta,
        ),
      );
    }
    if (data.containsKey('last_played')) {
      context.handle(
        _lastPlayedMeta,
        lastPlayed.isAcceptableOrUnknown(data['last_played']!, _lastPlayedMeta),
      );
    }
    if (data.containsKey('date_created')) {
      context.handle(
        _dateCreatedMeta,
        dateCreated.isAcceptableOrUnknown(
          data['date_created']!,
          _dateCreatedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Track map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Track(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      )!,
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      ),
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      artistIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_ids'],
      )!,
      labels: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}labels'],
      )!,
      durationTicks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ticks'],
      )!,
      imageTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_tag'],
      ),
      container: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      normalizationGain: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}normalization_gain'],
      ),
      albumNormalizationGain: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}album_normalization_gain'],
      ),
      lastPlayed: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played'],
      ),
      dateCreated: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_created'],
      ),
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class Track extends DataClass implements Insertable<Track> {
  final String id;
  final String name;
  final String album;
  final String? albumId;
  final String artist;
  final String artistIds;
  final String labels;
  final int durationTicks;
  final String? imageTag;
  final String container;
  final bool favorite;
  final int playCount;
  final double? normalizationGain;
  final double? albumNormalizationGain;
  final DateTime? lastPlayed;
  final DateTime? dateCreated;
  const Track({
    required this.id,
    required this.name,
    required this.album,
    this.albumId,
    required this.artist,
    required this.artistIds,
    required this.labels,
    required this.durationTicks,
    this.imageTag,
    required this.container,
    required this.favorite,
    required this.playCount,
    this.normalizationGain,
    this.albumNormalizationGain,
    this.lastPlayed,
    this.dateCreated,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['album'] = Variable<String>(album);
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<String>(albumId);
    }
    map['artist'] = Variable<String>(artist);
    map['artist_ids'] = Variable<String>(artistIds);
    map['labels'] = Variable<String>(labels);
    map['duration_ticks'] = Variable<int>(durationTicks);
    if (!nullToAbsent || imageTag != null) {
      map['image_tag'] = Variable<String>(imageTag);
    }
    map['container'] = Variable<String>(container);
    map['favorite'] = Variable<bool>(favorite);
    map['play_count'] = Variable<int>(playCount);
    if (!nullToAbsent || normalizationGain != null) {
      map['normalization_gain'] = Variable<double>(normalizationGain);
    }
    if (!nullToAbsent || albumNormalizationGain != null) {
      map['album_normalization_gain'] = Variable<double>(
        albumNormalizationGain,
      );
    }
    if (!nullToAbsent || lastPlayed != null) {
      map['last_played'] = Variable<DateTime>(lastPlayed);
    }
    if (!nullToAbsent || dateCreated != null) {
      map['date_created'] = Variable<DateTime>(dateCreated);
    }
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      name: Value(name),
      album: Value(album),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      artist: Value(artist),
      artistIds: Value(artistIds),
      labels: Value(labels),
      durationTicks: Value(durationTicks),
      imageTag: imageTag == null && nullToAbsent
          ? const Value.absent()
          : Value(imageTag),
      container: Value(container),
      favorite: Value(favorite),
      playCount: Value(playCount),
      normalizationGain: normalizationGain == null && nullToAbsent
          ? const Value.absent()
          : Value(normalizationGain),
      albumNormalizationGain: albumNormalizationGain == null && nullToAbsent
          ? const Value.absent()
          : Value(albumNormalizationGain),
      lastPlayed: lastPlayed == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayed),
      dateCreated: dateCreated == null && nullToAbsent
          ? const Value.absent()
          : Value(dateCreated),
    );
  }

  factory Track.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Track(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      album: serializer.fromJson<String>(json['album']),
      albumId: serializer.fromJson<String?>(json['albumId']),
      artist: serializer.fromJson<String>(json['artist']),
      artistIds: serializer.fromJson<String>(json['artistIds']),
      labels: serializer.fromJson<String>(json['labels']),
      durationTicks: serializer.fromJson<int>(json['durationTicks']),
      imageTag: serializer.fromJson<String?>(json['imageTag']),
      container: serializer.fromJson<String>(json['container']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      playCount: serializer.fromJson<int>(json['playCount']),
      normalizationGain: serializer.fromJson<double?>(
        json['normalizationGain'],
      ),
      albumNormalizationGain: serializer.fromJson<double?>(
        json['albumNormalizationGain'],
      ),
      lastPlayed: serializer.fromJson<DateTime?>(json['lastPlayed']),
      dateCreated: serializer.fromJson<DateTime?>(json['dateCreated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'album': serializer.toJson<String>(album),
      'albumId': serializer.toJson<String?>(albumId),
      'artist': serializer.toJson<String>(artist),
      'artistIds': serializer.toJson<String>(artistIds),
      'labels': serializer.toJson<String>(labels),
      'durationTicks': serializer.toJson<int>(durationTicks),
      'imageTag': serializer.toJson<String?>(imageTag),
      'container': serializer.toJson<String>(container),
      'favorite': serializer.toJson<bool>(favorite),
      'playCount': serializer.toJson<int>(playCount),
      'normalizationGain': serializer.toJson<double?>(normalizationGain),
      'albumNormalizationGain': serializer.toJson<double?>(
        albumNormalizationGain,
      ),
      'lastPlayed': serializer.toJson<DateTime?>(lastPlayed),
      'dateCreated': serializer.toJson<DateTime?>(dateCreated),
    };
  }

  Track copyWith({
    String? id,
    String? name,
    String? album,
    Value<String?> albumId = const Value.absent(),
    String? artist,
    String? artistIds,
    String? labels,
    int? durationTicks,
    Value<String?> imageTag = const Value.absent(),
    String? container,
    bool? favorite,
    int? playCount,
    Value<double?> normalizationGain = const Value.absent(),
    Value<double?> albumNormalizationGain = const Value.absent(),
    Value<DateTime?> lastPlayed = const Value.absent(),
    Value<DateTime?> dateCreated = const Value.absent(),
  }) => Track(
    id: id ?? this.id,
    name: name ?? this.name,
    album: album ?? this.album,
    albumId: albumId.present ? albumId.value : this.albumId,
    artist: artist ?? this.artist,
    artistIds: artistIds ?? this.artistIds,
    labels: labels ?? this.labels,
    durationTicks: durationTicks ?? this.durationTicks,
    imageTag: imageTag.present ? imageTag.value : this.imageTag,
    container: container ?? this.container,
    favorite: favorite ?? this.favorite,
    playCount: playCount ?? this.playCount,
    normalizationGain: normalizationGain.present
        ? normalizationGain.value
        : this.normalizationGain,
    albumNormalizationGain: albumNormalizationGain.present
        ? albumNormalizationGain.value
        : this.albumNormalizationGain,
    lastPlayed: lastPlayed.present ? lastPlayed.value : this.lastPlayed,
    dateCreated: dateCreated.present ? dateCreated.value : this.dateCreated,
  );
  Track copyWithCompanion(TracksCompanion data) {
    return Track(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      album: data.album.present ? data.album.value : this.album,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      artist: data.artist.present ? data.artist.value : this.artist,
      artistIds: data.artistIds.present ? data.artistIds.value : this.artistIds,
      labels: data.labels.present ? data.labels.value : this.labels,
      durationTicks: data.durationTicks.present
          ? data.durationTicks.value
          : this.durationTicks,
      imageTag: data.imageTag.present ? data.imageTag.value : this.imageTag,
      container: data.container.present ? data.container.value : this.container,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      normalizationGain: data.normalizationGain.present
          ? data.normalizationGain.value
          : this.normalizationGain,
      albumNormalizationGain: data.albumNormalizationGain.present
          ? data.albumNormalizationGain.value
          : this.albumNormalizationGain,
      lastPlayed: data.lastPlayed.present
          ? data.lastPlayed.value
          : this.lastPlayed,
      dateCreated: data.dateCreated.present
          ? data.dateCreated.value
          : this.dateCreated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Track(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('album: $album, ')
          ..write('albumId: $albumId, ')
          ..write('artist: $artist, ')
          ..write('artistIds: $artistIds, ')
          ..write('labels: $labels, ')
          ..write('durationTicks: $durationTicks, ')
          ..write('imageTag: $imageTag, ')
          ..write('container: $container, ')
          ..write('favorite: $favorite, ')
          ..write('playCount: $playCount, ')
          ..write('normalizationGain: $normalizationGain, ')
          ..write('albumNormalizationGain: $albumNormalizationGain, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('dateCreated: $dateCreated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    album,
    albumId,
    artist,
    artistIds,
    labels,
    durationTicks,
    imageTag,
    container,
    favorite,
    playCount,
    normalizationGain,
    albumNormalizationGain,
    lastPlayed,
    dateCreated,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track &&
          other.id == this.id &&
          other.name == this.name &&
          other.album == this.album &&
          other.albumId == this.albumId &&
          other.artist == this.artist &&
          other.artistIds == this.artistIds &&
          other.labels == this.labels &&
          other.durationTicks == this.durationTicks &&
          other.imageTag == this.imageTag &&
          other.container == this.container &&
          other.favorite == this.favorite &&
          other.playCount == this.playCount &&
          other.normalizationGain == this.normalizationGain &&
          other.albumNormalizationGain == this.albumNormalizationGain &&
          other.lastPlayed == this.lastPlayed &&
          other.dateCreated == this.dateCreated);
}

class TracksCompanion extends UpdateCompanion<Track> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> album;
  final Value<String?> albumId;
  final Value<String> artist;
  final Value<String> artistIds;
  final Value<String> labels;
  final Value<int> durationTicks;
  final Value<String?> imageTag;
  final Value<String> container;
  final Value<bool> favorite;
  final Value<int> playCount;
  final Value<double?> normalizationGain;
  final Value<double?> albumNormalizationGain;
  final Value<DateTime?> lastPlayed;
  final Value<DateTime?> dateCreated;
  final Value<int> rowid;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.album = const Value.absent(),
    this.albumId = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistIds = const Value.absent(),
    this.labels = const Value.absent(),
    this.durationTicks = const Value.absent(),
    this.imageTag = const Value.absent(),
    this.container = const Value.absent(),
    this.favorite = const Value.absent(),
    this.playCount = const Value.absent(),
    this.normalizationGain = const Value.absent(),
    this.albumNormalizationGain = const Value.absent(),
    this.lastPlayed = const Value.absent(),
    this.dateCreated = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TracksCompanion.insert({
    required String id,
    required String name,
    this.album = const Value.absent(),
    this.albumId = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistIds = const Value.absent(),
    this.labels = const Value.absent(),
    this.durationTicks = const Value.absent(),
    this.imageTag = const Value.absent(),
    this.container = const Value.absent(),
    this.favorite = const Value.absent(),
    this.playCount = const Value.absent(),
    this.normalizationGain = const Value.absent(),
    this.albumNormalizationGain = const Value.absent(),
    this.lastPlayed = const Value.absent(),
    this.dateCreated = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Track> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? album,
    Expression<String>? albumId,
    Expression<String>? artist,
    Expression<String>? artistIds,
    Expression<String>? labels,
    Expression<int>? durationTicks,
    Expression<String>? imageTag,
    Expression<String>? container,
    Expression<bool>? favorite,
    Expression<int>? playCount,
    Expression<double>? normalizationGain,
    Expression<double>? albumNormalizationGain,
    Expression<DateTime>? lastPlayed,
    Expression<DateTime>? dateCreated,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (album != null) 'album': album,
      if (albumId != null) 'album_id': albumId,
      if (artist != null) 'artist': artist,
      if (artistIds != null) 'artist_ids': artistIds,
      if (labels != null) 'labels': labels,
      if (durationTicks != null) 'duration_ticks': durationTicks,
      if (imageTag != null) 'image_tag': imageTag,
      if (container != null) 'container': container,
      if (favorite != null) 'favorite': favorite,
      if (playCount != null) 'play_count': playCount,
      if (normalizationGain != null) 'normalization_gain': normalizationGain,
      if (albumNormalizationGain != null)
        'album_normalization_gain': albumNormalizationGain,
      if (lastPlayed != null) 'last_played': lastPlayed,
      if (dateCreated != null) 'date_created': dateCreated,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TracksCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? album,
    Value<String?>? albumId,
    Value<String>? artist,
    Value<String>? artistIds,
    Value<String>? labels,
    Value<int>? durationTicks,
    Value<String?>? imageTag,
    Value<String>? container,
    Value<bool>? favorite,
    Value<int>? playCount,
    Value<double?>? normalizationGain,
    Value<double?>? albumNormalizationGain,
    Value<DateTime?>? lastPlayed,
    Value<DateTime?>? dateCreated,
    Value<int>? rowid,
  }) {
    return TracksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      artist: artist ?? this.artist,
      artistIds: artistIds ?? this.artistIds,
      labels: labels ?? this.labels,
      durationTicks: durationTicks ?? this.durationTicks,
      imageTag: imageTag ?? this.imageTag,
      container: container ?? this.container,
      favorite: favorite ?? this.favorite,
      playCount: playCount ?? this.playCount,
      normalizationGain: normalizationGain ?? this.normalizationGain,
      albumNormalizationGain:
          albumNormalizationGain ?? this.albumNormalizationGain,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      dateCreated: dateCreated ?? this.dateCreated,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (artistIds.present) {
      map['artist_ids'] = Variable<String>(artistIds.value);
    }
    if (labels.present) {
      map['labels'] = Variable<String>(labels.value);
    }
    if (durationTicks.present) {
      map['duration_ticks'] = Variable<int>(durationTicks.value);
    }
    if (imageTag.present) {
      map['image_tag'] = Variable<String>(imageTag.value);
    }
    if (container.present) {
      map['container'] = Variable<String>(container.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (normalizationGain.present) {
      map['normalization_gain'] = Variable<double>(normalizationGain.value);
    }
    if (albumNormalizationGain.present) {
      map['album_normalization_gain'] = Variable<double>(
        albumNormalizationGain.value,
      );
    }
    if (lastPlayed.present) {
      map['last_played'] = Variable<DateTime>(lastPlayed.value);
    }
    if (dateCreated.present) {
      map['date_created'] = Variable<DateTime>(dateCreated.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('album: $album, ')
          ..write('albumId: $albumId, ')
          ..write('artist: $artist, ')
          ..write('artistIds: $artistIds, ')
          ..write('labels: $labels, ')
          ..write('durationTicks: $durationTicks, ')
          ..write('imageTag: $imageTag, ')
          ..write('container: $container, ')
          ..write('favorite: $favorite, ')
          ..write('playCount: $playCount, ')
          ..write('normalizationGain: $normalizationGain, ')
          ..write('albumNormalizationGain: $albumNormalizationGain, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('dateCreated: $dateCreated, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, Playlist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackIdsMeta = const VerificationMeta(
    'trackIds',
  );
  @override
  late final GeneratedColumn<String> trackIds = GeneratedColumn<String>(
    'track_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _imageTagMeta = const VerificationMeta(
    'imageTag',
  );
  @override
  late final GeneratedColumn<String> imageTag = GeneratedColumn<String>(
    'image_tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, trackIds, imageTag];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Playlist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('track_ids')) {
      context.handle(
        _trackIdsMeta,
        trackIds.isAcceptableOrUnknown(data['track_ids']!, _trackIdsMeta),
      );
    }
    if (data.containsKey('image_tag')) {
      context.handle(
        _imageTagMeta,
        imageTag.isAcceptableOrUnknown(data['image_tag']!, _imageTagMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Playlist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Playlist(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      trackIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_ids'],
      )!,
      imageTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_tag'],
      ),
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class Playlist extends DataClass implements Insertable<Playlist> {
  final String id;
  final String name;
  final String trackIds;
  final String? imageTag;
  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    this.imageTag,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['track_ids'] = Variable<String>(trackIds);
    if (!nullToAbsent || imageTag != null) {
      map['image_tag'] = Variable<String>(imageTag);
    }
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      name: Value(name),
      trackIds: Value(trackIds),
      imageTag: imageTag == null && nullToAbsent
          ? const Value.absent()
          : Value(imageTag),
    );
  }

  factory Playlist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Playlist(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      trackIds: serializer.fromJson<String>(json['trackIds']),
      imageTag: serializer.fromJson<String?>(json['imageTag']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'trackIds': serializer.toJson<String>(trackIds),
      'imageTag': serializer.toJson<String?>(imageTag),
    };
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? trackIds,
    Value<String?> imageTag = const Value.absent(),
  }) => Playlist(
    id: id ?? this.id,
    name: name ?? this.name,
    trackIds: trackIds ?? this.trackIds,
    imageTag: imageTag.present ? imageTag.value : this.imageTag,
  );
  Playlist copyWithCompanion(PlaylistsCompanion data) {
    return Playlist(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      trackIds: data.trackIds.present ? data.trackIds.value : this.trackIds,
      imageTag: data.imageTag.present ? data.imageTag.value : this.imageTag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Playlist(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('trackIds: $trackIds, ')
          ..write('imageTag: $imageTag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, trackIds, imageTag);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Playlist &&
          other.id == this.id &&
          other.name == this.name &&
          other.trackIds == this.trackIds &&
          other.imageTag == this.imageTag);
}

class PlaylistsCompanion extends UpdateCompanion<Playlist> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> trackIds;
  final Value<String?> imageTag;
  final Value<int> rowid;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.trackIds = const Value.absent(),
    this.imageTag = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    required String id,
    required String name,
    this.trackIds = const Value.absent(),
    this.imageTag = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Playlist> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? trackIds,
    Expression<String>? imageTag,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (trackIds != null) 'track_ids': trackIds,
      if (imageTag != null) 'image_tag': imageTag,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? trackIds,
    Value<String?>? imageTag,
    Value<int>? rowid,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      imageTag: imageTag ?? this.imageTag,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (trackIds.present) {
      map['track_ids'] = Variable<String>(trackIds.value);
    }
    if (imageTag.present) {
      map['image_tag'] = Variable<String>(imageTag.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('trackIds: $trackIds, ')
          ..write('imageTag: $imageTag, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadsTable extends Downloads
    with TableInfo<$DownloadsTable, Download> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localUriMeta = const VerificationMeta(
    'localUri',
  );
  @override
  late final GeneratedColumn<String> localUri = GeneratedColumn<String>(
    'local_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receivedBytesMeta = const VerificationMeta(
    'receivedBytes',
  );
  @override
  late final GeneratedColumn<int> receivedBytes = GeneratedColumn<int>(
    'received_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    trackId,
    status,
    localUri,
    error,
    receivedBytes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<Download> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('local_uri')) {
      context.handle(
        _localUriMeta,
        localUri.isAcceptableOrUnknown(data['local_uri']!, _localUriMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('received_bytes')) {
      context.handle(
        _receivedBytesMeta,
        receivedBytes.isAcceptableOrUnknown(
          data['received_bytes']!,
          _receivedBytesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackId};
  @override
  Download map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Download(
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      localUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_uri'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      receivedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_bytes'],
      )!,
    );
  }

  @override
  $DownloadsTable createAlias(String alias) {
    return $DownloadsTable(attachedDatabase, alias);
  }
}

class Download extends DataClass implements Insertable<Download> {
  final String trackId;
  final String status;
  final String? localUri;
  final String? error;
  final int receivedBytes;
  const Download({
    required this.trackId,
    required this.status,
    this.localUri,
    this.error,
    required this.receivedBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_id'] = Variable<String>(trackId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || localUri != null) {
      map['local_uri'] = Variable<String>(localUri);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['received_bytes'] = Variable<int>(receivedBytes);
    return map;
  }

  DownloadsCompanion toCompanion(bool nullToAbsent) {
    return DownloadsCompanion(
      trackId: Value(trackId),
      status: Value(status),
      localUri: localUri == null && nullToAbsent
          ? const Value.absent()
          : Value(localUri),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      receivedBytes: Value(receivedBytes),
    );
  }

  factory Download.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Download(
      trackId: serializer.fromJson<String>(json['trackId']),
      status: serializer.fromJson<String>(json['status']),
      localUri: serializer.fromJson<String?>(json['localUri']),
      error: serializer.fromJson<String?>(json['error']),
      receivedBytes: serializer.fromJson<int>(json['receivedBytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackId': serializer.toJson<String>(trackId),
      'status': serializer.toJson<String>(status),
      'localUri': serializer.toJson<String?>(localUri),
      'error': serializer.toJson<String?>(error),
      'receivedBytes': serializer.toJson<int>(receivedBytes),
    };
  }

  Download copyWith({
    String? trackId,
    String? status,
    Value<String?> localUri = const Value.absent(),
    Value<String?> error = const Value.absent(),
    int? receivedBytes,
  }) => Download(
    trackId: trackId ?? this.trackId,
    status: status ?? this.status,
    localUri: localUri.present ? localUri.value : this.localUri,
    error: error.present ? error.value : this.error,
    receivedBytes: receivedBytes ?? this.receivedBytes,
  );
  Download copyWithCompanion(DownloadsCompanion data) {
    return Download(
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      status: data.status.present ? data.status.value : this.status,
      localUri: data.localUri.present ? data.localUri.value : this.localUri,
      error: data.error.present ? data.error.value : this.error,
      receivedBytes: data.receivedBytes.present
          ? data.receivedBytes.value
          : this.receivedBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Download(')
          ..write('trackId: $trackId, ')
          ..write('status: $status, ')
          ..write('localUri: $localUri, ')
          ..write('error: $error, ')
          ..write('receivedBytes: $receivedBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(trackId, status, localUri, error, receivedBytes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Download &&
          other.trackId == this.trackId &&
          other.status == this.status &&
          other.localUri == this.localUri &&
          other.error == this.error &&
          other.receivedBytes == this.receivedBytes);
}

class DownloadsCompanion extends UpdateCompanion<Download> {
  final Value<String> trackId;
  final Value<String> status;
  final Value<String?> localUri;
  final Value<String?> error;
  final Value<int> receivedBytes;
  final Value<int> rowid;
  const DownloadsCompanion({
    this.trackId = const Value.absent(),
    this.status = const Value.absent(),
    this.localUri = const Value.absent(),
    this.error = const Value.absent(),
    this.receivedBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadsCompanion.insert({
    required String trackId,
    required String status,
    this.localUri = const Value.absent(),
    this.error = const Value.absent(),
    this.receivedBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : trackId = Value(trackId),
       status = Value(status);
  static Insertable<Download> custom({
    Expression<String>? trackId,
    Expression<String>? status,
    Expression<String>? localUri,
    Expression<String>? error,
    Expression<int>? receivedBytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackId != null) 'track_id': trackId,
      if (status != null) 'status': status,
      if (localUri != null) 'local_uri': localUri,
      if (error != null) 'error': error,
      if (receivedBytes != null) 'received_bytes': receivedBytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadsCompanion copyWith({
    Value<String>? trackId,
    Value<String>? status,
    Value<String?>? localUri,
    Value<String?>? error,
    Value<int>? receivedBytes,
    Value<int>? rowid,
  }) {
    return DownloadsCompanion(
      trackId: trackId ?? this.trackId,
      status: status ?? this.status,
      localUri: localUri ?? this.localUri,
      error: error ?? this.error,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (localUri.present) {
      map['local_uri'] = Variable<String>(localUri.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (receivedBytes.present) {
      map['received_bytes'] = Variable<int>(receivedBytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadsCompanion(')
          ..write('trackId: $trackId, ')
          ..write('status: $status, ')
          ..write('localUri: $localUri, ')
          ..write('error: $error, ')
          ..write('receivedBytes: $receivedBytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingWritesTable extends PendingWrites
    with TableInfo<$PendingWritesTable, PendingWrite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingWritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    targetId,
    payload,
    createdAt,
    attempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_writes';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingWrite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingWrite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingWrite(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $PendingWritesTable createAlias(String alias) {
    return $PendingWritesTable(attachedDatabase, alias);
  }
}

class PendingWrite extends DataClass implements Insertable<PendingWrite> {
  final String id;
  final String kind;
  final String targetId;
  final String payload;
  final DateTime createdAt;
  final int attempts;
  const PendingWrite({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.payload,
    required this.createdAt,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['target_id'] = Variable<String>(targetId);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  PendingWritesCompanion toCompanion(bool nullToAbsent) {
    return PendingWritesCompanion(
      id: Value(id),
      kind: Value(kind),
      targetId: Value(targetId),
      payload: Value(payload),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
    );
  }

  factory PendingWrite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingWrite(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      targetId: serializer.fromJson<String>(json['targetId']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'targetId': serializer.toJson<String>(targetId),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  PendingWrite copyWith({
    String? id,
    String? kind,
    String? targetId,
    String? payload,
    DateTime? createdAt,
    int? attempts,
  }) => PendingWrite(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    targetId: targetId ?? this.targetId,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
  );
  PendingWrite copyWithCompanion(PendingWritesCompanion data) {
    return PendingWrite(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingWrite(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, targetId, payload, createdAt, attempts);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingWrite &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.targetId == this.targetId &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts);
}

class PendingWritesCompanion extends UpdateCompanion<PendingWrite> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> targetId;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<int> rowid;
  const PendingWritesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.targetId = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingWritesCompanion.insert({
    required String id,
    required String kind,
    required String targetId,
    this.payload = const Value.absent(),
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       targetId = Value(targetId),
       createdAt = Value(createdAt);
  static Insertable<PendingWrite> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? targetId,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (targetId != null) 'target_id': targetId,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingWritesCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? targetId,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<int>? rowid,
  }) {
    return PendingWritesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      targetId: targetId ?? this.targetId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingWritesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DowntifyImportsTable extends DowntifyImports
    with TableInfo<$DowntifyImportsTable, DowntifyImport> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DowntifyImportsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jellyfinServerIdMeta = const VerificationMeta(
    'jellyfinServerId',
  );
  @override
  late final GeneratedColumn<String> jellyfinServerId = GeneratedColumn<String>(
    'jellyfin_server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jellyfinUserIdMeta = const VerificationMeta(
    'jellyfinUserId',
  );
  @override
  late final GeneratedColumn<String> jellyfinUserId = GeneratedColumn<String>(
    'jellyfin_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downtifyUrlMeta = const VerificationMeta(
    'downtifyUrl',
  );
  @override
  late final GeneratedColumn<String> downtifyUrl = GeneratedColumn<String>(
    'downtify_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _externalSongIdMeta = const VerificationMeta(
    'externalSongId',
  );
  @override
  late final GeneratedColumn<String> externalSongId = GeneratedColumn<String>(
    'external_song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _songJsonMeta = const VerificationMeta(
    'songJson',
  );
  @override
  late final GeneratedColumn<String> songJson = GeneratedColumn<String>(
    'song_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _matchedTrackIdMeta = const VerificationMeta(
    'matchedTrackId',
  );
  @override
  late final GeneratedColumn<String> matchedTrackId = GeneratedColumn<String>(
    'matched_track_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _messageShownMeta = const VerificationMeta(
    'messageShown',
  );
  @override
  late final GeneratedColumn<bool> messageShown = GeneratedColumn<bool>(
    'message_shown',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("message_shown" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    jellyfinServerId,
    jellyfinUserId,
    downtifyUrl,
    externalSongId,
    jobId,
    songJson,
    status,
    progress,
    message,
    filename,
    matchedTrackId,
    messageShown,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downtify_imports';
  @override
  VerificationContext validateIntegrity(
    Insertable<DowntifyImport> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('jellyfin_server_id')) {
      context.handle(
        _jellyfinServerIdMeta,
        jellyfinServerId.isAcceptableOrUnknown(
          data['jellyfin_server_id']!,
          _jellyfinServerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_jellyfinServerIdMeta);
    }
    if (data.containsKey('jellyfin_user_id')) {
      context.handle(
        _jellyfinUserIdMeta,
        jellyfinUserId.isAcceptableOrUnknown(
          data['jellyfin_user_id']!,
          _jellyfinUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_jellyfinUserIdMeta);
    }
    if (data.containsKey('downtify_url')) {
      context.handle(
        _downtifyUrlMeta,
        downtifyUrl.isAcceptableOrUnknown(
          data['downtify_url']!,
          _downtifyUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_downtifyUrlMeta);
    }
    if (data.containsKey('external_song_id')) {
      context.handle(
        _externalSongIdMeta,
        externalSongId.isAcceptableOrUnknown(
          data['external_song_id']!,
          _externalSongIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_externalSongIdMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    }
    if (data.containsKey('song_json')) {
      context.handle(
        _songJsonMeta,
        songJson.isAcceptableOrUnknown(data['song_json']!, _songJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_songJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    }
    if (data.containsKey('matched_track_id')) {
      context.handle(
        _matchedTrackIdMeta,
        matchedTrackId.isAcceptableOrUnknown(
          data['matched_track_id']!,
          _matchedTrackIdMeta,
        ),
      );
    }
    if (data.containsKey('message_shown')) {
      context.handle(
        _messageShownMeta,
        messageShown.isAcceptableOrUnknown(
          data['message_shown']!,
          _messageShownMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DowntifyImport map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DowntifyImport(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      jellyfinServerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jellyfin_server_id'],
      )!,
      jellyfinUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jellyfin_user_id'],
      )!,
      downtifyUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}downtify_url'],
      )!,
      externalSongId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_song_id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      ),
      songJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      ),
      matchedTrackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}matched_track_id'],
      ),
      messageShown: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}message_shown'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DowntifyImportsTable createAlias(String alias) {
    return $DowntifyImportsTable(attachedDatabase, alias);
  }
}

class DowntifyImport extends DataClass implements Insertable<DowntifyImport> {
  final String id;
  final String jellyfinServerId;
  final String jellyfinUserId;
  final String downtifyUrl;
  final String externalSongId;
  final String? jobId;
  final String songJson;
  final String status;
  final double progress;
  final String message;
  final String? filename;
  final String? matchedTrackId;
  final bool messageShown;
  final DateTime createdAt;
  final DateTime updatedAt;
  const DowntifyImport({
    required this.id,
    required this.jellyfinServerId,
    required this.jellyfinUserId,
    required this.downtifyUrl,
    required this.externalSongId,
    this.jobId,
    required this.songJson,
    required this.status,
    required this.progress,
    required this.message,
    this.filename,
    this.matchedTrackId,
    required this.messageShown,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['jellyfin_server_id'] = Variable<String>(jellyfinServerId);
    map['jellyfin_user_id'] = Variable<String>(jellyfinUserId);
    map['downtify_url'] = Variable<String>(downtifyUrl);
    map['external_song_id'] = Variable<String>(externalSongId);
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    map['song_json'] = Variable<String>(songJson);
    map['status'] = Variable<String>(status);
    map['progress'] = Variable<double>(progress);
    map['message'] = Variable<String>(message);
    if (!nullToAbsent || filename != null) {
      map['filename'] = Variable<String>(filename);
    }
    if (!nullToAbsent || matchedTrackId != null) {
      map['matched_track_id'] = Variable<String>(matchedTrackId);
    }
    map['message_shown'] = Variable<bool>(messageShown);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DowntifyImportsCompanion toCompanion(bool nullToAbsent) {
    return DowntifyImportsCompanion(
      id: Value(id),
      jellyfinServerId: Value(jellyfinServerId),
      jellyfinUserId: Value(jellyfinUserId),
      downtifyUrl: Value(downtifyUrl),
      externalSongId: Value(externalSongId),
      jobId: jobId == null && nullToAbsent
          ? const Value.absent()
          : Value(jobId),
      songJson: Value(songJson),
      status: Value(status),
      progress: Value(progress),
      message: Value(message),
      filename: filename == null && nullToAbsent
          ? const Value.absent()
          : Value(filename),
      matchedTrackId: matchedTrackId == null && nullToAbsent
          ? const Value.absent()
          : Value(matchedTrackId),
      messageShown: Value(messageShown),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DowntifyImport.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DowntifyImport(
      id: serializer.fromJson<String>(json['id']),
      jellyfinServerId: serializer.fromJson<String>(json['jellyfinServerId']),
      jellyfinUserId: serializer.fromJson<String>(json['jellyfinUserId']),
      downtifyUrl: serializer.fromJson<String>(json['downtifyUrl']),
      externalSongId: serializer.fromJson<String>(json['externalSongId']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      songJson: serializer.fromJson<String>(json['songJson']),
      status: serializer.fromJson<String>(json['status']),
      progress: serializer.fromJson<double>(json['progress']),
      message: serializer.fromJson<String>(json['message']),
      filename: serializer.fromJson<String?>(json['filename']),
      matchedTrackId: serializer.fromJson<String?>(json['matchedTrackId']),
      messageShown: serializer.fromJson<bool>(json['messageShown']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'jellyfinServerId': serializer.toJson<String>(jellyfinServerId),
      'jellyfinUserId': serializer.toJson<String>(jellyfinUserId),
      'downtifyUrl': serializer.toJson<String>(downtifyUrl),
      'externalSongId': serializer.toJson<String>(externalSongId),
      'jobId': serializer.toJson<String?>(jobId),
      'songJson': serializer.toJson<String>(songJson),
      'status': serializer.toJson<String>(status),
      'progress': serializer.toJson<double>(progress),
      'message': serializer.toJson<String>(message),
      'filename': serializer.toJson<String?>(filename),
      'matchedTrackId': serializer.toJson<String?>(matchedTrackId),
      'messageShown': serializer.toJson<bool>(messageShown),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DowntifyImport copyWith({
    String? id,
    String? jellyfinServerId,
    String? jellyfinUserId,
    String? downtifyUrl,
    String? externalSongId,
    Value<String?> jobId = const Value.absent(),
    String? songJson,
    String? status,
    double? progress,
    String? message,
    Value<String?> filename = const Value.absent(),
    Value<String?> matchedTrackId = const Value.absent(),
    bool? messageShown,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DowntifyImport(
    id: id ?? this.id,
    jellyfinServerId: jellyfinServerId ?? this.jellyfinServerId,
    jellyfinUserId: jellyfinUserId ?? this.jellyfinUserId,
    downtifyUrl: downtifyUrl ?? this.downtifyUrl,
    externalSongId: externalSongId ?? this.externalSongId,
    jobId: jobId.present ? jobId.value : this.jobId,
    songJson: songJson ?? this.songJson,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    message: message ?? this.message,
    filename: filename.present ? filename.value : this.filename,
    matchedTrackId: matchedTrackId.present
        ? matchedTrackId.value
        : this.matchedTrackId,
    messageShown: messageShown ?? this.messageShown,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DowntifyImport copyWithCompanion(DowntifyImportsCompanion data) {
    return DowntifyImport(
      id: data.id.present ? data.id.value : this.id,
      jellyfinServerId: data.jellyfinServerId.present
          ? data.jellyfinServerId.value
          : this.jellyfinServerId,
      jellyfinUserId: data.jellyfinUserId.present
          ? data.jellyfinUserId.value
          : this.jellyfinUserId,
      downtifyUrl: data.downtifyUrl.present
          ? data.downtifyUrl.value
          : this.downtifyUrl,
      externalSongId: data.externalSongId.present
          ? data.externalSongId.value
          : this.externalSongId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      songJson: data.songJson.present ? data.songJson.value : this.songJson,
      status: data.status.present ? data.status.value : this.status,
      progress: data.progress.present ? data.progress.value : this.progress,
      message: data.message.present ? data.message.value : this.message,
      filename: data.filename.present ? data.filename.value : this.filename,
      matchedTrackId: data.matchedTrackId.present
          ? data.matchedTrackId.value
          : this.matchedTrackId,
      messageShown: data.messageShown.present
          ? data.messageShown.value
          : this.messageShown,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DowntifyImport(')
          ..write('id: $id, ')
          ..write('jellyfinServerId: $jellyfinServerId, ')
          ..write('jellyfinUserId: $jellyfinUserId, ')
          ..write('downtifyUrl: $downtifyUrl, ')
          ..write('externalSongId: $externalSongId, ')
          ..write('jobId: $jobId, ')
          ..write('songJson: $songJson, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('message: $message, ')
          ..write('filename: $filename, ')
          ..write('matchedTrackId: $matchedTrackId, ')
          ..write('messageShown: $messageShown, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    jellyfinServerId,
    jellyfinUserId,
    downtifyUrl,
    externalSongId,
    jobId,
    songJson,
    status,
    progress,
    message,
    filename,
    matchedTrackId,
    messageShown,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DowntifyImport &&
          other.id == this.id &&
          other.jellyfinServerId == this.jellyfinServerId &&
          other.jellyfinUserId == this.jellyfinUserId &&
          other.downtifyUrl == this.downtifyUrl &&
          other.externalSongId == this.externalSongId &&
          other.jobId == this.jobId &&
          other.songJson == this.songJson &&
          other.status == this.status &&
          other.progress == this.progress &&
          other.message == this.message &&
          other.filename == this.filename &&
          other.matchedTrackId == this.matchedTrackId &&
          other.messageShown == this.messageShown &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DowntifyImportsCompanion extends UpdateCompanion<DowntifyImport> {
  final Value<String> id;
  final Value<String> jellyfinServerId;
  final Value<String> jellyfinUserId;
  final Value<String> downtifyUrl;
  final Value<String> externalSongId;
  final Value<String?> jobId;
  final Value<String> songJson;
  final Value<String> status;
  final Value<double> progress;
  final Value<String> message;
  final Value<String?> filename;
  final Value<String?> matchedTrackId;
  final Value<bool> messageShown;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DowntifyImportsCompanion({
    this.id = const Value.absent(),
    this.jellyfinServerId = const Value.absent(),
    this.jellyfinUserId = const Value.absent(),
    this.downtifyUrl = const Value.absent(),
    this.externalSongId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.songJson = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    this.message = const Value.absent(),
    this.filename = const Value.absent(),
    this.matchedTrackId = const Value.absent(),
    this.messageShown = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DowntifyImportsCompanion.insert({
    required String id,
    required String jellyfinServerId,
    required String jellyfinUserId,
    required String downtifyUrl,
    required String externalSongId,
    this.jobId = const Value.absent(),
    required String songJson,
    required String status,
    this.progress = const Value.absent(),
    this.message = const Value.absent(),
    this.filename = const Value.absent(),
    this.matchedTrackId = const Value.absent(),
    this.messageShown = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       jellyfinServerId = Value(jellyfinServerId),
       jellyfinUserId = Value(jellyfinUserId),
       downtifyUrl = Value(downtifyUrl),
       externalSongId = Value(externalSongId),
       songJson = Value(songJson),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DowntifyImport> custom({
    Expression<String>? id,
    Expression<String>? jellyfinServerId,
    Expression<String>? jellyfinUserId,
    Expression<String>? downtifyUrl,
    Expression<String>? externalSongId,
    Expression<String>? jobId,
    Expression<String>? songJson,
    Expression<String>? status,
    Expression<double>? progress,
    Expression<String>? message,
    Expression<String>? filename,
    Expression<String>? matchedTrackId,
    Expression<bool>? messageShown,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jellyfinServerId != null) 'jellyfin_server_id': jellyfinServerId,
      if (jellyfinUserId != null) 'jellyfin_user_id': jellyfinUserId,
      if (downtifyUrl != null) 'downtify_url': downtifyUrl,
      if (externalSongId != null) 'external_song_id': externalSongId,
      if (jobId != null) 'job_id': jobId,
      if (songJson != null) 'song_json': songJson,
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (message != null) 'message': message,
      if (filename != null) 'filename': filename,
      if (matchedTrackId != null) 'matched_track_id': matchedTrackId,
      if (messageShown != null) 'message_shown': messageShown,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DowntifyImportsCompanion copyWith({
    Value<String>? id,
    Value<String>? jellyfinServerId,
    Value<String>? jellyfinUserId,
    Value<String>? downtifyUrl,
    Value<String>? externalSongId,
    Value<String?>? jobId,
    Value<String>? songJson,
    Value<String>? status,
    Value<double>? progress,
    Value<String>? message,
    Value<String?>? filename,
    Value<String?>? matchedTrackId,
    Value<bool>? messageShown,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DowntifyImportsCompanion(
      id: id ?? this.id,
      jellyfinServerId: jellyfinServerId ?? this.jellyfinServerId,
      jellyfinUserId: jellyfinUserId ?? this.jellyfinUserId,
      downtifyUrl: downtifyUrl ?? this.downtifyUrl,
      externalSongId: externalSongId ?? this.externalSongId,
      jobId: jobId ?? this.jobId,
      songJson: songJson ?? this.songJson,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      filename: filename ?? this.filename,
      matchedTrackId: matchedTrackId ?? this.matchedTrackId,
      messageShown: messageShown ?? this.messageShown,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (jellyfinServerId.present) {
      map['jellyfin_server_id'] = Variable<String>(jellyfinServerId.value);
    }
    if (jellyfinUserId.present) {
      map['jellyfin_user_id'] = Variable<String>(jellyfinUserId.value);
    }
    if (downtifyUrl.present) {
      map['downtify_url'] = Variable<String>(downtifyUrl.value);
    }
    if (externalSongId.present) {
      map['external_song_id'] = Variable<String>(externalSongId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (songJson.present) {
      map['song_json'] = Variable<String>(songJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (matchedTrackId.present) {
      map['matched_track_id'] = Variable<String>(matchedTrackId.value);
    }
    if (messageShown.present) {
      map['message_shown'] = Variable<bool>(messageShown.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DowntifyImportsCompanion(')
          ..write('id: $id, ')
          ..write('jellyfinServerId: $jellyfinServerId, ')
          ..write('jellyfinUserId: $jellyfinUserId, ')
          ..write('downtifyUrl: $downtifyUrl, ')
          ..write('externalSongId: $externalSongId, ')
          ..write('jobId: $jobId, ')
          ..write('songJson: $songJson, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('message: $message, ')
          ..write('filename: $filename, ')
          ..write('matchedTrackId: $matchedTrackId, ')
          ..write('messageShown: $messageShown, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumReleaseKindsTable extends AlbumReleaseKinds
    with TableInfo<$AlbumReleaseKindsTable, AlbumReleaseKind> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumReleaseKindsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [albumId, kind];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'album_release_kinds';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlbumReleaseKind> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    } else if (isInserting) {
      context.missing(_albumIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {albumId};
  @override
  AlbumReleaseKind map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumReleaseKind(
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
    );
  }

  @override
  $AlbumReleaseKindsTable createAlias(String alias) {
    return $AlbumReleaseKindsTable(attachedDatabase, alias);
  }
}

class AlbumReleaseKind extends DataClass
    implements Insertable<AlbumReleaseKind> {
  final String albumId;
  final String kind;
  const AlbumReleaseKind({required this.albumId, required this.kind});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['album_id'] = Variable<String>(albumId);
    map['kind'] = Variable<String>(kind);
    return map;
  }

  AlbumReleaseKindsCompanion toCompanion(bool nullToAbsent) {
    return AlbumReleaseKindsCompanion(
      albumId: Value(albumId),
      kind: Value(kind),
    );
  }

  factory AlbumReleaseKind.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumReleaseKind(
      albumId: serializer.fromJson<String>(json['albumId']),
      kind: serializer.fromJson<String>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'albumId': serializer.toJson<String>(albumId),
      'kind': serializer.toJson<String>(kind),
    };
  }

  AlbumReleaseKind copyWith({String? albumId, String? kind}) =>
      AlbumReleaseKind(
        albumId: albumId ?? this.albumId,
        kind: kind ?? this.kind,
      );
  AlbumReleaseKind copyWithCompanion(AlbumReleaseKindsCompanion data) {
    return AlbumReleaseKind(
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      kind: data.kind.present ? data.kind.value : this.kind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumReleaseKind(')
          ..write('albumId: $albumId, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(albumId, kind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumReleaseKind &&
          other.albumId == this.albumId &&
          other.kind == this.kind);
}

class AlbumReleaseKindsCompanion extends UpdateCompanion<AlbumReleaseKind> {
  final Value<String> albumId;
  final Value<String> kind;
  final Value<int> rowid;
  const AlbumReleaseKindsCompanion({
    this.albumId = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumReleaseKindsCompanion.insert({
    required String albumId,
    required String kind,
    this.rowid = const Value.absent(),
  }) : albumId = Value(albumId),
       kind = Value(kind);
  static Insertable<AlbumReleaseKind> custom({
    Expression<String>? albumId,
    Expression<String>? kind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (albumId != null) 'album_id': albumId,
      if (kind != null) 'kind': kind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumReleaseKindsCompanion copyWith({
    Value<String>? albumId,
    Value<String>? kind,
    Value<int>? rowid,
  }) {
    return AlbumReleaseKindsCompanion(
      albumId: albumId ?? this.albumId,
      kind: kind ?? this.kind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumReleaseKindsCompanion(')
          ..write('albumId: $albumId, ')
          ..write('kind: $kind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $DownloadsTable downloads = $DownloadsTable(this);
  late final $PendingWritesTable pendingWrites = $PendingWritesTable(this);
  late final $DowntifyImportsTable downtifyImports = $DowntifyImportsTable(
    this,
  );
  late final $AlbumReleaseKindsTable albumReleaseKinds =
      $AlbumReleaseKindsTable(this);
  late final Index tracksName = Index(
    'tracks_name',
    'CREATE INDEX tracks_name ON tracks (name)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    playlists,
    downloads,
    pendingWrites,
    downtifyImports,
    albumReleaseKinds,
    tracksName,
  ];
}

typedef $$TracksTableCreateCompanionBuilder = TracksCompanion Function({
  required String id,
  required String name,
  Value<String> album,
  Value<String?> albumId,
  Value<String> artist,
  Value<String> artistIds,
  Value<String> labels,
  Value<int> durationTicks,
  Value<String?> imageTag,
  Value<String> container,
  Value<bool> favorite,
  Value<int> playCount,
  Value<double?> normalizationGain,
  Value<double?> albumNormalizationGain,
  Value<DateTime?> lastPlayed,
  Value<DateTime?> dateCreated,
  Value<int> rowid,
});
typedef $$TracksTableUpdateCompanionBuilder = TracksCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> album,
  Value<String?> albumId,
  Value<String> artist,
  Value<String> artistIds,
  Value<String> labels,
  Value<int> durationTicks,
  Value<String?> imageTag,
  Value<String> container,
  Value<bool> favorite,
  Value<int> playCount,
  Value<double?> normalizationGain,
  Value<double?> albumNormalizationGain,
  Value<DateTime?> lastPlayed,
  Value<DateTime?> dateCreated,
  Value<int> rowid,
});

class $$TracksTableFilterComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistIds => $composableBuilder(
    column: $table.artistIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get labels => $composableBuilder(
    column: $table.labels,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationTicks => $composableBuilder(
    column: $table.durationTicks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageTag => $composableBuilder(
    column: $table.imageTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get normalizationGain => $composableBuilder(
    column: $table.normalizationGain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get albumNormalizationGain => $composableBuilder(
    column: $table.albumNormalizationGain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateCreated => $composableBuilder(
    column: $table.dateCreated,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TracksTableOrderingComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistIds => $composableBuilder(
    column: $table.artistIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get labels => $composableBuilder(
    column: $table.labels,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationTicks => $composableBuilder(
    column: $table.durationTicks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageTag => $composableBuilder(
    column: $table.imageTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get normalizationGain => $composableBuilder(
    column: $table.normalizationGain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get albumNormalizationGain => $composableBuilder(
    column: $table.albumNormalizationGain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateCreated => $composableBuilder(
    column: $table.dateCreated,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get artistIds =>
      $composableBuilder(column: $table.artistIds, builder: (column) => column);

  GeneratedColumn<String> get labels =>
      $composableBuilder(column: $table.labels, builder: (column) => column);

  GeneratedColumn<int> get durationTicks => $composableBuilder(
    column: $table.durationTicks,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageTag =>
      $composableBuilder(column: $table.imageTag, builder: (column) => column);

  GeneratedColumn<String> get container =>
      $composableBuilder(column: $table.container, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<double> get normalizationGain => $composableBuilder(
    column: $table.normalizationGain,
    builder: (column) => column,
  );

  GeneratedColumn<double> get albumNormalizationGain => $composableBuilder(
    column: $table.albumNormalizationGain,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dateCreated => $composableBuilder(
    column: $table.dateCreated,
    builder: (column) => column,
  );
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TracksTable,
          Track,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (Track, BaseReferences<_$AppDatabase, $TracksTable, Track>),
          Track,
          PrefetchHooks Function()
        > {
  $$TracksTableTableManager(_$AppDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> artistIds = const Value.absent(),
                Value<String> labels = const Value.absent(),
                Value<int> durationTicks = const Value.absent(),
                Value<String?> imageTag = const Value.absent(),
                Value<String> container = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<double?> normalizationGain = const Value.absent(),
                Value<double?> albumNormalizationGain = const Value.absent(),
                Value<DateTime?> lastPlayed = const Value.absent(),
                Value<DateTime?> dateCreated = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion(
                id: id,
                name: name,
                album: album,
                albumId: albumId,
                artist: artist,
                artistIds: artistIds,
                labels: labels,
                durationTicks: durationTicks,
                imageTag: imageTag,
                container: container,
                favorite: favorite,
                playCount: playCount,
                normalizationGain: normalizationGain,
                albumNormalizationGain: albumNormalizationGain,
                lastPlayed: lastPlayed,
                dateCreated: dateCreated,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> album = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> artistIds = const Value.absent(),
                Value<String> labels = const Value.absent(),
                Value<int> durationTicks = const Value.absent(),
                Value<String?> imageTag = const Value.absent(),
                Value<String> container = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<double?> normalizationGain = const Value.absent(),
                Value<double?> albumNormalizationGain = const Value.absent(),
                Value<DateTime?> lastPlayed = const Value.absent(),
                Value<DateTime?> dateCreated = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion.insert(
                id: id,
                name: name,
                album: album,
                albumId: albumId,
                artist: artist,
                artistIds: artistIds,
                labels: labels,
                durationTicks: durationTicks,
                imageTag: imageTag,
                container: container,
                favorite: favorite,
                playCount: playCount,
                normalizationGain: normalizationGain,
                albumNormalizationGain: albumNormalizationGain,
                lastPlayed: lastPlayed,
                dateCreated: dateCreated,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TracksTable, Track>(table),
                  BaseReferences<_$AppDatabase, $TracksTable, Track>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TracksTable,
      Track,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (Track, BaseReferences<_$AppDatabase, $TracksTable, Track>),
      Track,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder = PlaylistsCompanion Function({
  required String id,
  required String name,
  Value<String> trackIds,
  Value<String?> imageTag,
  Value<int> rowid,
});
typedef $$PlaylistsTableUpdateCompanionBuilder = PlaylistsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> trackIds,
  Value<String?> imageTag,
  Value<int> rowid,
});

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackIds => $composableBuilder(
    column: $table.trackIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageTag => $composableBuilder(
    column: $table.imageTag,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackIds => $composableBuilder(
    column: $table.trackIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageTag => $composableBuilder(
    column: $table.imageTag,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get trackIds =>
      $composableBuilder(column: $table.trackIds, builder: (column) => column);

  GeneratedColumn<String> get imageTag =>
      $composableBuilder(column: $table.imageTag, builder: (column) => column);
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          Playlist,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (Playlist, BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>),
          Playlist,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> trackIds = const Value.absent(),
                Value<String?> imageTag = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion(
                id: id,
                name: name,
                trackIds: trackIds,
                imageTag: imageTag,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> trackIds = const Value.absent(),
                Value<String?> imageTag = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                id: id,
                name: name,
                trackIds: trackIds,
                imageTag: imageTag,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistsTable, Playlist>(table),
                  BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      Playlist,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (Playlist, BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>),
      Playlist,
      PrefetchHooks Function()
    >;
typedef $$DownloadsTableCreateCompanionBuilder = DownloadsCompanion Function({
  required String trackId,
  required String status,
  Value<String?> localUri,
  Value<String?> error,
  Value<int> receivedBytes,
  Value<int> rowid,
});
typedef $$DownloadsTableUpdateCompanionBuilder = DownloadsCompanion Function({
  Value<String> trackId,
  Value<String> status,
  Value<String?> localUri,
  Value<String?> error,
  Value<int> receivedBytes,
  Value<int> rowid,
});

class $$DownloadsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localUri => $composableBuilder(
    column: $table.localUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localUri => $composableBuilder(
    column: $table.localUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get localUri =>
      $composableBuilder(column: $table.localUri, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => column,
  );
}

class $$DownloadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadsTable,
          Download,
          $$DownloadsTableFilterComposer,
          $$DownloadsTableOrderingComposer,
          $$DownloadsTableAnnotationComposer,
          $$DownloadsTableCreateCompanionBuilder,
          $$DownloadsTableUpdateCompanionBuilder,
          (Download, BaseReferences<_$AppDatabase, $DownloadsTable, Download>),
          Download,
          PrefetchHooks Function()
        > {
  $$DownloadsTableTableManager(_$AppDatabase db, $DownloadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> trackId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> localUri = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> receivedBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion(
                trackId: trackId,
                status: status,
                localUri: localUri,
                error: error,
                receivedBytes: receivedBytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackId,
                required String status,
                Value<String?> localUri = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> receivedBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion.insert(
                trackId: trackId,
                status: status,
                localUri: localUri,
                error: error,
                receivedBytes: receivedBytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DownloadsTable, Download>(table),
                  BaseReferences<_$AppDatabase, $DownloadsTable, Download>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadsTable,
      Download,
      $$DownloadsTableFilterComposer,
      $$DownloadsTableOrderingComposer,
      $$DownloadsTableAnnotationComposer,
      $$DownloadsTableCreateCompanionBuilder,
      $$DownloadsTableUpdateCompanionBuilder,
      (Download, BaseReferences<_$AppDatabase, $DownloadsTable, Download>),
      Download,
      PrefetchHooks Function()
    >;
typedef $$PendingWritesTableCreateCompanionBuilder =
    PendingWritesCompanion Function({
      required String id,
      required String kind,
      required String targetId,
      Value<String> payload,
      required DateTime createdAt,
      Value<int> attempts,
      Value<int> rowid,
    });
typedef $$PendingWritesTableUpdateCompanionBuilder =
    PendingWritesCompanion Function({
      Value<String> id,
      Value<String> kind,
      Value<String> targetId,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<int> rowid,
    });

class $$PendingWritesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingWritesTable> {
  $$PendingWritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingWritesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingWritesTable> {
  $$PendingWritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingWritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingWritesTable> {
  $$PendingWritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$PendingWritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingWritesTable,
          PendingWrite,
          $$PendingWritesTableFilterComposer,
          $$PendingWritesTableOrderingComposer,
          $$PendingWritesTableAnnotationComposer,
          $$PendingWritesTableCreateCompanionBuilder,
          $$PendingWritesTableUpdateCompanionBuilder,
          (
            PendingWrite,
            BaseReferences<_$AppDatabase, $PendingWritesTable, PendingWrite>,
          ),
          PendingWrite,
          PrefetchHooks Function()
        > {
  $$PendingWritesTableTableManager(_$AppDatabase db, $PendingWritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingWritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingWritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingWritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingWritesCompanion(
                id: id,
                kind: kind,
                targetId: targetId,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String targetId,
                Value<String> payload = const Value.absent(),
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingWritesCompanion.insert(
                id: id,
                kind: kind,
                targetId: targetId,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingWritesTable, PendingWrite>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PendingWritesTable,
                    PendingWrite
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingWritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingWritesTable,
      PendingWrite,
      $$PendingWritesTableFilterComposer,
      $$PendingWritesTableOrderingComposer,
      $$PendingWritesTableAnnotationComposer,
      $$PendingWritesTableCreateCompanionBuilder,
      $$PendingWritesTableUpdateCompanionBuilder,
      (
        PendingWrite,
        BaseReferences<_$AppDatabase, $PendingWritesTable, PendingWrite>,
      ),
      PendingWrite,
      PrefetchHooks Function()
    >;
typedef $$DowntifyImportsTableCreateCompanionBuilder =
    DowntifyImportsCompanion Function({
      required String id,
      required String jellyfinServerId,
      required String jellyfinUserId,
      required String downtifyUrl,
      required String externalSongId,
      Value<String?> jobId,
      required String songJson,
      required String status,
      Value<double> progress,
      Value<String> message,
      Value<String?> filename,
      Value<String?> matchedTrackId,
      Value<bool> messageShown,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$DowntifyImportsTableUpdateCompanionBuilder =
    DowntifyImportsCompanion Function({
      Value<String> id,
      Value<String> jellyfinServerId,
      Value<String> jellyfinUserId,
      Value<String> downtifyUrl,
      Value<String> externalSongId,
      Value<String?> jobId,
      Value<String> songJson,
      Value<String> status,
      Value<double> progress,
      Value<String> message,
      Value<String?> filename,
      Value<String?> matchedTrackId,
      Value<bool> messageShown,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$DowntifyImportsTableFilterComposer
    extends Composer<_$AppDatabase, $DowntifyImportsTable> {
  $$DowntifyImportsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jellyfinServerId => $composableBuilder(
    column: $table.jellyfinServerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jellyfinUserId => $composableBuilder(
    column: $table.jellyfinUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get downtifyUrl => $composableBuilder(
    column: $table.downtifyUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalSongId => $composableBuilder(
    column: $table.externalSongId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songJson => $composableBuilder(
    column: $table.songJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matchedTrackId => $composableBuilder(
    column: $table.matchedTrackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get messageShown => $composableBuilder(
    column: $table.messageShown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DowntifyImportsTableOrderingComposer
    extends Composer<_$AppDatabase, $DowntifyImportsTable> {
  $$DowntifyImportsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jellyfinServerId => $composableBuilder(
    column: $table.jellyfinServerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jellyfinUserId => $composableBuilder(
    column: $table.jellyfinUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get downtifyUrl => $composableBuilder(
    column: $table.downtifyUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalSongId => $composableBuilder(
    column: $table.externalSongId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songJson => $composableBuilder(
    column: $table.songJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matchedTrackId => $composableBuilder(
    column: $table.matchedTrackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get messageShown => $composableBuilder(
    column: $table.messageShown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DowntifyImportsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DowntifyImportsTable> {
  $$DowntifyImportsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jellyfinServerId => $composableBuilder(
    column: $table.jellyfinServerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jellyfinUserId => $composableBuilder(
    column: $table.jellyfinUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get downtifyUrl => $composableBuilder(
    column: $table.downtifyUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get externalSongId => $composableBuilder(
    column: $table.externalSongId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get songJson =>
      $composableBuilder(column: $table.songJson, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get matchedTrackId => $composableBuilder(
    column: $table.matchedTrackId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get messageShown => $composableBuilder(
    column: $table.messageShown,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DowntifyImportsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DowntifyImportsTable,
          DowntifyImport,
          $$DowntifyImportsTableFilterComposer,
          $$DowntifyImportsTableOrderingComposer,
          $$DowntifyImportsTableAnnotationComposer,
          $$DowntifyImportsTableCreateCompanionBuilder,
          $$DowntifyImportsTableUpdateCompanionBuilder,
          (
            DowntifyImport,
            BaseReferences<
              _$AppDatabase,
              $DowntifyImportsTable,
              DowntifyImport
            >,
          ),
          DowntifyImport,
          PrefetchHooks Function()
        > {
  $$DowntifyImportsTableTableManager(
    _$AppDatabase db,
    $DowntifyImportsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DowntifyImportsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DowntifyImportsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DowntifyImportsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> jellyfinServerId = const Value.absent(),
                Value<String> jellyfinUserId = const Value.absent(),
                Value<String> downtifyUrl = const Value.absent(),
                Value<String> externalSongId = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String> songJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String?> filename = const Value.absent(),
                Value<String?> matchedTrackId = const Value.absent(),
                Value<bool> messageShown = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DowntifyImportsCompanion(
                id: id,
                jellyfinServerId: jellyfinServerId,
                jellyfinUserId: jellyfinUserId,
                downtifyUrl: downtifyUrl,
                externalSongId: externalSongId,
                jobId: jobId,
                songJson: songJson,
                status: status,
                progress: progress,
                message: message,
                filename: filename,
                matchedTrackId: matchedTrackId,
                messageShown: messageShown,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String jellyfinServerId,
                required String jellyfinUserId,
                required String downtifyUrl,
                required String externalSongId,
                Value<String?> jobId = const Value.absent(),
                required String songJson,
                required String status,
                Value<double> progress = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String?> filename = const Value.absent(),
                Value<String?> matchedTrackId = const Value.absent(),
                Value<bool> messageShown = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DowntifyImportsCompanion.insert(
                id: id,
                jellyfinServerId: jellyfinServerId,
                jellyfinUserId: jellyfinUserId,
                downtifyUrl: downtifyUrl,
                externalSongId: externalSongId,
                jobId: jobId,
                songJson: songJson,
                status: status,
                progress: progress,
                message: message,
                filename: filename,
                matchedTrackId: matchedTrackId,
                messageShown: messageShown,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DowntifyImportsTable, DowntifyImport>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DowntifyImportsTable,
                    DowntifyImport
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DowntifyImportsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DowntifyImportsTable,
      DowntifyImport,
      $$DowntifyImportsTableFilterComposer,
      $$DowntifyImportsTableOrderingComposer,
      $$DowntifyImportsTableAnnotationComposer,
      $$DowntifyImportsTableCreateCompanionBuilder,
      $$DowntifyImportsTableUpdateCompanionBuilder,
      (
        DowntifyImport,
        BaseReferences<_$AppDatabase, $DowntifyImportsTable, DowntifyImport>,
      ),
      DowntifyImport,
      PrefetchHooks Function()
    >;
typedef $$AlbumReleaseKindsTableCreateCompanionBuilder =
    AlbumReleaseKindsCompanion Function({
      required String albumId,
      required String kind,
      Value<int> rowid,
    });
typedef $$AlbumReleaseKindsTableUpdateCompanionBuilder =
    AlbumReleaseKindsCompanion Function({
      Value<String> albumId,
      Value<String> kind,
      Value<int> rowid,
    });

class $$AlbumReleaseKindsTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumReleaseKindsTable> {
  $$AlbumReleaseKindsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlbumReleaseKindsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumReleaseKindsTable> {
  $$AlbumReleaseKindsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlbumReleaseKindsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumReleaseKindsTable> {
  $$AlbumReleaseKindsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);
}

class $$AlbumReleaseKindsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlbumReleaseKindsTable,
          AlbumReleaseKind,
          $$AlbumReleaseKindsTableFilterComposer,
          $$AlbumReleaseKindsTableOrderingComposer,
          $$AlbumReleaseKindsTableAnnotationComposer,
          $$AlbumReleaseKindsTableCreateCompanionBuilder,
          $$AlbumReleaseKindsTableUpdateCompanionBuilder,
          (
            AlbumReleaseKind,
            BaseReferences<
              _$AppDatabase,
              $AlbumReleaseKindsTable,
              AlbumReleaseKind
            >,
          ),
          AlbumReleaseKind,
          PrefetchHooks Function()
        > {
  $$AlbumReleaseKindsTableTableManager(
    _$AppDatabase db,
    $AlbumReleaseKindsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumReleaseKindsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumReleaseKindsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumReleaseKindsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> albumId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumReleaseKindsCompanion(
                albumId: albumId,
                kind: kind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String albumId,
                required String kind,
                Value<int> rowid = const Value.absent(),
              }) => AlbumReleaseKindsCompanion.insert(
                albumId: albumId,
                kind: kind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AlbumReleaseKindsTable, AlbumReleaseKind>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AlbumReleaseKindsTable,
                    AlbumReleaseKind
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlbumReleaseKindsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlbumReleaseKindsTable,
      AlbumReleaseKind,
      $$AlbumReleaseKindsTableFilterComposer,
      $$AlbumReleaseKindsTableOrderingComposer,
      $$AlbumReleaseKindsTableAnnotationComposer,
      $$AlbumReleaseKindsTableCreateCompanionBuilder,
      $$AlbumReleaseKindsTableUpdateCompanionBuilder,
      (
        AlbumReleaseKind,
        BaseReferences<
          _$AppDatabase,
          $AlbumReleaseKindsTable,
          AlbumReleaseKind
        >,
      ),
      AlbumReleaseKind,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$DownloadsTableTableManager get downloads =>
      $$DownloadsTableTableManager(_db, _db.downloads);
  $$PendingWritesTableTableManager get pendingWrites =>
      $$PendingWritesTableTableManager(_db, _db.pendingWrites);
  $$DowntifyImportsTableTableManager get downtifyImports =>
      $$DowntifyImportsTableTableManager(_db, _db.downtifyImports);
  $$AlbumReleaseKindsTableTableManager get albumReleaseKinds =>
      $$AlbumReleaseKindsTableTableManager(_db, _db.albumReleaseKinds);
}
