import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final session = state.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(session?.userName ?? ''),
            subtitle: Text(session?.serverUrl ?? ''),
          ),
          const Divider(),
          const SwitchListTile(
            value: true,
            onChanged: null,
            title: Text('Volume normalization'),
            subtitle: Text('Use Jellyfin gain data when available'),
          ),
          const ListTile(
            leading: Icon(Icons.high_quality_rounded),
            title: Text('Streaming quality'),
            subtitle: Text('Full quality'),
          ),
          const ListTile(
            leading: Icon(Icons.download_rounded),
            title: Text('Download quality'),
            subtitle: Text('Full quality'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Refresh library'),
            subtitle: Text(
              state.syncing ? 'Refreshing…' : 'Sync from Jellyfin',
            ),
            onTap: state.syncing
                ? null
                : ref.read(appControllerProvider.notifier).refresh,
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            onTap: () => _confirmSignOut(context, ref),
          ),
          const AboutListTile(
            icon: Icon(Icons.info_outline_rounded),
            applicationName: 'Spotifin',
            applicationVersion: '1.0.0',
            applicationLegalese: 'Free and open-source Jellyfin music player',
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This removes local catalog data and the saved queue from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appControllerProvider.notifier).signOut();
    }
  }
}
