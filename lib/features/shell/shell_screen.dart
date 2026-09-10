import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../downloads/downloads_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../player/player_bar.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  int _index = 0;
  static const _screens = <Widget>[
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    DownloadsScreen(),
    SettingsScreen(),
  ];

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
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final content = Stack(
      children: [
        Positioned.fill(child: _screens[_index]),
        const Positioned(left: 0, right: 0, bottom: 0, child: PlayerBar()),
      ],
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              extended: MediaQuery.sizeOf(context).width >= 1150,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Icon(Icons.graphic_eq_rounded, size: 36),
              ),
              destinations: _destinations
                  .map(
                    (item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      label: Text(item.label),
                    ),
                  )
                  .toList(),
            ),
            Expanded(child: content),
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
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

const _destinations = [
  (icon: Icons.home_rounded, label: 'Home'),
  (icon: Icons.search_rounded, label: 'Search'),
  (icon: Icons.library_music_rounded, label: 'Library'),
  (icon: Icons.download_rounded, label: 'Downloads'),
  (icon: Icons.settings_rounded, label: 'Settings'),
];
