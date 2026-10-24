import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/link.dart';

import '../../app/theme.dart';

/// A browser link so downloads also support opening in a new tab or copying.
class NativeAppLink extends StatelessWidget {
  const NativeAppLink({this.iconOnly = false, super.key});

  final bool iconOnly;

  @override
  Widget build(BuildContext context) => Link(
    uri: Uri.parse('https://github.com/pablopunk/spotifin/releases/latest'),
    target: LinkTarget.blank,
    builder: (context, followLink) {
      if (iconOnly) {
        return IconButton(
          tooltip: 'Download native app',
          onPressed: followLink,
          icon: SvgPicture.asset(
            'assets/branding/github.svg',
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              SpotifinColors.textMuted,
              BlendMode.srcIn,
            ),
          ),
        );
      }
      return TextButton.icon(
        onPressed: followLink,
        style: TextButton.styleFrom(foregroundColor: SpotifinColors.textMuted),
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: const Text('Download the native app'),
      );
    },
  );
}
