import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import 'cast_device_sheet.dart';

/// Chromecast entry point for the player UI.
///
/// Hidden on platforms without a Cast sender SDK (desktop/web) so existing
/// surfaces stay unchanged there; the iPhone/iOS MVP (and Android via shared
/// code) shows a cast icon that opens the device picker.
class CastButton extends ConsumerWidget {
  const CastButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(castControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isSupported) return const SizedBox.shrink();
        final connected =
            controller.isCasting ||
            controller.connectionState.name == 'connected';
        return IconButton(
          tooltip: controller.connectedDeviceName == null
              ? 'Cast to Chromecast'
              : 'Casting to ${controller.connectedDeviceName}',
          color: connected ? SpotifinColors.accent : null,
          onPressed: () => showCastDevices(context, controller),
          icon: Icon(
            connected ? Icons.cast_connected_rounded : Icons.cast_rounded,
          ),
        );
      },
    );
  }
}
