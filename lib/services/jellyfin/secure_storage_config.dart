import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain service identifier for the Jellyfin session token on macOS.
///
/// Kept stable so macOS upgrades keep reading the same item.
const sessionMacAccountName = 'com.pablopunk.spotifin.session';

/// Secure storage for the Jellyfin session token.
///
/// iOS uses `first_unlock` accessibility
/// (`kSecAttrAccessibleAfterFirstUnlock`) so a saved session stays readable
/// on a normal unlocked foreground launch even after the device was locked or
/// restarted, and when audio/CarPlay wakes the app in the background. The
/// previous default (`unlocked` / `kSecAttrAccessibleWhenUnlocked`) fails
/// those launches with errSecInteractionNotAllowed (-25308, "User interaction
/// is not allowed."). The iOS service name is intentionally left at the
/// plugin default so existing items are found under the same account.
/// macOS behavior is unchanged.
FlutterSecureStorage buildSessionSecureStorage() => const FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  mOptions: MacOsOptions(
    accountName: sessionMacAccountName,
    usesDataProtectionKeychain: false,
  ),
);

/// True when [error] looks like Keychain errSecInteractionNotAllowed (-25308,
/// "User interaction is not allowed.").
bool isKeychainInteractionNotAllowed(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('-25308') ||
      text.contains('interactionnotallowed') ||
      (text.contains('user interaction') && text.contains('not allowed'));
}

/// True when [error] looks like Keychain errSecDuplicateItem (-25299).
///
/// A pre-migration entry can share the keychain account with a different
/// accessibility attribute, so the first write with the new options can
/// report a duplicate instead of updating the item in place.
bool isKeychainDuplicateItem(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('-25299') || text.contains('duplicate');
}

/// User-facing message for a failed saved-session restore.
///
/// A locked keychain gets actionable recovery steps (with the exact -25308
/// code kept for diagnostics); anything else keeps the raw error text.
String sessionRestoreErrorMessage(Object error) {
  if (isKeychainInteractionNotAllowed(error)) {
    return 'Could not open saved Spotifin data because the device keychain '
        'is locked (-25308 errSecInteractionNotAllowed: User interaction is '
        'not allowed). Unlock the device and reopen Spotifin; if this keeps '
        'happening, sign in again.';
  }
  return 'Could not open saved Spotifin data: $error';
}
