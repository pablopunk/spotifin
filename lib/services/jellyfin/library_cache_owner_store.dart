import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_scope.dart';
import 'session.dart';

/// Non-secret owner of the cached library: normalized server URL, server ID,
/// and user ID. Carries no token, password, or display name.
@immutable
class LibraryCacheOwner {
  const LibraryCacheOwner({
    required this.serverUrl,
    required this.serverId,
    required this.userId,
  });

  final String serverUrl;
  final String serverId;
  final String userId;

  /// Stable comparison key shared with [AccountLease.ownerKey].
  String get key => '$serverUrl|$serverId|$userId';

  Map<String, String> toJson() => {
    'serverUrl': serverUrl,
    'serverId': serverId,
    'userId': userId,
  };

  factory LibraryCacheOwner.fromJson(Map<String, dynamic> json) =>
      LibraryCacheOwner(
        serverUrl: json['serverUrl'] as String? ?? '',
        serverId: json['serverId'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
      );

  factory LibraryCacheOwner.fromSession(JellyfinSession session) =>
      LibraryCacheOwner(
        serverUrl: normalizeServerUrlForOwner(session.serverUrl),
        serverId: session.serverId,
        userId: session.userId,
      );
}

/// Persists the [LibraryCacheOwner] of the on-device library.
///
/// The marker lives separately from credentials because session expiry keeps
/// cached rows and pending edits while dropping the token. Marker writes must
/// go through [AccountScope.exclusive]/[AccountScope.commit] at the call
/// site; this store performs only the underlying preference read/write.
class LibraryCacheOwnerStore {
  LibraryCacheOwnerStore([SharedPreferences? preferences])
    : _preferencesOverride = preferences;

  final SharedPreferences? _preferencesOverride;

  /// Non-secret preference key for the owner marker.
  static const storageKey = 'libraryCacheOwner.v1';

  Future<SharedPreferences> _preferences() async =>
      _preferencesOverride ?? await SharedPreferences.getInstance();

  /// Loads the stored owner, or null when absent or unreadable.
  Future<LibraryCacheOwner?> load() async {
    final raw = (await _preferences()).getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final owner = LibraryCacheOwner.fromJson(decoded);
      if (owner.serverUrl.isEmpty || owner.userId.isEmpty) return null;
      return owner;
    } catch (_) {
      return null;
    }
  }

  /// Loads the stored owner key, or null when absent.
  Future<String?> loadKey() async => (await load())?.key;

  /// True when [marker] names [session]'s account.
  bool matches(LibraryCacheOwner? marker, JellyfinSession session) =>
      marker != null && marker.key == accountOwnerKeyForSession(session);

  /// True when [marker] names [ownerKey].
  bool matchesKey(LibraryCacheOwner? marker, String ownerKey) =>
      marker != null && marker.key == ownerKey;

  /// Stores ownership derived from [session].
  Future<void> saveOwner(JellyfinSession session) =>
      save(LibraryCacheOwner.fromSession(session));

  /// Stores [owner].
  Future<void> save(LibraryCacheOwner owner) async {
    await (await _preferences()).setString(
      storageKey,
      jsonEncode(owner.toJson()),
    );
  }

  /// Drops the stored marker.
  Future<void> clear() async {
    await (await _preferences()).remove(storageKey);
  }
}
