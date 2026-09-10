import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/login_screen.dart';
import '../features/shell/shell_screen.dart';
import 'providers.dart';
import 'state/app_controller.dart';
import 'theme.dart';

class SpotifinApp extends ConsumerStatefulWidget {
  const SpotifinApp({super.key});

  @override
  ConsumerState<SpotifinApp> createState() => _SpotifinAppState();
}

class _SpotifinAppState extends ConsumerState<SpotifinApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(ref.read(appControllerProvider.notifier).initialize);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    return MaterialApp(
      title: 'Spotifin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: switch (state.status) {
        AppStatus.starting => const _StartupScreen(),
        AppStatus.signedOut => const LoginScreen(),
        AppStatus.ready => const ShellScreen(),
      },
    );
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
