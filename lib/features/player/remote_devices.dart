import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/jellyfin/remote_session.dart';
import '../../services/playback/remote_session_service.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';

class RemoteDeviceButton extends ConsumerWidget {
  const RemoteDeviceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(remoteSessionProvider);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => IconButton(
        tooltip: 'Other devices',
        color: service.sessions.any((session) => session.isPlaying)
            ? SpotifinColors.accent
            : null,
        onPressed: () => showRemoteDevices(context, service),
        icon: const Icon(Icons.devices_rounded),
      ),
    );
  }
}

class RemoteNowPlayingBar extends ConsumerWidget {
  const RemoteNowPlayingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(remoteSessionProvider);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final active = service.sessions
            .where((session) => session.nowPlayingItemId != null)
            .toList();
        if (service.sessions.isEmpty) return const SizedBox.shrink();
        final session = active.isEmpty ? service.sessions.first : active.first;
        return Material(
          type: MaterialType.transparency,
          child: ListTile(
            minTileHeight: 72,
            onTap: () => showRemoteDevices(context, service),
            leading: session.nowPlayingItemId == null
                ? const SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.devices_rounded),
                  )
                : Artwork(
                    itemId: session.nowPlayingItemId!,
                    size: 48,
                    borderRadius: SpotifinRadii.small,
                  ),
            title: Text(
              session.nowPlayingItemName ?? session.deviceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              session.nowPlayingItemName == null
                  ? 'Nothing playing'
                  : '${session.deviceName} · ${session.nowPlayingArtist ?? 'Unknown artist'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: session.nowPlayingItemId == null
                ? const Icon(Icons.chevron_right_rounded)
                : IconButton(
                    tooltip: session.paused
                        ? 'Play on ${session.deviceName}'
                        : 'Pause ${session.deviceName}',
                    onPressed: service.pendingSessionIds.contains(session.id)
                        ? null
                        : () => _run(
                            context,
                            session.paused
                                ? service.play(session)
                                : service.pause(session),
                          ),
                    icon: Icon(
                      session.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

Future<void> showRemoteDevices(
  BuildContext context,
  RemoteSessionService service,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => _RemoteDevicesSheet(service: service),
);

class _RemoteDevicesSheet extends StatelessWidget {
  const _RemoteDevicesSheet({required this.service});

  final RemoteSessionService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              service.connected
                  ? Icons.sync_rounded
                  : Icons.sync_problem_rounded,
              color: service.connected
                  ? SpotifinColors.accent
                  : SpotifinColors.textMuted,
            ),
            title: const Text('Spotifin devices'),
            subtitle: Text(
              service.connected
                  ? 'Live updates connected'
                  : 'Using periodic updates',
            ),
            trailing: IconButton(
              tooltip: 'Refresh devices',
              onPressed: service.loading ? null : service.refresh,
              icon: service.loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
          if (service.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpotifinSpacing.md,
              ),
              child: Text(
                service.error!,
                style: const TextStyle(color: SpotifinColors.negative),
              ),
            ),
          const Divider(),
          Flexible(
            child: service.sessions.isEmpty
                ? const SpotifinEmptyState(
                    icon: Icons.devices_other_rounded,
                    title: 'No other Spotifin devices',
                    message: 'Open Spotifin on another signed-in device.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: service.sessions.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: SpotifinSpacing.sm),
                    itemBuilder: (context, index) => _RemoteDeviceCard(
                      service: service,
                      session: service.sessions[index],
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _RemoteDeviceCard extends StatelessWidget {
  const _RemoteDeviceCard({required this.service, required this.session});

  final RemoteSessionService service;
  final RemoteSession session;

  @override
  Widget build(BuildContext context) {
    final pending = service.pendingSessionIds.contains(session.id);
    final maximum = session.duration.inMilliseconds.toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SpotifinSpacing.md),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices_rounded),
              title: Text(session.deviceName),
              subtitle: Text(
                session.nowPlayingItemName == null
                    ? 'Nothing playing'
                    : '${session.nowPlayingItemName} · ${session.nowPlayingArtist ?? 'Unknown artist'}',
              ),
              trailing: pending
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            if (session.nowPlayingItemId != null) ...[
              if (session.canSeek && maximum > 0)
                Slider(
                  value: session.position.inMilliseconds.toDouble().clamp(
                    0,
                    maximum,
                  ),
                  max: maximum,
                  onChanged: pending
                      ? null
                      : (value) => _run(
                          context,
                          service.seek(
                            session,
                            Duration(milliseconds: value.round()),
                          ),
                        ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous on ${session.deviceName}',
                    onPressed: pending
                        ? null
                        : () => _run(context, service.previous(session)),
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton.filled(
                    tooltip: session.paused ? 'Play' : 'Pause',
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.black,
                      disabledForegroundColor: SpotifinColors.textMuted,
                    ),
                    onPressed: pending
                        ? null
                        : () => _run(
                            context,
                            session.paused
                                ? service.play(session)
                                : service.pause(session),
                          ),
                    icon: Icon(
                      session.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next on ${session.deviceName}',
                    onPressed: pending
                        ? null
                        : () => _run(context, service.next(session)),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  const SizedBox(width: SpotifinSpacing.md),
                  FilledButton.icon(
                    onPressed: pending
                        ? null
                        : () => _playHere(context, service, session),
                    icon: const Icon(Icons.move_to_inbox_rounded),
                    label: const Text('Play here'),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Volume down',
                    onPressed: pending
                        ? null
                        : () => _run(
                            context,
                            service.setVolume(session, session.volume - 10),
                          ),
                    icon: const Icon(Icons.volume_down_rounded),
                  ),
                  Text('${session.volume}%'),
                  IconButton(
                    tooltip: 'Volume up',
                    onPressed: pending
                        ? null
                        : () => _run(
                            context,
                            service.setVolume(session, session.volume + 10),
                          ),
                    icon: const Icon(Icons.volume_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Shuffle',
                    color: session.shuffle ? SpotifinColors.accent : null,
                    onPressed: pending
                        ? null
                        : () => _run(
                            context,
                            service.setShuffle(session, !session.shuffle),
                          ),
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                  IconButton(
                    tooltip: 'Repeat',
                    color: session.repeatMode == 'RepeatNone'
                        ? null
                        : SpotifinColors.accent,
                    onPressed: pending
                        ? null
                        : () => _run(
                            context,
                            service.setRepeatMode(
                              session,
                              _nextRepeatMode(session.repeatMode),
                            ),
                          ),
                    icon: Icon(
                      session.repeatMode == 'RepeatOne'
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _nextRepeatMode(String current) => switch (current) {
  'RepeatNone' => 'RepeatAll',
  'RepeatAll' => 'RepeatOne',
  _ => 'RepeatNone',
};

Future<void> _playHere(
  BuildContext context,
  RemoteSessionService service,
  RemoteSession session,
) async {
  final succeeded = await _run(context, service.takeOver(session));
  if (succeeded && context.mounted) Navigator.of(context).pop();
}

Future<bool> _run(BuildContext context, Future<void> action) async {
  try {
    await action;
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
    return false;
  }
}
