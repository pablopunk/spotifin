import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

class SparkleUpdater {
  const SparkleUpdater._();

  static const _feedUrl =
      'https://github.com/pablopunk/spotifin/releases/latest/download/appcast.xml';

  static bool get supported => kReleaseMode && Platform.isMacOS;

  static Future<void> initialize() async {
    if (!supported) return;
    try {
      await autoUpdater.setFeedURL(_feedUrl);
      await autoUpdater.setScheduledCheckInterval(86400);
    } catch (_) {}
  }

  static Future<void> checkForUpdates() async {
    if (!supported) return;
    try {
      await autoUpdater.checkForUpdates();
    } catch (_) {}
  }
}
