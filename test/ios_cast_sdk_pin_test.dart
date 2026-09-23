import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards the iOS SwiftPM pin for the Google Cast SDK used by
// flutter_chrome_cast (see ios/Runner.xcworkspace/xcshareddata/swiftpm/).
//
// The plugin's ios/Package.swift declares an iOS 15.0 floor while depending
// on SRGSSR/google-cast-sdk with `from: "4.8.4"`. That range floats to 4.8.6,
// whose floor is iOS 16.0, and Xcode then fails the release build with:
// "The package product 'GoogleCast' requires minimum platform version 16.0
// for the iOS platform, but this target supports 15.0".
// Pinning google-cast-sdk to 4.8.4 (floor iOS 15.0) keeps the graph valid
// until the plugin raises its own floor to iOS 16.0.
void main() {
  test('google-cast-sdk is pinned to the iOS 15 compatible 4.8.4', () {
    final file = File(
      'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
    );
    expect(file.existsSync(), isTrue, reason: 'Package.resolved is missing');

    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final pins = decoded['pins'] as List<dynamic>;
    final pin = pins.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['identity'] == 'google-cast-sdk',
      orElse: () => <String, dynamic>{},
    );

    expect(pin, isNotEmpty, reason: 'google-cast-sdk pin is missing');
    expect(pin['location'], contains('SRGSSR/google-cast-sdk'));
    expect(pin['state']['version'], '4.8.4');
    expect(pin['state']['revision'], isNotEmpty);
  });
}
