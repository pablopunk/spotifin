import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/database.dart';

Future<void> renamePlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final name = await requestPlaylistName(
    context,
    title: 'Rename playlist',
    initialValue: playlist.name,
  );
  if (name == null || name == playlist.name) return;
  await ref
      .read(appControllerProvider.notifier)
      .renamePlaylist(playlist.id, name);
}

Future<void> removePlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove playlist?'),
      content: Text('"${playlist.name}" will be deleted from Jellyfin.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(appControllerProvider.notifier).deletePlaylist(playlist.id);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

Future<String?> requestPlaylistName(
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
