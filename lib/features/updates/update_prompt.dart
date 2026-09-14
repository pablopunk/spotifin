import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../services/updates/release_info.dart';

enum UpdatePromptAction { close, viewRelease }

Future<void> promptUpdateAvailable(
  BuildContext context,
  WidgetRef ref,
  ReleaseInfo release,
) async {
  final action = await showDialog<UpdatePromptAction>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(release.name),
      content: Text('Spotifin ${release.version} is available.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, UpdatePromptAction.close),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, UpdatePromptAction.viewRelease),
          child: const Text('View release'),
        ),
      ],
    ),
  );
  await ref.read(updateControllerProvider.notifier).dismiss();
  if (!context.mounted) return;
  if (action == UpdatePromptAction.viewRelease) {
    await _openRelease(context, release.url);
  }
}

Future<void> showUpToDateDialog(BuildContext context, String? version) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("You're up to date"),
        content: Text(
          version == null
              ? 'Spotifin is up to date.'
              : 'Spotifin $version is the latest version.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

Future<void> _openRelease(BuildContext context, String url) async {
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Could not open the release page.')),
  );
}
