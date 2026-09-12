import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import '../common/playlist_artwork.dart';

class SidebarPlaylists extends ConsumerWidget {
  const SidebarPlaylists({required this.onSelected, super.key});

  final ValueChanged<Playlist> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<Track>>(
        stream: ref.watch(allTracksStreamProvider),
        builder: (context, trackSnapshot) {
          final tracksById = {
            for (final track in trackSnapshot.data ?? const <Track>[])
              track.id: track,
          };
          return StreamBuilder<List<Playlist>>(
            stream: ref.watch(playlistsStreamProvider),
            builder: (context, playlistSnapshot) {
              final playlists = playlistSnapshot.data ?? const [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: SpotifinSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: SpotifinSpacing.lg,
                      right: SpotifinSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Playlists',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Create playlist',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _create(context, ref),
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: playlists.length,
                      itemBuilder: (context, index) => _PlaylistTarget(
                        playlist: playlists[index],
                        tracks: tracksInPlaylist(playlists[index], tracksById),
                        onTap: () => onSelected(playlists[index]),
                        onRename: () => _rename(context, ref, playlists[index]),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _requestName(context, title: 'Create playlist');
    if (name == null) return;
    await ref
        .read(appControllerProvider.notifier)
        .createPlaylist(name, const []);
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final name = await _requestName(
      context,
      title: 'Rename playlist',
      initialValue: playlist.name,
    );
    if (name == null || name == playlist.name) return;
    await ref
        .read(appControllerProvider.notifier)
        .renamePlaylist(playlist.id, name);
  }
}

class _PlaylistTarget extends ConsumerWidget {
  const _PlaylistTarget({
    required this.playlist,
    required this.tracks,
    required this.onTap,
    required this.onRename,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final VoidCallback onTap;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DragTarget<Track>(
    onAcceptWithDetails: (details) {
      ref
          .read(appControllerProvider.notifier)
          .addToPlaylist(playlist.id, details.data.id);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Added to ${playlist.name}')));
    },
    builder: (context, candidates, _) => Material(
      color: candidates.isEmpty
          ? Colors.transparent
          : SpotifinColors.interactive,
      borderRadius: BorderRadius.circular(SpotifinRadii.small),
      child: ListTile(
        dense: true,
        leading: PlaylistArtwork(tracks: tracks, size: 36),
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          tooltip: 'Playlist options',
          onSelected: (_) => onRename(),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'rename',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_rounded),
                title: Text('Rename'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _requestName(
  BuildContext context, {
  required String title,
  String initialValue = '',
}) async {
  var value = initialValue;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        onChanged: (next) => value = next,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, value),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final name = result?.trim();
  return name == null || name.isEmpty ? null : name;
}
