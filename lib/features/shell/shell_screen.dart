import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/playback/playback_service.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import '../common/glass.dart';
import '../downloads/downloads_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../player/player_bar.dart';
import '../player/player_side_panel.dart';
import '../settings/settings_screen.dart';
import 'shell_controller.dart';
import 'sidebar.dart';
import 'sidebar_playlists.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({required this.controller, super.key});

  final ShellController controller;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  static const _defaultPlayerPanelWidth = 420.0;
  static const _minimumPlayerPanelWidth = 320.0;

  late final PlaybackService _playback;
  double _playerPanelWidth = _defaultPlayerPanelWidth;
  final _navigatorKeys = List.generate(
    _destinations.length,
    (_) => GlobalKey<NavigatorState>(),
  );
  final _visitedDestinations = <int>{0};
  late final List<Widget> _screens = [
    HomeScreen(searchFocusNode: widget.controller.searchFocusNode),
    const LibraryScreen(),
    const DownloadsScreen(),
    const SettingsScreen(),
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

  void _openPlaylist(Playlist playlist) {
    _visitedDestinations.add(1);
    widget.controller.selectDestination(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKeys[1].currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistScreen(playlistId: playlist.id),
        ),
      );
    });
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= SpotifinBreakpoints.rail;
    final playerPanels = ref.watch(playerPanelProvider);
    final showPlayerPanel =
        width >= SpotifinBreakpoints.playerPanel &&
        !playerPanels.isEmpty &&
        _playback.currentTrack != null;
    final playerPanelWidth = showPlayerPanel
        ? _playerPanelWidth.clamp(_minimumPlayerPanelWidth, width * 0.5)
        : 0.0;
    final selectedIndex = widget.controller.selectedIndex;
    final glassEffects = ref.watch(glassEffectsProvider);
    final glassOpacity = ref.watch(glassOpacityProvider);
    _visitedDestinations.add(selectedIndex);
    final content = SpotifinChromeInsets(
      bottom: !wide && glassEffects
          ? SpotifinChromeInsets.glassMobileBottom
          : SpotifinChromeInsets.fallbackBottom,
      child: Stack(
        children: [
          Positioned.fill(child: _buildDestinationStack(selectedIndex)),
          if (!glassEffects)
            const Positioned(left: 0, right: 0, bottom: 0, child: PlayerBar()),
        ],
      ),
    );
    if (wide) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  SpotifinSidebar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: widget.controller.selectDestination,
                    extended: width >= SpotifinBreakpoints.extendedRail,
                    destinations: _destinations,
                    extendedContent: SidebarPlaylists(
                      onSelected: _openPlaylist,
                    ),
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
                                child: _buildDestinationStack(selectedIndex),
                              ),
                            ),
                          ),
                        ),
                        if (showPlayerPanel)
                          SizedBox(
                            width: playerPanelWidth,
                            child: Row(
                              children: [
                                _PanelResizeHandle(
                                  onDrag: (delta) => setState(() {
                                    _playerPanelWidth =
                                        (_playerPanelWidth - delta).clamp(
                                          _minimumPlayerPanelWidth,
                                          width * 0.5,
                                        );
                                  }),
                                ),
                                const Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(0, 8, 8, 96),
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
                ],
              ),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: PlayerBar()),
          ],
        ),
      );
    }
    if (glassEffects) {
      final hasTrack = _playback.currentTrack != null;
      return GlassScaffold(
        backgroundColor: SpotifinColors.background,
        settings: SpotifinGlass.settings(glassOpacity),
        topEdgeFade: false,
        bottomBar: GlassTabBar.bottom(
          settings: SpotifinGlass.settings(glassOpacity),
          indicatorSettings: SpotifinGlass.settings(glassOpacity),
          quality: GlassQuality.standard,
          backgroundQuality: GlassQuality.standard,
          showIndicator: true,
          indicatorPinchStrength: 0,
          selectedIndex: selectedIndex,
          onTabSelected: widget.controller.selectDestination,
          selectedIconColor: SpotifinColors.text,
          unselectedIconColor: SpotifinColors.textMuted,
          selectedLabelColor: SpotifinColors.text,
          unselectedLabelColor: SpotifinColors.textMuted,
          interactionGlowColor: SpotifinColors.accent,
          bottomAccessory: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: PlayerBar(),
          ),
          bottomAccessoryEnabled: hasTrack,
          bottomAccessoryHeight: 74,
          tabs: _destinations
              .map(
                (item) => GlassTab(
                  icon: Icon(item.icon),
                  activeIcon: Icon(item.selectedIcon),
                  label: item.label,
                ),
              )
              .toList(),
        ),
        body: content,
      );
    }
    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: widget.controller.selectDestination,
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

  Widget _buildDestinationStack(int selectedIndex) => IndexedStack(
    index: selectedIndex,
    children: List.generate(
      _screens.length,
      (index) => _visitedDestinations.contains(index)
          ? _buildDestinationNavigator(index)
          : const SizedBox.shrink(),
    ),
  );

  Widget _buildDestinationNavigator(int index) => Navigator(
    key: _navigatorKeys[index],
    onGenerateRoute: (_) =>
        MaterialPageRoute<void>(builder: (_) => _screens[index]),
  );
}

class _PanelResizeHandle extends StatelessWidget {
  const _PanelResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: const SizedBox(
        width: 8,
        child: Center(
          child: SizedBox(
            width: 2,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: SpotifinColors.border,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _destinations = <SpotifinSidebarDestination>[
  SpotifinSidebarDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
  ),
  SpotifinSidebarDestination(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music_rounded,
    label: 'Library',
  ),
  SpotifinSidebarDestination(
    icon: Icons.download_for_offline_outlined,
    selectedIcon: Icons.download_for_offline_rounded,
    label: 'Downloads',
  ),
  SpotifinSidebarDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: 'Settings',
  ),
];
