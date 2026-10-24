import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

import '../../app/theme.dart';

/// A browser link so downloads also support opening in a new tab or copying.
class NativeAppLink extends StatelessWidget {
  const NativeAppLink({super.key});

  @override
  Widget build(BuildContext context) => Link(
    uri: Uri.parse('https://github.com/pablopunk/spotifin/releases/latest'),
    target: LinkTarget.blank,
    builder: (context, followLink) => TextButton.icon(
      onPressed: followLink,
      style: TextButton.styleFrom(foregroundColor: SpotifinColors.textMuted),
      icon: const Icon(Icons.open_in_new_rounded, size: 16),
      label: const Text('Download the native app'),
    ),
  );
}
