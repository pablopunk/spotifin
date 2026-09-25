import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/cast/cast_controller.dart';
import '../../services/cast/cast_sender.dart';
import '../common/design_system.dart';

Future<void> showCastDevices(
  BuildContext context,
  CastController controller,
) async {
  await controller.initialize();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _CastDevicesSheet(controller: controller),
  );
  await controller.handleAppForeground();
}

class _CastDevicesSheet extends StatelessWidget {
  const _CastDevicesSheet({required this.controller});

  final CastController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              controller.isCasting
                  ? Icons.cast_connected_rounded
                  : Icons.cast_rounded,
              color: controller.isCasting
                  ? SpotifinColors.accent
                  : SpotifinColors.textMuted,
            ),
            title: const Text('Chromecast'),
            subtitle: Text(_statusText()),
            trailing: IconButton(
              tooltip: 'Refresh devices',
              onPressed: controller.busy || controller.initializing
                  ? null
                  : () => _run(context, controller.initialize()),
              icon: controller.initializing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpotifinSpacing.md,
              ),
              child: Text(
                controller.error!,
                style: const TextStyle(color: SpotifinColors.negative),
              ),
            ),
          if (controller.unavailableReason != null && !controller.isCasting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                controller.unavailableReason!,
                style: const TextStyle(color: SpotifinColors.textMuted),
              ),
            ),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.isCasting) _NowCasting(controller: controller),
                  if (controller.isCasting)
                    const SizedBox(height: SpotifinSpacing.md),
                  _DeviceList(controller: controller),
                  const SizedBox(height: SpotifinSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use unstable receiver'),
                    subtitle: const Text(
                      'Stable is recommended. Unstable tracks the receiver master branch.',
                    ),
                    value: controller.useUnstableReceiver,
                    onChanged: controller.busy
                        ? null
                        : (value) => _run(
                            context,
                            controller.setReceiverChannel(value),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  String _statusText() {
    if (controller.initializing) return 'Looking for devices…';
    if (controller.isCasting && controller.connectedDeviceName != null) {
      return 'Casting to ${controller.connectedDeviceName}';
    }
    if (controller.connectionState == CastConnectionState.connected) {
      return controller.connectedDeviceName == null
          ? 'Connected'
          : 'Connected to ${controller.connectedDeviceName}';
    }
    if (controller.connectionState == CastConnectionState.connecting ||
        controller.busy) {
      return 'Connecting…';
    }
    return 'Not connected';
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.controller});

  final CastController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.initializing) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (controller.devices.isEmpty) {
      return const SpotifinEmptyState(
        icon: Icons.cast_rounded,
        title: 'No Chromecasts found',
        message:
            'Make sure your Chromecast is on the same Wi-Fi network and '
            'that local network access is allowed for Spotifin.',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final device in controller.devices)
          _DeviceTile(controller: controller, deviceId: device.id),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.controller, required this.deviceId});

  final CastController controller;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final device = controller.devices.firstWhere(
      (item) => item.id == deviceId,
      orElse: () => controller.devices.first,
    );
    final isCurrent =
        controller.connectedDevice?.id == device.id ||
        controller.connectedDeviceName == device.friendlyName;
    final pending = controller.busy;
    return Card(
      child: ListTile(
        leading: Icon(
          isCurrent ? Icons.cast_connected_rounded : Icons.cast_rounded,
          color: isCurrent ? SpotifinColors.accent : null,
        ),
        title: Text(device.friendlyName),
        subtitle: Text(device.modelName ?? 'Chromecast'),
        trailing: pending
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : isCurrent
            ? TextButton(
                onPressed: () =>
                    _run(context, controller.disconnect(), popOnSuccess: true),
                child: const Text('Disconnect'),
              )
            : TextButton(
                onPressed: () => _run(context, controller.connect(device)),
                child: const Text('Connect'),
              ),
      ),
    );
  }
}

class _NowCasting extends StatelessWidget {
  const _NowCasting({required this.controller});

  final CastController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.remoteTrack;
    final duration = controller.remoteDuration ?? Duration.zero;
    final position = controller.remotePosition;
    final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SpotifinSpacing.md),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_rounded),
              title: Text(track?.name ?? 'Casting'),
              subtitle: Text(
                track == null
                    ? (controller.connectedDeviceName ?? '')
                    : '${track.artist} · ${controller.connectedDeviceName ?? 'Chromecast'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Slider(
              value: position.inMilliseconds.toDouble().clamp(0.0, max),
              max: max,
              onChanged: controller.busy
                  ? null
                  : (value) => _run(
                      context,
                      controller.seek(Duration(milliseconds: value.round())),
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(_time(position)), Text(_time(duration))],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous',
                  onPressed: controller.busy
                      ? null
                      : () => _run(context, controller.previous()),
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                SpotifinPlayButton(
                  playing: controller.remotePlaying,
                  onPressed: controller.busy
                      ? null
                      : () => _run(context, controller.toggle()),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: controller.busy
                      ? null
                      : () => _run(context, controller.next()),
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.volume_down_rounded, size: 20),
                Expanded(
                  child: Slider(
                    value: controller.remoteVolume.clamp(0.0, 1.0),
                    onChanged: controller.busy
                        ? null
                        : (value) => _run(context, controller.setVolume(value)),
                  ),
                ),
                const Icon(Icons.volume_up_rounded, size: 20),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => _run(context, controller.retry()),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reconnect'),
                ),
                const SizedBox(height: SpotifinSpacing.sm),
                FilledButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => _run(
                          context,
                          controller.disconnect(),
                          popOnSuccess: true,
                        ),
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Stop & resume here'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

Future<void> _run(
  BuildContext context,
  Future<void> action, {
  bool popOnSuccess = false,
}) async {
  try {
    await action;
    if (popOnSuccess && context.mounted) Navigator.of(context).pop();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
