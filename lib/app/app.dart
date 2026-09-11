import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/login_screen.dart';
import '../features/shell/shell_controller.dart';
import '../features/shell/shell_screen.dart';
import 'app_shortcuts.dart';
import 'providers.dart';
import 'state/app_controller.dart';
import 'theme.dart';

class SpotifinApp extends ConsumerStatefulWidget {
  const SpotifinApp({super.key});

  @override
  ConsumerState<SpotifinApp> createState() => _SpotifinAppState();
}

class _SpotifinAppState extends ConsumerState<SpotifinApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _shellController = ShellController();

  @override
  void initState() {
    super.initState();
    Future.microtask(ref.read(appControllerProvider.notifier).initialize);
  }

  @override
  void dispose() {
    _shellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      appControllerProvider.select((state) => state.status),
    );
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Spotifin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) =>
          Material(type: MaterialType.transparency, child: child!),
      shortcuts: buildAppShortcuts(enabled: status == AppStatus.ready),
      actions: buildAppActions(
        onTogglePlayback: _togglePlayback,
        onOpenSearch: _openSearch,
        onPreviousTrack: _playPrevious,
        onNextTrack: _playNext,
      ),
      home: switch (status) {
        AppStatus.starting => const _StartupScreen(),
        AppStatus.signedOut => const LoginScreen(),
        AppStatus.ready => ShellScreen(controller: _shellController),
      },
    );
  }

  void _togglePlayback() {
    final playback = ref.read(playbackProvider);
    if (playback.currentTrack != null) playback.toggle();
  }

  void _openSearch() {
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _shellController.openSearch();
  }

  void _playPrevious() {
    final playback = ref.read(playbackProvider);
    if (playback.currentTrack != null) playback.previous();
  }

  void _playNext() {
    final playback = ref.read(playbackProvider);
    if (playback.currentTrack != null) playback.next();
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 72,
            color: SpotifinColors.accent,
          ),
          SizedBox(height: 24),
          CircularProgressIndicator(),
        ],
      ),
    ),
  );
}
