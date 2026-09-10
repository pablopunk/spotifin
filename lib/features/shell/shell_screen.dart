import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/playback/playback_service.dart';
import '../common/design_system.dart';
import '../downloads/downloads_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../player/player_bar.dart';
import '../player/player_side_panel.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  int _index = 0;
  late final PlaybackService _playback;
  static const _screens = <Widget>[
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    DownloadsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _playback = ref.read(playbackProvider)..addListener(_refreshPlaybackLayout);
  }

  @override
  void dispose() {
    _playback.removeListener(_refreshPlaybackLayout);
    super.dispose();
  }

  void _refreshPlaybackLayout() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appControllerProvider.select((state) => state.error), (
      _,
      error,
    ) {
      if (error == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      ref.read(appControllerProvider.notifier).clearError();
    });
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= SpotifinBreakpoints.rail;
    final playerPanels = ref.watch(playerPanelProvider);
    final showPlayerPanel =
        width >= SpotifinBreakpoints.playerPanel &&
        !playerPanels.isEmpty &&
        _playback.currentTrack != null;
    final content = Stack(
      children: [
        Positioned.fill(child: _screens[_index]),
        const Positioned(left: 0, right: 0, bottom: 0, child: PlayerBar()),
      ],
    );
    if (wide) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (index) =>
                        setState(() => _index = index),
                    extended: width >= SpotifinBreakpoints.extendedRail,
                    minWidth: 80,
                    minExtendedWidth: 220,
                    leading: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.graphic_eq_rounded,
                            size: 34,
                            color: SpotifinColors.accent,
                          ),
                          if (width >= SpotifinBreakpoints.extendedRail) ...[
                            const SizedBox(width: 10),
                            Text(
                              'Spotifin',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ],
                      ),
                    ),
                    destinations: _destinations
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                SpotifinRadii.card,
                              ),
                              child: ColoredBox(
                                color: SpotifinColors.background,
                                child: _screens[_index],
                              ),
                            ),
                          ),
                        ),
                        if (showPlayerPanel)
                          const SizedBox(
                            width: 420,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(0, 8, 8, 88),
                              child: ClipRRect(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(SpotifinRadii.card),
                                ),
                                child: PlayerSidePanel(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: PlayerBar()),
          ],
        ),
      );
    }
    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: _destinations
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

const _destinations = [
  (icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
  (icon: Icons.search_rounded, selectedIcon: Icons.search, label: 'Search'),
  (
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music_rounded,
    label: 'Library',
  ),
  (
    icon: Icons.download_for_offline_outlined,
    selectedIcon: Icons.download_for_offline_rounded,
    label: 'Downloads',
  ),
  (
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: 'Settings',
  ),
];
