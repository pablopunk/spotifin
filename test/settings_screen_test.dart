import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/settings/settings_screen.dart';

void main() {
  testWidgets('shows the real app version in the about dialog', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageInfoProvider.overrideWith(
            (ref) async => PackageInfo(
              appName: 'Spotifin',
              packageName: 'app.spotifin',
              version: '1.2.3',
              buildNumber: '45',
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('About Spotifin'));
    await tester.pumpAndSettle();

    expect(find.text('1.2.3 (45)'), findsOneWidget);
  });
}
