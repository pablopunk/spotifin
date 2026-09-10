import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../common/design_system.dart';

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
          SpotifinSettingsGroup(
            title: 'Account',
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: SpotifinColors.accent,
                  foregroundColor: Colors.black,
                  child: Icon(Icons.person_rounded),
                ),
                title: Text(session?.userName ?? ''),
                subtitle: Text(session?.serverUrl ?? ''),
              ),
            ],
          ),
          SpotifinSettingsGroup(
            title: 'Playback',
            children: [
              SwitchListTile(
                value: state.normalization,
                onChanged: ref
                    .read(appControllerProvider.notifier)
                    .setNormalization,
                title: const Text('Volume normalization'),
                subtitle: const Text('Use Jellyfin gain data when available'),
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.high_quality_rounded),
                title: const Text('Streaming quality'),
                subtitle: Text(
                  state.smallStreaming ? 'Small file' : 'Full quality',
                ),
                onTap: () => _chooseQuality(
                  context,
                  state.smallStreaming,
                  ref.read(appControllerProvider.notifier).setSmallStreaming,
                ),
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Download quality'),
                subtitle: Text(
                  state.smallDownloads ? 'Small file' : 'Full quality',
                ),
                onTap: () => _chooseQuality(
                  context,
                  state.smallDownloads,
                  ref.read(appControllerProvider.notifier).setSmallDownloads,
                ),
              ),
            ],
          ),
          SpotifinSettingsGroup(
            title: 'Library',
            children: [
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
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: SpotifinColors.negative,
                ),
                title: const Text('Sign out'),
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
          const SpotifinSettingsGroup(
            title: 'About',
            children: [
              AboutListTile(
                icon: Icon(Icons.info_outline_rounded),
                applicationName: 'Spotifin',
                applicationVersion: '1.0.0',
                applicationLegalese:
                    'Free and open-source Jellyfin music player',
              ),
            ],
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

  Future<void> _chooseQuality(
    BuildContext context,
    bool current,
    Future<void> Function(bool) save,
  ) async {
    final selected = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose quality'),
        children: [
          RadioGroup<bool>(
            groupValue: current,
            onChanged: (value) => Navigator.pop(context, value),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<bool>(
                  value: false,
                  title: Text('Full quality'),
                  subtitle: Text('Prefer the original audio'),
                ),
                RadioListTile<bool>(
                  value: true,
                  title: Text('Small file'),
                  subtitle: Text('AAC at about 128 kbps'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) await save(selected);
  }
}
