import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/state/downtify_controller.dart';
import '../../services/downtify/downtify_models.dart';
import '../../services/downtify/import_policy.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import 'external_track_tile.dart';

class DowntifySettingsScreen extends ConsumerStatefulWidget {
  const DowntifySettingsScreen({super.key});

  @override
  ConsumerState<DowntifySettingsScreen> createState() =>
      _DowntifySettingsScreenState();
}

class _DowntifySettingsScreenState
    extends ConsumerState<DowntifySettingsScreen> {
  final _serverController = TextEditingController();
  final _searchController = SearchController();
  bool _seededAddress = false;
  bool _saving = false;

  @override
  void dispose() {
    _serverController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(downtifyControllerProvider);
    // Clear the query view whenever configuration or account identity
    // changes underneath the search.
    ref.listen(
      downtifyControllerProvider.select((value) => value.searchNonce),
      (_, _) {
        if (_searchController.text.isNotEmpty) _searchController.clear();
      },
    );
    final downloadQueue = state.imports
        .where((item) => isDownloadQueueRow(parseImportStatus(item.status)))
        .toList();
    final libraryImports = state.imports
        .where((item) => !isDownloadQueueRow(parseImportStatus(item.status)))
        .toList();
    if (!_seededAddress && state.serverUrl != null) {
      _seededAddress = true;
      _serverController.text = state.serverUrl!;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Downtify')),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: SpotifinChromeInsets.bottomOf(context),
        ),
        children: [
          SpotifinSettingsGroup(
            title: 'Connection',
            children: [
              Padding(
                padding: const EdgeInsets.all(SpotifinSpacing.md),
                child: TextField(
                  controller: _serverController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Downtify server',
                    hintText: 'https://downtify.example.com',
                  ),
                ),
              ),
              ListTile(
                leading: Icon(_availabilityIcon(state.availability)),
                title: Text(_availabilityLabel(state.availability)),
                subtitle: state.version == null
                    ? null
                    : Text('Downtify ${state.version}'),
                trailing: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Checking…' : 'Save and test'),
                ),
              ),
              if (state.serverUrl != null)
                ListTile(
                  leading: const Icon(Icons.link_off_rounded),
                  title: const Text('Remove integration'),
                  onTap: () async {
                    await ref
                        .read(downtifyControllerProvider.notifier)
                        .removeConfiguration();
                    _serverController.clear();
                    _seededAddress = false;
                  },
                ),
            ],
          ),
          const SpotifinSettingsGroup(
            title: 'Setup requirements',
            children: [
              ListTile(
                leading: Icon(Icons.lock_rounded),
                title: Text('Secure access'),
                subtitle: Text(
                  'Use an HTTPS address that this device can reach, such as through Tailscale.',
                ),
              ),
              ListTile(
                leading: Icon(Icons.folder_copy_rounded),
                title: Text('Shared music folder'),
                subtitle: Text(
                  'Mount Downtify’s download folder inside a Jellyfin music library.',
                ),
              ),
              ListTile(
                leading: Icon(Icons.manage_accounts_rounded),
                title: Text('Library scan permission'),
                subtitle: Text(
                  'Instant import needs Jellyfin scan permission; otherwise the song appears after its next scheduled scan.',
                ),
              ),
            ],
          ),
          if (state.available) ...[
            SpotifinSettingsGroup(
              title: 'Search Downtify',
              children: [
                Padding(
                  padding: const EdgeInsets.all(SpotifinSpacing.md),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'Search YouTube Music',
                    leading: const Icon(Icons.search_rounded),
                    onChanged: (value) => ref
                        .read(downtifyControllerProvider.notifier)
                        .search(value),
                  ),
                ),
                if (state.searching)
                  const Padding(
                    padding: EdgeInsets.all(SpotifinSpacing.md),
                    child: LinearProgressIndicator(),
                  ),
                for (final song in state.results) ExternalTrackTile(song: song),
              ],
            ),
            if (downloadQueue.isNotEmpty)
              SpotifinSettingsGroup(
                title: 'Download queue',
                children: [
                  for (final item in downloadQueue)
                    _ImportTile(item: item, queueItem: true),
                ],
              ),
            if (libraryImports.isNotEmpty)
              SpotifinSettingsGroup(
                title: 'Library imports',
                children: [
                  for (final item in libraryImports) _ImportTile(item: item),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(downtifyControllerProvider.notifier)
          .configure(_serverController.text);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ImportTile extends ConsumerWidget {
  const _ImportTile({required this.item, this.queueItem = false});

  final DowntifyImport item;
  final bool queueItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = DowntifySong.fromJson(
      jsonDecode(item.songJson) as Map<String, dynamic>,
    );
    final status = parseImportStatus(item.status);
    final origin = ref.watch(
      downtifyControllerProvider.select((state) => state.serverUrl),
    );
    // Imports from another origin stay stored and visible with their
    // original source, marked paused: no automatic or manual work runs on
    // them until that original URL is selected again.
    final foreign = origin != null && item.downtifyUrl != origin;
    return ListTile(
      leading: Icon(_importIcon(item.status)),
      title: Text(song.name),
      subtitle: Text(
        foreign ? 'Paused · ${_importLabel(item)}' : _importLabel(item),
      ),
      trailing: foreign
          ? null
          : queueItem
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canRetryImport(status))
                  IconButton(
                    tooltip: 'Retry import',
                    onPressed: () => ref
                        .read(downtifyControllerProvider.notifier)
                        .retry(item),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                IconButton(
                  tooltip: canRetryImport(status)
                      ? 'Remove from queue'
                      : 'Stop download',
                  onPressed: () => ref
                      .read(downtifyControllerProvider.notifier)
                      .removeFromQueue(item),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            )
          : item.status == 'imported'
          ? IconButton(
              tooltip: 'Dismiss',
              onPressed: () =>
                  ref.read(downtifyControllerProvider.notifier).dismiss(item),
              icon: const Icon(Icons.close_rounded),
            )
          : canRetryImport(status)
          ? IconButton(
              tooltip: 'Retry import',
              onPressed: () =>
                  ref.read(downtifyControllerProvider.notifier).retry(item),
              icon: const Icon(Icons.refresh_rounded),
            )
          : null,
    );
  }
}

IconData _availabilityIcon(DowntifyAvailability value) => switch (value) {
  DowntifyAvailability.loading => Icons.sync_rounded,
  DowntifyAvailability.unconfigured => Icons.cloud_off_rounded,
  DowntifyAvailability.available => Icons.cloud_done_rounded,
  DowntifyAvailability.unavailable => Icons.cloud_off_rounded,
};

String _availabilityLabel(DowntifyAvailability value) => switch (value) {
  DowntifyAvailability.loading => 'Checking connection',
  DowntifyAvailability.unconfigured => 'Not configured',
  DowntifyAvailability.available => 'Connected',
  DowntifyAvailability.unavailable => 'Server unavailable',
};

IconData _importIcon(String status) => switch (status) {
  'imported' => Icons.check_circle_rounded,
  'downloadFailed' || 'importTimedOut' => Icons.error_rounded,
  'requestingScan' ||
  'waitingForJellyfin' ||
  'scanDenied' => Icons.sync_rounded,
  _ => Icons.downloading_rounded,
};

String _importLabel(DowntifyImport item) => switch (item.status) {
  'submitting' => 'Submitting…',
  'queued' => 'Queued',
  'downloading' => 'Downloading ${item.progress.round()}%',
  'retrying' =>
    'Retrying ${item.retryCount} of ${DowntifyController.maxDownloadRetries}…',
  'requestingScan' => 'Starting Jellyfin scan…',
  'waitingForJellyfin' => 'Waiting for Jellyfin',
  'scanDenied' => 'Waiting for Jellyfin’s scheduled scan',
  'imported' => 'Available in Jellyfin',
  'downloadFailed' => item.message.isEmpty ? 'Download failed' : item.message,
  'importTimedOut' => 'Jellyfin has not found this song yet',
  _ => item.status,
};
