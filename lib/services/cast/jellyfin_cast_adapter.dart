/// Jellyfin Cast receiver selection and server reachability checks.
///
/// The receiver fetches streams from the server itself (see
/// [JellyfinReceiverProtocol]), so the phone only picks the receiver app and
/// checks the server address is one a Chromecast can reach.
abstract final class JellyfinCastAdapter {
  /// Jellyfin Web Receiver app IDs shipped with the server.
  ///
  /// `F007D354` is the production receiver registered with Google;
  /// `6F511C87` tracks the receiver `master` branch. Resolved from the
  /// server `CastReceiverApplications` model where available; these pinned
  /// values are the fallback (see jellyfin-web `chromecastPlayer/plugin.js`
  /// and server `system.xml` defaults).
  static const String stableReceiverAppId = 'F007D354';
  static const String unstableReceiverAppId = '6F511C87';

  static String receiverAppId({bool unstable = false}) =>
      unstable ? unstableReceiverAppId : stableReceiverAppId;

  /// Whether the server URL can plausibly be fetched by a Chromecast.
  ///
  /// Chromecasts resolve DNS via Google servers and require HTTPS with a
  /// valid certificate plus a LAN-routable host. Plain `http://`,
  /// `localhost`, and `.local`-style hosts fail on the receiver even though
  /// the phone itself can play them.
  static bool isServerReachableByCast(Uri serverUrl) {
    if (serverUrl.scheme != 'https') return false;
    final host = serverUrl.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host.startsWith('127.') ||
        host == '[::1]') {
      return false;
    }
    return true;
  }

  /// User-visible reason when the server cannot be used for Cast, if any.
  static String? serverBlockerMessage(Uri serverUrl) {
    if (serverUrl.scheme != 'https') {
      return 'This Jellyfin server uses plain HTTP and cannot be reached '
          'by Chromecast. Use an HTTPS address to cast.';
    }
    final host = serverUrl.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host.startsWith('127.') ||
        host == '[::1]') {
      return 'This Jellyfin server address is only reachable from this '
          'phone. Chromecast needs a server address reachable on your '
          'Wi-Fi network.';
    }
    return null;
  }
}
