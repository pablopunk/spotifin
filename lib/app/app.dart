import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/login_screen.dart';
import '../features/common/brand_logo.dart';
import '../features/shell/shell_controller.dart';
import '../features/shell/shell_screen.dart';
import '../features/updates/update_prompt.dart';
import '../services/updates/release_info.dart';
import 'app_shortcuts.dart';
import 'providers.dart';
import 'state/app_controller.dart';
import 'theme.dart';

class SpotifinApp extends ConsumerStatefulWidget {
  const SpotifinApp({super.key});

  @override
  ConsumerState<SpotifinApp> createState() => _SpotifinAppState();
}

class _SpotifinAppState extends ConsumerState<SpotifinApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _shellController = ShellController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(ref.read(appControllerProvider.notifier).initialize);
    Future.microtask(
      ref.read(updateControllerProvider.notifier).checkOnStartup,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shellController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appControllerProvider.notifier).refresh(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      appControllerProvider.select((state) => state.status),
    );
    ref.listen(updateControllerProvider.select((state) => state.release), (
      previous,
      release,
    ) {
      if (release != null && previous?.version != release.version) {
        _showUpdatePrompt(release);
      }
    });
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

  Future<void> _showUpdatePrompt(ReleaseInfo release) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    await promptUpdateAvailable(context, ref, release);
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
          SpotifinLogo(size: 72),
          SizedBox(height: 24),
          CircularProgressIndicator(),
        ],
      ),
    ),
  );
}
